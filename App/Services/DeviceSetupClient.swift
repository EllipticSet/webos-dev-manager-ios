import Foundation
import Network

struct ConnectionCheck: Hashable, Sendable {
  var keyServer: Bool
  var ssh22: Bool
  var ssh9922: Bool
}

/// Talks to the TV before a device is saved, and to LG's Developer Mode session service.
struct DeviceSetupClient: Sendable {
  static let keyServerPort: UInt16 = 9991

  /// Downloads the key the Developer Mode app offers while its Key Server is on.
  func fetchDevModeKey(host: String, passphrase: String) async throws -> String {
    var components = URLComponents()
    components.scheme = "http"
    components.host = host
    components.port = Int(Self.keyServerPort)
    components.path = "/webos_rsa"
    guard let url = components.url else { throw DeviceError.keyServerUnavailable }
    var request = URLRequest(url: url)
    request.timeoutInterval = 10
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw DeviceError.keyServerUnavailable
    }
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw DeviceError.keyServerUnavailable
    }
    let key = String(decoding: data, as: UTF8.self)
    try SSHKeyLoader.validate(key: key, passphrase: passphrase)
    return key
  }

  func checkConnection(host: String) async -> ConnectionCheck {
    async let keyServer = isReachable(host: host, port: Self.keyServerPort)
    async let ssh22 = isReachable(host: host, port: 22)
    async let ssh9922 = isReachable(host: host, port: 9922)
    return await ConnectionCheck(keyServer: keyServer, ssh22: ssh22, ssh9922: ssh9922)
  }

  func isReachable(host: String, port: UInt16) async -> Bool {
    guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return false }
    let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
    let result = OnceBox()
    return await withCheckedContinuation { continuation in
      connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
          if result.claim() { continuation.resume(returning: true) }
          connection.cancel()
        case .failed, .cancelled, .waiting:
          if result.claim() { continuation.resume(returning: false) }
          connection.cancel()
        default:
          break
        }
      }
      connection.start(queue: .global())
      DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
        if result.claim() { continuation.resume(returning: false) }
        connection.cancel()
      }
    }
  }

  // MARK: Developer Mode session

  func devModeRemaining(token: String) async throws -> String? {
    let session: DevModeSessionResponse = try await devModeRequest(
      "CheckDevModeSession.dev", token: token)
    return session.result == "success" ? session.errorMsg : nil
  }

  /// Renews through LG's server, which works while the TV is off once the token is known.
  func renewDevMode(token: String) async throws {
    let session: DevModeSessionResponse = try await devModeRequest(
      "ResetDevModeSession.dev", token: token)
    guard session.result == "success" else {
      throw DeviceError.repository(session.errorMsg ?? "Renewal failed.")
    }
  }

  private func devModeRequest<Value: Decodable>(_ path: String, token: String) async throws -> Value {
    var components = URLComponents(string: "https://developer.lge.com/secure/\(path)")
    components?.queryItems = [URLQueryItem(name: "sessionToken", value: token)]
    guard let url = components?.url else { throw DeviceError.invalidResponse }
    let (data, response) = try await URLSession.shared.data(from: url)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw DeviceError.invalidResponse
    }
    return try JSONDecoder().decode(Value.self, from: data)
  }
}

private struct DevModeSessionResponse: Decodable {
  var result: String
  var errorCode: String?
  var errorMsg: String?
}

private final class OnceBox: @unchecked Sendable {
  private let lock = NSLock()
  private var claimed = false

  func claim() -> Bool {
    lock.withLock {
      defer { claimed = true }
      return !claimed
    }
  }
}
