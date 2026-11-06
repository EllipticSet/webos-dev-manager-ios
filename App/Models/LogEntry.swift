import Foundation

struct LogEntry: Identifiable, Hashable, Sendable {
  var id = UUID()
  var date: Date?
  var monotonic: Double?
  var level: LogLevel
  var process: String?
  var context: String?
  var message: String

  private static let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  static func parsePmLog(_ line: String) -> LogEntry? {
    let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !line.isEmpty else { return nil }
    let pattern =
      /^(?<datetime>[\w:.\-+]+) \[(?<monotonic>\d+\.\d+)\] (?<facility>\S+)\.(?<level>\S+) (?<process>\S+) \[(?:\S+:\S+)?\] (?<context>\S+) (?<msgid>\S+) (?<remaining>\{.+)$/
    guard let match = line.wholeMatch(of: pattern) else {
      return LogEntry(date: Date(), level: .info, message: line)
    }
    let remaining = String(match.output.remaining)
    let message = remaining.endOfJSONObject.map { String(remaining[$0...]) } ?? remaining
    return LogEntry(
      date: isoFormatter.date(from: String(match.output.datetime)),
      monotonic: Double(match.output.monotonic),
      level: LogLevel(rawValue: String(match.output.level)) ?? .info,
      process: String(match.output.process),
      context: String(match.output.context),
      message: message.trimmingCharacters(in: .whitespaces)
    )
  }

  static func parseDmesg(_ line: String) -> LogEntry? {
    let pattern =
      /^(?<facility>\S+)\s*:(?<level>\S+)\s*:\s*\[\s*(?<monotonic>\d+\.\d+)\]\s+(?:(?<context>.+?): )?(?<remaining>.+)$/
    guard let match = line.wholeMatch(of: pattern) else { return nil }
    return LogEntry(
      monotonic: Double(match.output.monotonic),
      level: LogLevel(dmesgName: String(match.output.level)),
      context: match.output.context.map(String.init),
      message: String(match.output.remaining)
    )
  }
}

enum LogLevel: String, CaseIterable, Identifiable, Sendable {
  case emerg, alert, crit, err, warning, notice, info, debug

  var id: Self { self }

  init(dmesgName: String) {
    self = LogLevel(rawValue: dmesgName) ?? (dmesgName == "warn" ? .warning : .info)
  }

  var isProblem: Bool {
    switch self {
    case .emerg, .alert, .crit, .err: true
    default: false
    }
  }
}

extension String {
  /// The index just after the JSON object this string starts with.
  fileprivate var endOfJSONObject: String.Index? {
    var depth = 0
    var inString = false
    var escaped = false
    for index in indices {
      let character = self[index]
      if escaped {
        escaped = false
      } else if inString {
        if character == "\\" { escaped = true } else if character == "\"" { inString = false }
      } else if character == "\"" {
        inString = true
      } else if character == "{" {
        depth += 1
      } else if character == "}" {
        depth -= 1
        if depth == 0 { return self.index(after: index) }
      }
    }
    return nil
  }
}
