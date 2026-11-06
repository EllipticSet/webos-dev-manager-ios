import Crypto
import Foundation

/// The webOS operations the app offers, built on SSH commands and Luna calls.
struct DeviceService: Sendable {
  var session: DeviceSession
  var luna: LunaClient

  init(session: DeviceSession) {
    self.session = session
    luna = LunaClient(session: session)
  }

  /// IPKs wait here while the installer reads them; webOS 11 keeps it out of `/tmp`.
  private static let temporaryIPKDirectory = "/media/developer/temp"
  private static let responseTimeout: TimeInterval = 10 * 60

  // MARK: Device information

  func details() async throws -> DeviceDetails {
    let system = try await luna.call(
      "luna://com.webos.service.tv.systemproperty/getSystemInfo",
      parameters: ["keys": ["firmwareVersion", "modelName", "sdkVersion", "otaId"]],
      falseAsError: false)
    let os = try? await luna.call(
      "luna://com.palm.systemservice/osInfo/query",
      parameters: ["parameters": ["device_name", "webos_manufacturing_version", "webos_release"]])

    var details = DeviceDetails(
      modelName: system["modelName"] as? String,
      osVersion: (os?["webos_release"] as? String) ?? (system["sdkVersion"] as? String),
      otaID: system["otaId"] as? String,
      firmwareVersion: system["firmwareVersion"] as? String,
      socName: os?["device_name"] as? String
    )
    if details.otaID == nil,
      let response = try? await luna.call("luna://com.webos.service.sdx/getDeviceUuid"),
      let billing = response["billingId"] as? String
    {
      details.otaID = URLComponents(string: "?" + billing)?.queryItems?
        .first { $0.name == "modelName" }?.value
    }
    if details.socName == nil,
      let data = try? await session.read("/etc/prefs/properties/machineName")
    {
      details.socName = String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return details
  }

  func storage(mountPoint: String = "/media/developer") async throws -> StorageInfo? {
    StorageInfo.parse(df: try await session.run("df \(mountPoint.shellQuoted)").text)
  }

  func homebrewConfiguration() async throws -> HomebrewConfiguration {
    let response = try await luna.call("luna://org.webosbrew.hbchannel.service/getConfiguration")
    return HomebrewConfiguration(
      root: response["root"] as? Bool,
      telnetDisabled: response["telnetDisabled"] as? Bool,
      failsafe: response["failsafe"] as? Bool,
      sshdEnabled: response["sshdEnabled"] as? Bool,
      blockUpdates: response["blockUpdates"] as? Bool
    )
  }

  func extendDevMode() async throws {
    try await launch(appID: "com.palmdts.devmode", parameters: ["extend": true])
  }

  /// The session token the Developer Mode app saved on the TV, if it looks valid.
  func devModeToken() async throws -> String? {
    let data = try await session.read("/var/luna/preferences/devmode_enabled")
    let token = String(decoding: data, as: UTF8.self)
    return token.wholeMatch(of: /[0-9a-zA-Z]+/) != nil ? token : nil
  }

  /// Captures the screen and returns the PNG. Needs root, like the desktop app.
  func screenshot(method: ScreenshotMethod) async throws -> Data {
    let path = "/tmp/devman_shot_\(UUID().uuidString).png"
    let parameters: [String: Any] = ["path": path, "method": method.rawValue, "format": "PNG"]
    do {
      try await luna.call(
        "luna://com.webos.service.capture/executeOneShot", parameters: parameters, isPublic: false)
    } catch DeviceError.lunaServiceNotFound {
      try await legacyScreenshot(parameters: parameters)
    }
    defer { Task { try? await session.remove(path, recursive: false) } }
    return try await session.read(path)
  }

  /// Older webOS uses another service, and some models need an explicit size.
  private func legacyScreenshot(parameters: [String: Any]) async throws {
    let uri = "luna://com.webos.service.tv.capture/executeOneShot"
    do {
      try await luna.call(uri, parameters: parameters, isPublic: false)
    } catch DeviceError.lunaResponse(let text)
      where text.contains("CAPTURE_ERROR_03") || text.localizedCaseInsensitiveContains("out of range")
    {
      try await luna.call(
        uri, parameters: parameters.merging(["width": 1920, "height": 1080]) { $1 },
        isPublic: false)
    }
  }

  // MARK: Apps

  func installedApps() async throws -> [InstalledApp] {
    let response: LunaResponse
    do {
      response = try await luna.call("luna://com.webos.applicationManager/dev/listApps")
    } catch DeviceError.lunaUnknownMethod {
      response = try await luna.call("luna://com.webos.applicationManager/listApps", isPublic: false)
    }
    let data = try JSONSerialization.data(withJSONObject: response["apps"] ?? [])
    return try JSONDecoder().decode([InstalledApp].self, from: data)
      .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
  }

  func launch(appID: String, parameters: [String: Any]? = nil) async throws {
    var body: [String: Any] = ["id": appID, "subscribe": false]
    if let parameters { body["params"] = parameters }
    try await luna.call("luna://com.webos.applicationManager/launch", parameters: body)
  }

  func uninstall(appID: String) async throws {
    let stream = try luna.subscribe(
      "luna://com.webos.appInstallService/dev/remove",
      parameters: ["id": appID, "subscribe": true])
    try await waitForResult(of: stream, operation: "uninstall") {
      try Self.isFinished(appInstallResponse: $0, expected: /removed/.ignoresCase())
    }
  }

  func install(fileAt url: URL, progress: @escaping @Sendable (Double?, String) -> Void) async throws {
    let path = try await upload(url, progress: progress)
    try await developerInstall(remotePath: path, progress: progress)
  }

  func install(manifest: PackageManifest, progress: @escaping @Sendable (Double?, String) -> Void)
    async throws
  {
    var homebrewFailure: Error?
    if (try? await homebrewConfiguration()) != nil {
      do {
        try await homebrewInstall(manifest: manifest, progress: progress)
        return
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        // The Homebrew Channel must never be reinstalled over itself with the default installer.
        if case DeviceError.insufficientSpace = error { throw error }
        if manifest.id == InstalledApp.homebrewChannelID { throw error }
        homebrewFailure = error
      }
    }
    do {
      try await developerInstall(manifest: manifest, progress: progress)
    } catch {
      // The first failure says more than the fallback's, which often just lacks Developer Mode.
      if Task.isCancelled { throw CancellationError() }
      throw homebrewFailure ?? error
    }
  }

  private func developerInstall(
    manifest: PackageManifest, progress: @escaping @Sendable (Double?, String) -> Void
  ) async throws {
    guard let source = URL(string: manifest.ipkUrl) else { throw DeviceError.invalidResponse }
    progress(nil, "Downloading IPK to iPhone…")
    let (location, response) = try await URLSession.shared.download(from: source)
    defer { try? FileManager.default.removeItem(at: location) }
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
      throw DeviceError.repository("Download failed (HTTP \(http.statusCode)).")
    }
    try Self.verify(fileAt: location, sha256: manifest.ipkHash?.sha256)
    let path = try await upload(location, progress: progress)
    try await developerInstall(remotePath: path, progress: progress)
  }

  /// Rejects a download that doesn't match the hash the repository published.
  static func verify(fileAt url: URL, sha256 expected: String?) throws {
    guard let expected else { return }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
      hasher.update(data: chunk)
    }
    let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
    guard digest == expected.lowercased() else {
      throw DeviceError.repository("The downloaded package doesn't match the repository's checksum.")
    }
  }

  private func upload(_ url: URL, progress: @escaping @Sendable (Double?, String) -> Void)
    async throws -> String
  {
    try await session.run(
      "mkdir -p \(Self.temporaryIPKDirectory) && chmod 777 \(Self.temporaryIPKDirectory)")
    let path = "\(Self.temporaryIPKDirectory)/devman_dl_\(UUID().uuidString).ipk"
    progress(nil, "Sending IPK to TV…")
    do {
      try await session.upload(url, to: path) { progress($0, "Sending IPK to TV…") }
    } catch {
      // Separate from this task, which may be the one that was cancelled.
      Task { try? await session.remove(path, recursive: false) }
      throw error
    }
    return path
  }

  private func developerInstall(
    remotePath: String, progress: @escaping @Sendable (Double?, String) -> Void
  ) async throws {
    defer { Task { try? await session.remove(remotePath, recursive: false) } }
    progress(nil, "Installing on TV…")
    let stream = try luna.subscribe(
      "luna://com.webos.appInstallService/dev/install",
      parameters: ["id": "com.ares.defaultName", "ipkUrl": remotePath, "subscribe": true])
    try await waitForResult(of: stream, operation: "install") {
      try Self.isFinished(appInstallResponse: $0, expected: /installed/.ignoresCase())
    }
  }

  private func homebrewInstall(
    manifest: PackageManifest, progress: @escaping @Sendable (Double?, String) -> Void
  ) async throws {
    var parameters: [String: Any] = ["ipkUrl": manifest.ipkUrl, "subscribe": true]
    if let hash = manifest.ipkHash?.sha256 { parameters["ipkHash"] = hash }
    let stream = try luna.subscribe(
      "luna://org.webosbrew.hbchannel.service/install", parameters: parameters)
    try await waitForResult(of: stream, operation: "install") { response in
      if response["returnValue"] as? Bool == false {
        let text = response["errorText"] as? String ?? "Unknown error"
        if text.wholeMatch(of: /.*-5: +FAILED_IPKG_INSTALL.*/) != nil {
          throw DeviceError.insufficientSpace
        }
        throw DeviceError.installFailed(text)
      }
      if response["finished"] as? Bool == true { return true }
      if response["subscribed"] as? Bool == false, response["returnValue"] as? Bool == true {
        return true
      }
      let fraction = (response["progress"] as? Double).map { $0 / 100 }
      progress(fraction, response["statusText"] as? String ?? "Installing on TV…")
      return false
    }
  }

  static func isFinished(appInstallResponse response: LunaResponse, expected: some RegexComponent)
    throws -> Bool
  {
    let details = response["details"] as? [String: Any]
    let state = details?["state"] as? String ?? ""
    if state.localizedCaseInsensitiveContains("FAILED") {
      if let reason = details?["reason"] as? String {
        let code = details?["errorCode"] as? Int
        if reason == "FAILED_IPKG_INSTALL", code == -5 { throw DeviceError.insufficientSpace }
        throw DeviceError.installFailed(code.map { "\($0): \(reason)" } ?? reason)
      }
      throw DeviceError.installFailed(state)
    }
    if response["returnValue"] as? Bool == false {
      throw DeviceError.installFailed(response["errorText"] as? String ?? "Unknown error")
    }
    return state.uppercased().hasPrefix("SUCCESS") || state.firstMatch(of: expected) != nil
  }

  /// Waits for a final response. Installs can take minutes, so only silence counts as a timeout.
  private func waitForResult(
    of stream: AsyncThrowingStream<LunaResponse, Error>, operation: String,
    isFinished: @escaping @Sendable (LunaResponse) throws -> Bool
  ) async throws {
    let activity = ActivityClock()
    let reader = UncheckedBox(stream)
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        for try await response in reader.value {
          activity.touch()
          if try isFinished(response) { return }
        }
        try Task.checkCancellation()
        throw DeviceError.installFailed(
          "the connection closed before the TV reported the \(operation) result.")
      }
      group.addTask {
        while activity.secondsSinceLastTouch < Self.responseTimeout {
          try await Task.sleep(for: .seconds(5))
        }
        throw DeviceError.timedOut
      }
      defer { group.cancelAll() }
      try await group.next()
    }
  }
}

private struct UncheckedBox<Value>: @unchecked Sendable {
  var value: Value
  init(_ value: Value) { self.value = value }
}

