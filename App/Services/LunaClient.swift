import Foundation

typealias LunaResponse = [String: Any]

/// Calls webOS Luna services by running `luna-send` over SSH.
struct LunaClient: Sendable {
  var session: DeviceSession

  @discardableResult
  func call(
    _ uri: String, parameters: [String: Any] = [:], isPublic: Bool = true,
    falseAsError: Bool = true
  ) async throws -> LunaResponse {
    let command = try "\(sender(isPublic)) -n 1 \(uri) \(encode(parameters).shellQuoted)"
    let output = try await session.execute(command)
    if output.status == 127 { throw DeviceError.notWebOS }
    guard
      let response = try? JSONSerialization.jsonObject(with: output.stdout) as? LunaResponse
    else {
      if output.status != 0 {
        throw DeviceError.commandFailed(
          command: command, status: output.status, message: output.errorText)
      }
      throw DeviceError.invalidResponse
    }
    if let error = Self.error(in: response, falseAsError: falseAsError) { throw error }
    return response
  }

  func subscribe(_ uri: String, parameters: [String: Any], isPublic: Bool = true) throws
    -> AsyncThrowingStream<LunaResponse, Error>
  {
    let command = try "\(sender(isPublic)) -i \(uri) \(encode(parameters).shellQuoted)"
    let lines = session.lines(of: command)
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await line in lines {
            guard let data = line.data(using: .utf8),
              let response = try? JSONSerialization.jsonObject(with: data) as? LunaResponse
            else { continue }
            continuation.yield(response)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  static func error(in response: LunaResponse, falseAsError: Bool) -> DeviceError? {
    guard response["returnValue"] as? Bool == false else { return nil }
    let text = response["errorText"] as? String ?? "The TV refused the request."
    if text.hasPrefix("Unknown method") { return .lunaUnknownMethod(text) }
    if text.hasPrefix("Service does not exist") { return .lunaServiceNotFound(text) }
    return falseAsError ? .lunaResponse(text) : nil
  }

  private func sender(_ isPublic: Bool) -> String {
    isPublic ? "luna-send-pub" : "luna-send"
  }

  private func encode(_ parameters: [String: Any]) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: parameters, options: .withoutEscapingSlashes), as: UTF8.self)
  }
}
