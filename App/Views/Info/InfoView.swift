import SwiftUI

struct InfoView: View {
  var device: Device

  @Environment(DeviceStore.self) private var store
  @Environment(OperationCenter.self) private var operations
  @State private var details: LoadState<DeviceDetails> = .loading
  @State private var storage: StorageInfo?
  @State private var devMode: DevModeStatus?
  @State private var homebrewApp: InstalledApp?
  @State private var homebrewConfig: HomebrewConfiguration?
  @State private var homebrewRelease: RepositoryItem?
  @State private var screenshot: ScreenshotImage?
  @State private var renewalScript: RenewalScriptFile?

  private var service: DeviceService { store.service(for: device) }

  var body: some View {
    NavigationStack {
      Group {
        switch details {
        case .loading:
          ProgressView("Connecting…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
          ErrorStateView(message: message) { Task { await load() } }
        case .loaded(let details):
          form(details)
        }
      }
      .navigationTitle("Info")
      .appMenu()
      .task { if details.value == nil { await load() } }
      .sheet(item: $screenshot) { ScreenshotView(screenshot: $0) }
      .sheet(item: $renewalScript) { RenewalScriptView(script: $0) }
    }
  }

  private func form(_ details: DeviceDetails) -> some View {
    Form {
      Section("TV") {
        DetailRow(title: "Name", value: device.name)
        if let value = details.modelName { DetailRow(title: "Model", value: value) }
        if let value = details.osVersion { DetailRow(title: "webOS", value: value) }
        if let value = details.firmwareVersion { DetailRow(title: "Firmware", value: value) }
        if let value = details.otaID { DetailRow(title: "OTA ID", value: value) }
        if let value = details.socName { DetailRow(title: "SoC", value: value) }
      }

      if let storage {
        Section("App Storage") {
          Gauge(value: storage.usedFraction) {
            Text("Used")
          } currentValueLabel: {
            Text(storage.usedFraction.formatted(.percent.precision(.fractionLength(0))))
          }
          // The separator otherwise starts where the centered label does.
          .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
          let free = Measurement(value: Double(storage.availableKilobytes), unit: UnitInformationStorage.kilobytes)
          DetailRow(title: "Available", value: free.formatted(.byteCount(style: .file)))
        }
      }

      if device.isDevMode {
        Section {
          devModeRemainingRow
          Button("Renew Session", systemImage: "arrow.clockwise") { renew() }
          if let token = devMode?.token {
            Button("Auto-Renewal Script…", systemImage: "scroll") {
              renewalScript = RenewalScriptFile(deviceName: device.name, token: token)
            }
          }
        } header: {
          Text("Developer Mode")
        } footer: {
          Text("The session expires after a period set by LG, and the TV removes installed apps if it isn't renewed.")
        }
      }

      homebrewSection

      if device.isRoot {
        Section("Screenshot") {
          ForEach(ScreenshotMethod.allCases) { method in
            Button(method.title, systemImage: "camera.viewfinder") { takeScreenshot(method) }
          }
        }
      }
    }
    .refreshable { await load() }
  }

  @ViewBuilder
  private var devModeRemainingRow: some View {
    if let interval = devMode?.remainingInterval {
      LabeledContent("Time Left") {
        Text(Date.now.addingTimeInterval(interval), style: .timer)
          .monospacedDigit()
      }
    } else if let remaining = devMode?.remaining {
      DetailRow(title: "Time Left", value: remaining)
    } else {
      DetailRow(title: "Time Left", value: devMode == nil ? "Checking…" : "Unavailable")
    }
  }

  @ViewBuilder
  private var homebrewSection: some View {
    Section("Homebrew Channel") {
      if let homebrewApp {
        DetailRow(title: "Version", value: homebrewApp.version)
        if let root = homebrewConfig?.root {
          DetailRow(title: "Root", value: root ? "Active" : "Inactive")
          NavigationLink {
            HomebrewSettingsView(device: device, service: service)
          } label: {
            Label("Root Settings", systemImage: "slider.horizontal.3")
          }
        }
        if let manifest = homebrewRelease?.manifest, manifest.hasUpdate(over: homebrewApp.version) {
          Button("Update to \(manifest.version)", systemImage: "arrow.down.circle") {
            installHomebrew(manifest)
          }
        }
      } else {
        DetailRow(title: "Status", value: "Not Installed")
        if let manifest = homebrewRelease?.manifest {
          Button("Install Homebrew Channel", systemImage: "square.and.arrow.down") {
            installHomebrew(manifest)
          }
        }
      }
    }
  }

  private func load() async {
    let service = service
    do {
      details = .loaded(try await service.details())
    } catch is CancellationError {
      return
    } catch {
      details = .failed(DeviceError.message(for: error))
      return
    }
    async let storageResult = try? service.storage()
    async let devModeResult = loadDevMode()
    async let homebrewResult = loadHomebrew()
    storage = await storageResult
    devMode = await devModeResult
    await homebrewResult
  }

  private func loadDevMode() async -> DevModeStatus? {
    guard device.isDevMode else { return nil }
    guard let token = try? await service.devModeToken() else {
      return DevModeStatus()
    }
    let remaining = try? await DeviceSetupClient().devModeRemaining(token: token)
    return DevModeStatus(token: token, remaining: remaining)
  }

  private func loadHomebrew() async {
    homebrewApp = (try? await service.installedApps())?
      .first { $0.id == InstalledApp.homebrewChannelID }
    homebrewConfig = try? await service.homebrewConfiguration()
    homebrewRelease = try? await RepositoryClient().latest(appID: InstalledApp.homebrewChannelID)
  }

  private func renew() {
    let service = service
    let token = devMode?.token
    operations.run("Renewing Developer Mode") { _ in
      do {
        try await service.extendDevMode()
      } catch {
        guard let token else { throw error }
        try await DeviceSetupClient().renewDevMode(token: token)
      }
      devMode = await loadDevMode()
    }
  }

  private func takeScreenshot(_ method: ScreenshotMethod) {
    let service = service
    operations.run("Taking Screenshot") { _ in
      let data = try await service.screenshot(method: method)
      screenshot = try ScreenshotImage(data: data)
    }
  }

  private func installHomebrew(_ manifest: PackageManifest) {
    let service = service
    operations.run("Installing Homebrew Channel") { progress in
      try await service.install(manifest: manifest, progress: progress)
      await loadHomebrew()
    }
  }
}

struct ScreenshotImage: Identifiable {
  var id = UUID()
  var image: UIImage

  init(data: Data) throws {
    guard let image = UIImage(data: data) else { throw DeviceError.invalidResponse }
    self.image = image
  }
}

private struct ScreenshotView: View {
  var screenshot: ScreenshotImage
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Image(uiImage: screenshot.image)
        .resizable()
        .scaledToFit()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("TV screenshot")
        .navigationTitle("Screenshot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done", role: .confirm) { dismiss() }
          }
          ToolbarItem(placement: .primaryAction) {
            let image = Image(uiImage: screenshot.image)
            ShareLink(item: image, preview: SharePreview("TV Screenshot", image: image))
          }
        }
    }
  }
}

struct RenewalScriptFile: Identifiable {
  var id = UUID()
  var deviceName: String
  var token: String

  var contents: String { RenewalScript.make(deviceName: deviceName, token: token) }

  func writeToTemporaryFile() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(RenewalScript.fileName(deviceName: deviceName))
    try Data(contents.utf8).write(to: url, options: [.atomic, .completeFileProtection])
    return url
  }
}

private struct RenewalScriptView: View {
  var script: RenewalScriptFile
  @Environment(\.dismiss) private var dismiss
  @State private var fileURL: URL?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Label(
            "The script contains the session token, so keep it somewhere private.",
            systemImage: "exclamationmark.shield")
          Text("Run it once a day with cron on a computer that's always on. iOS doesn't guarantee scheduled background execution.")
            .foregroundStyle(.secondary)
          Text(script.contents)
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: .rect(cornerRadius: 12))
        }
        .padding()
      }
      .navigationTitle("Auto-Renewal")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", role: .confirm) { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
          if let fileURL {
            ShareLink(item: fileURL)
          }
        }
      }
      .onAppear { fileURL = try? script.writeToTemporaryFile() }
      .onDisappear { if let fileURL { try? FileManager.default.removeItem(at: fileURL) } }
    }
  }
}
