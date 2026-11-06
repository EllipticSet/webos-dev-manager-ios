import Citadel
import Foundation
import NIOCore
import NIOSSH

struct CommandOutput: Sendable {
  var stdout: Data
  var stderr: Data
  var status: Int

  var text: String { String(decoding: stdout, as: UTF8.self) }
  var errorText: String {
    String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// One device's SSH connection. Short commands share a connection; long-running ones each get their own,
/// because closing the connection is the way to stop a remote process that never exits.
actor DeviceSession {
  let device: Device
  private let secrets: DeviceSecrets
  private let hostKeyTrial: HostKeyTrial?
  private var client: SSHClient?
  private var connecting: Task<SSHClient, Error>?
  private var sftp: SFTPClient?
  private var sftpUnavailable = false

  /// How long a command may stay silent before the connection counts as dead.
  private static let commandSilenceLimit: Double = 60

  init(device: Device, secrets: DeviceSecrets, hostKeyTrial: HostKeyTrial? = nil) {
    self.device = device
    self.secrets = secrets
    self.hostKeyTrial = hostKeyTrial
  }

  // MARK: Connections

  func makeClient() async throws -> SSHClient {
    let method: SSHAuthenticationMethod
    switch device.authentication {
    case .password:
      guard let password = secrets.password else { throw DeviceError.missingCredentials }
      method = .passwordBased(username: device.username, password: password)
    case .devModeKey, .importedKey:
      guard let key = secrets.privateKey else { throw DeviceError.missingCredentials }
      method = try SSHKeyLoader.authentication(
        username: device.username, key: key, passphrase: secrets.passphrase)
    case .certificate:
      guard let id = device.certificateID, let key = KeychainStore.secrets(for: id).privateKey
      else { throw DeviceError.missingCredentials }
      method = try SSHKeyLoader.authentication(
        username: device.username, key: key,
        passphrase: KeychainStore.secrets(for: id).passphrase)
    }
    let device = device
    let trial = hostKeyTrial
    return try await withTimeout(seconds: 20) {
      let client = try await SSHClient.connect(
        host: device.host,
        port: device.port,
        authenticationMethod: method,
        hostKeyValidator: .custom(TrustOnFirstUseValidator(deviceID: device.id, trial: trial)),
        reconnect: .never,
        algorithms: .all,
        connectTimeout: .seconds(10)
      )
      // After a timeout or a cancellation, nobody is left to close this connection.
      if Task.isCancelled {
        try? await client.close()
        throw CancellationError()
      }
      return client
    }
  }

  /// Callers arriving while a connection is being made wait for it, rather than each opening their own.
  private func sharedClient() async throws -> SSHClient {
    if let client, client.isConnected { return client }
    if let connecting { return try await connecting.value }
    sftp = nil
    let task = Task { try await makeClient() }
    connecting = task
    do {
      let client = try await task.value
      guard connecting == task else {
        try? await client.close()
        throw CancellationError()
      }
      connecting = nil
      self.client = client
      return client
    } catch {
      if connecting == task { connecting = nil }
      throw error
    }
  }

  /// Forgets a connection that stopped responding, so that the next command opens a new one.
  private func drop(_ stalled: SSHClient) {
    if client === stalled {
      client = nil
      sftp = nil
    }
    Task { try? await stalled.close() }
  }

  func disconnect() async {
    connecting?.cancel()
    connecting = nil
    try? await client?.close()
    client = nil
    sftp = nil
    sftpUnavailable = false
  }

  // MARK: Commands

  /// Runs a command and collects its output, without treating a non-zero status as an error.
  func execute(_ command: String, silenceLimit: Double = commandSilenceLimit) async throws
    -> CommandOutput
  {
    let client = try await sharedClient()
    do {
      return try await withInactivityTimeout(seconds: silenceLimit) { touch in
        var stdout = Data()
        var stderr = Data()
        var status = 0
        do {
          for try await chunk in try await client.executeCommandStream(command) {
            touch()
            switch chunk {
            case .stdout(let buffer): stdout.append(buffer.data)
            case .stderr(let buffer): stderr.append(buffer.data)
            }
          }
        } catch let failure as SSHClient.CommandFailed {
          status = failure.exitCode
        }
        // A cancelled stream just ends, which would look like a complete output.
        try Task.checkCancellation()
        return CommandOutput(stdout: stdout, stderr: stderr, status: status)
      }
    } catch DeviceError.timedOut, CitadelError.channelCreationFailed {
      // Citadel gives up by itself when a connection that looks open no longer answers.
      drop(client)
      throw DeviceError.timedOut
    }
  }

  /// Runs a command and throws when it exits with a non-zero status.
  @discardableResult
  func run(_ command: String, silenceLimit: Double = commandSilenceLimit) async throws
    -> CommandOutput
  {
    let output = try await execute(command, silenceLimit: silenceLimit)
    guard output.status == 0 else {
      throw DeviceError.commandFailed(
        command: command, status: output.status, message: output.errorText)
    }
    return output
  }

  /// Streams the lines of a long-running command on its own connection.
  /// Ending the stream closes the connection, which stops the command.
  nonisolated func lines(of command: String) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        var connection: SSHClient?
        do {
          let client = try await makeClient()
          connection = client
          var splitter = LineSplitter()
          var errorOutput = Data()
          do {
            for try await chunk in try await client.executeCommandStream(command) {
              switch chunk {
              case .stdout(let buffer):
                for line in splitter.append(buffer.data) { continuation.yield(line) }
              case .stderr(let buffer):
                errorOutput.append(buffer.data)
              }
            }
          } catch let failure as SSHClient.CommandFailed {
            throw DeviceError.commandFailed(
              command: command, status: failure.exitCode,
              message: String(decoding: errorOutput, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines))
          }
          if let last = splitter.finish() { continuation.yield(last) }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
        try? await connection?.close()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  // MARK: Files

  func homeDirectory() async throws -> String {
    let home = try await run("pwd").text.trimmingCharacters(in: .whitespacesAndNewlines)
    return home.isEmpty ? "/" : home
  }

  func list(_ path: String) async throws -> [RemoteFile] {
    if let sftp = try await sftpClient() {
      // SFTP servers can leave a request unanswered, so don't let it block the screen. The shell
      // below then gives the real reason, such as a missing folder or denied permission.
      if let names = try? await withTimeout(seconds: 10, operation: { @Sendable in
        try await sftp.listDirectory(atPath: path).flatMap(\.components)
      }) {
        var files: [RemoteFile] = []
        for component in names where ![".", ".."].contains(component.filename) {
          files.append(await file(from: component, in: path, sftp: sftp))
        }
        return RemoteFile.sorted(files)
      }
    }
    let listing = try await run("ls -la \(path.shellQuoted)").text
    return RemoteFile.sorted(RemoteFile.parseListing(listing, directory: path))
  }

  private func file(from component: SFTPPathComponent, in directory: String, sftp: SFTPClient) async
    -> RemoteFile
  {
    let path = directory.appendingPathSegment(component.filename)
    let attributes = component.attributes
    let permissions = attributes.permissions ?? 0
    let isLink = permissions & 0o170000 == 0o120000
    var effective = permissions
    if isLink,
      let resolved = try? await withTimeout(seconds: 5, operation: { @Sendable in
        try await sftp.getAttributes(at: path).permissions
      })
    {
      effective = resolved
    }
    let kind: RemoteFile.Kind
    switch effective & 0o170000 {
    case 0o040000: kind = .directory
    case 0o100000, 0o120000: kind = .file
    default: kind = .other
    }
    return RemoteFile(
      name: component.filename,
      path: path,
      kind: kind,
      isLink: isLink,
      size: attributes.size ?? 0,
      modified: attributes.accessModificationTime?.modificationTime,
      mode: RemoteFile.modeString(permissions: permissions)
    )
  }

  /// Uses `cat` so reads also work on firmware without SFTP. Runs on its own connection, because
  /// closing it is what stops a transfer that was cancelled.
  func download(_ path: String, to destination: URL, progress: (@Sendable (Int64) -> Void)? = nil)
    async throws
  {
    FileManager.default.createFile(atPath: destination.path, contents: nil)
    let handle = try FileHandle(forWritingTo: destination)
    defer { try? handle.close() }
    let client = try await makeClient()
    defer { Task { try? await client.close() } }
    try await withInactivityTimeout(seconds: Self.commandSilenceLimit) { touch in
      var written: Int64 = 0
      var errorText = Data()
      do {
        for try await chunk in try await client.executeCommandStream("cat \(path.shellQuoted)") {
          touch()
          switch chunk {
          case .stdout(let buffer):
            let data = buffer.data
            try handle.write(contentsOf: data)
            written += Int64(data.count)
            progress?(written)
          case .stderr(let buffer):
            errorText.append(buffer.data)
          }
        }
      } catch let failure as SSHClient.CommandFailed {
        throw DeviceError.commandFailed(
          command: "cat", status: failure.exitCode,
          message: String(decoding: errorText, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines))
      }
      // A cancelled stream just ends, which would look like a complete file.
      try Task.checkCancellation()
    }
  }

  func read(_ path: String) async throws -> Data {
    try await run("cat \(path.shellQuoted)").stdout
  }

  /// Reads a gzip-compressed file, decompressing it on the device.
  func readGzip(_ path: String) async throws -> Data {
    let quoted = path.shellQuoted
    let output = try await execute("gzip -dc \(quoted) 2>/dev/null || cat \(quoted)")
    guard output.status == 0 else { throw DeviceError.invalidResponse }
    return output.stdout
  }

  func upload(_ source: URL, to path: String, progress: (@Sendable (Double) -> Void)? = nil)
    async throws
  {
    let handle = try FileHandle(forReadingFrom: source)
    defer { try? handle.close() }
    let total = max(1, try handle.seekToEnd())
    try handle.seek(toOffset: 0)
    if let sftp = try await sftpClient() {
      let client = try await sharedClient()
      let limit = Self.commandSilenceLimit
      do {
        let file = try await withTimeout(seconds: limit) {
          try await sftp.openFile(filePath: path, flags: [.write, .create, .truncate])
        }
        do {
          var offset: UInt64 = 0
          while let data = try handle.read(upToCount: 32 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            let position = offset
            try await withTimeout(seconds: limit) {
              try await file.write(ByteBuffer(bytes: data), at: position)
            }
            offset += UInt64(data.count)
            progress?(Double(offset) / Double(total))
          }
          try await withTimeout(seconds: limit) { try await file.close() }
        } catch {
          // Separate from this task, which may be the one that was cancelled.
          Task { _ = try? await withTimeout(seconds: 5) { try await file.close() } }
          throw error
        }
      } catch DeviceError.timedOut {
        drop(client)
        throw DeviceError.timedOut
      }
      return
    }
    // Without SFTP, append base64 chunks: Citadel has no stdin for exec channels.
    try await run(": > \(path.shellQuoted)")
    var offset: UInt64 = 0
    while let data = try handle.read(upToCount: 48 * 1024), !data.isEmpty {
      try Task.checkCancellation()
      try await run("echo \(data.base64EncodedString()) | base64 -d >> \(path.shellQuoted)")
      offset += UInt64(data.count)
      progress?(Double(offset) / Double(total))
    }
  }

  /// Uploads next to the destination and then renames, so a failure leaves any existing file intact.
  func uploadReplacing(
    _ source: URL, to path: String, progress: (@Sendable (Double) -> Void)? = nil
  ) async throws {
    let directory = (path as NSString).deletingLastPathComponent
    let partial = directory.appendingPathSegment(".devman-\(UUID().uuidString).part")
    do {
      try await upload(source, to: partial, progress: progress)
      // Keeps the permissions of a file being replaced; there's nothing to keep for a new one.
      try await run(
        "chmod \"$(stat -c %a \(path.shellQuoted) 2>/dev/null)\" \(partial.shellQuoted) 2>/dev/null; "
          + "mv -f \(partial.shellQuoted) \(path.shellQuoted)")
    } catch {
      Task { try? await remove(partial, recursive: false) }
      throw error
    }
  }

  func makeDirectory(_ path: String) async throws {
    try await run("mkdir -p \(path.shellQuoted)")
  }

  func remove(_ path: String, recursive: Bool) async throws {
    // Deleting a large folder can legitimately print nothing for a long time.
    try await run("rm \(recursive ? "-rf" : "-f") \(path.shellQuoted)", silenceLimit: 10 * 60)
  }

  private func sftpClient() async throws -> SFTPClient? {
    if sftpUnavailable { return nil }
    let client = try await sharedClient()
    if let sftp, sftp.isActive { return sftp }
    do {
      let opened = try await withTimeout(seconds: 10) { try await client.openSFTP() }
      sftp = opened
      return opened
    } catch {
      sftpUnavailable = true
      return nil
    }
  }
}

/// Remembers each TV's host key the first time it connects and refuses a different one afterwards.
final class TrustOnFirstUseValidator: NIOSSHClientServerAuthenticationDelegate {
  private let deviceID: UUID
  private let trial: HostKeyTrial?

  init(deviceID: UUID, trial: HostKeyTrial? = nil) {
    self.deviceID = deviceID
    self.trial = trial
  }

  func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
    let presented = String(openSSHPublicKey: hostKey)
    if let trial {
      trial.record(presented)
      validationCompletePromise.succeed(())
    } else if let known = Self.knownKey(for: deviceID) {
      if known == presented {
        validationCompletePromise.succeed(())
      } else {
        validationCompletePromise.fail(DeviceError.hostKeyChanged)
      }
    } else {
      UserDefaults.standard.set(presented, forKey: Self.defaultsKey(for: deviceID))
      validationCompletePromise.succeed(())
    }
  }

  static func knownKey(for id: UUID) -> String? {
    UserDefaults.standard.string(forKey: defaultsKey(for: id))
  }

  static func remember(_ key: String, for id: UUID) {
    UserDefaults.standard.set(key, forKey: defaultsKey(for: id))
  }

  static func forget(for id: UUID) {
    UserDefaults.standard.removeObject(forKey: defaultsKey(for: id))
  }

  private static func defaultsKey(for id: UUID) -> String { "hostKey.\(id.uuidString)" }
}

/// Holds the host key of a new address while its sign-in is being tested. The saved key only changes
/// on `commit`, so a test that fails leaves the TV as it was.
final class HostKeyTrial: @unchecked Sendable {
  private let lock = NSLock()
  private var presented: String?

  func record(_ key: String) {
    lock.withLock { presented = key }
  }

  func commit(for id: UUID) {
    if let key = lock.withLock({ presented }) {
      TrustOnFirstUseValidator.remember(key, for: id)
    }
  }
}

struct LineSplitter {
  private var pending = Data()

  mutating func append(_ data: Data) -> [String] {
    pending.append(data)
    var lines: [String] = []
    while let newline = pending.firstIndex(of: 0x0A) {
      lines.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
      pending = Data(pending[pending.index(after: newline)...])
    }
    return lines
  }

  mutating func finish() -> String? {
    defer { pending = Data() }
    return pending.isEmpty ? nil : String(decoding: pending, as: UTF8.self)
  }
}

extension ByteBuffer {
  var data: Data {
    Data(getBytes(at: readerIndex, length: readableBytes) ?? [])
  }
}

/// Races an operation against a deadline.
func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T)
  async throws -> T
{
  try await withInactivityTimeout(seconds: seconds) { _ in try await operation() }
}

/// Races an operation against a deadline that it pushes back by calling `touch`. A task group wouldn't
/// do: it waits for its children, and NIO futures ignore cancellation, so a stalled operation would
/// never give up. Cancelling the caller also gives up at once, for the same reason.
func withInactivityTimeout<T: Sendable>(
  seconds: Double,
  operation: @escaping @Sendable (_ touch: @escaping @Sendable () -> Void) async throws -> T
) async throws -> T {
  let race = TimeoutRace<T>()
  let clock = ActivityClock()
  let work = Task {
    do {
      race.finish(.success(try await operation { clock.touch() }))
    } catch {
      race.finish(.failure(error))
    }
  }
  let watchdog = Task {
    while case let remaining = seconds - clock.secondsSinceLastTouch, remaining > 0 {
      try await Task.sleep(for: .seconds(remaining))
    }
    race.finish(.failure(DeviceError.timedOut))
    work.cancel()
  }
  defer { watchdog.cancel() }
  return try await withTaskCancellationHandler {
    try await withCheckedThrowingContinuation { race.install($0) }
  } onCancel: {
    race.finish(.failure(CancellationError()))
    work.cancel()
  }
}

/// Hands the first result to the caller, whichever arrives first: the result or the continuation.
private final class TimeoutRace<T: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var result: Result<T, Error>?
  private var continuation: CheckedContinuation<T, Error>?

  func install(_ continuation: CheckedContinuation<T, Error>) {
    let ready: Result<T, Error>? = lock.withLock {
      if result == nil { self.continuation = continuation }
      return result
    }
    if let ready { continuation.resume(with: ready) }
  }

  func finish(_ outcome: Result<T, Error>) {
    let waiting: CheckedContinuation<T, Error>? = lock.withLock {
      guard result == nil else { return nil }
      result = outcome
      defer { continuation = nil }
      return continuation
    }
    waiting?.resume(with: outcome)
  }
}

final class ActivityClock: @unchecked Sendable {
  private let lock = NSLock()
  private var last = Date()

  func touch() {
    lock.withLock { last = Date() }
  }

  var secondsSinceLastTouch: TimeInterval {
    lock.withLock { Date().timeIntervalSince(last) }
  }
}
