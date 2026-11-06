import Foundation

struct RemoteFile: Identifiable, Hashable, Sendable {
  enum Kind: Sendable {
    case file
    case directory
    case other
  }

  var name: String
  var path: String
  var kind: Kind
  var isLink: Bool = false
  var linkTarget: String?
  var size: UInt64 = 0
  var modified: Date?
  var mode: String = ""
  var owner: String?

  var id: String { path }
  var isDirectory: Bool { kind == .directory }

  var systemImage: String {
    switch kind {
    case .directory: isLink ? "folder.badge.gearshape" : "folder.fill"
    case .file: isLink ? "link" : "doc"
    case .other: "questionmark.square.dashed"
    }
  }

  /// Builds a mode string such as `drwxr-xr-x` from a POSIX `st_mode`.
  static func modeString(permissions: UInt32) -> String {
    let type: Character
    switch permissions & 0o170000 {
    case 0o040000: type = "d"
    case 0o120000: type = "l"
    case 0o100000: type = "-"
    case 0o020000: type = "c"
    case 0o060000: type = "b"
    case 0o010000: type = "p"
    case 0o140000: type = "s"
    default: type = "?"
    }
    var result = String(type)
    for shift in stride(from: 6, through: 0, by: -3) {
      let bits = (permissions >> UInt32(shift)) & 0o7
      result += bits & 4 != 0 ? "r" : "-"
      result += bits & 2 != 0 ? "w" : "-"
      result += bits & 1 != 0 ? "x" : "-"
    }
    return result
  }

  /// Parses `ls -la` output, for SSH servers that have no SFTP subsystem.
  static func parseListing(_ output: String, directory: String) -> [RemoteFile] {
    output.split(whereSeparator: \.isNewline).compactMap { line in
      let fields = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
      guard fields.count == 9, let size = UInt64(fields[4]) else { return nil }
      let mode = String(fields[0])
      var name = String(fields[8])
      var target: String?
      if mode.hasPrefix("l"), let arrow = name.range(of: " -> ") {
        target = String(name[arrow.upperBound...])
        name = String(name[..<arrow.lowerBound])
      }
      guard name != ".", name != ".." else { return nil }
      let kind: Kind
      switch mode.first {
      case "d": kind = .directory
      case "-", "l": kind = .file
      default: kind = .other
      }
      return RemoteFile(
        name: name,
        path: directory.appendingPathSegment(name),
        kind: kind,
        isLink: mode.hasPrefix("l"),
        linkTarget: target,
        size: size,
        mode: mode,
        owner: String(fields[2])
      )
    }
  }

  static func sorted(_ files: [RemoteFile]) -> [RemoteFile] {
    files.sorted { lhs, rhs in
      if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
      return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
  }
}

extension String {
  func appendingPathSegment(_ segment: String) -> String {
    hasSuffix("/") ? self + segment : self + "/" + segment
  }

  /// Quotes the string as one POSIX shell word.
  var shellQuoted: String {
    "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}
