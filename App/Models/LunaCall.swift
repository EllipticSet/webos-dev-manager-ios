import Foundation

/// A Luna call and the messages answering it, grouped from `ls-monitor -j` output.
struct LunaCall: Identifiable {
  struct Message: Identifiable {
    var id = UUID()
    var type: String
    var payload: String
  }

  var id = UUID()
  var key: String
  var sender: String
  var destination: String
  var method: String
  var messages: [Message]
}

/// Folds the monitor's JSON lines into calls.
struct LunaCallBuilder {
  private(set) var calls: [LunaCall] = []
  private var indexes: [String: Int] = [:]

  private static let maximumCalls = 2000

  mutating func add(line: String) {
    guard let data = line.data(using: .utf8),
      let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      message["transport"] as? String == "TX" || message["transport"] == nil,
      let type = message["type"] as? String
    else { return }
    let payload = Self.payloadText(message)
    let item = LunaCall.Message(type: type, payload: payload)
    if type == "call" {
      let key = Self.key(name: message["senderUniqueName"], token: message["token"])
      let method = [message["methodCategory"] as? String, message["method"] as? String]
        .compactMap { $0?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        .filter { !$0.isEmpty }.joined(separator: "/")
      indexes[key] = calls.count
      calls.append(
        LunaCall(
          key: key,
          sender: message["sender"] as? String ?? "?",
          destination: message["destination"] as? String ?? "?",
          method: method,
          messages: [item]))
      if calls.count > Self.maximumCalls { dropOldestCalls(200) }
    } else {
      let key = Self.key(name: message["destinationUniqueName"], token: message["replyToken"])
      if let index = indexes[key] { calls[index].messages.append(item) }
    }
  }

  private mutating func dropOldestCalls(_ count: Int) {
    calls.removeFirst(count)
    indexes = indexes.compactMapValues { $0 >= count ? $0 - count : nil }
  }

  private static func key(name: Any?, token: Any?) -> String {
    "\(name as? String ?? "?")-\((token as? NSNumber)?.stringValue ?? "?")"
  }

  private static func payloadText(_ message: [String: Any]) -> String {
    if let payload = message["payload"], JSONSerialization.isValidJSONObject(payload),
      let data = try? JSONSerialization.data(
        withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    {
      return String(decoding: data, as: UTF8.self)
    }
    return message["rawPayload"] as? String ?? ""
  }
}
