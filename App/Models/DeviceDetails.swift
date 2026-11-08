import Foundation

struct DeviceDetails: Hashable, Sendable {
  var modelName: String?
  var osVersion: String?
  var otaID: String?
  var firmwareVersion: String?
  var socName: String?
}

struct StorageInfo: Hashable, Sendable {
  var totalKilobytes: Int64
  var usedKilobytes: Int64
  var availableKilobytes: Int64

  var usedFraction: Double {
    totalKilobytes > 0 ? Double(usedKilobytes) / Double(totalKilobytes) : 0
  }

  /// Reads the second line of `df` output.
  static func parse(df output: String) -> StorageInfo? {
    let lines = output.split(whereSeparator: \.isNewline)
    guard lines.count >= 2 else { return nil }
    let fields = lines[1].split(whereSeparator: \.isWhitespace)
    guard fields.count >= 4, let total = Int64(fields[1]), let used = Int64(fields[2]),
      let available = Int64(fields[3])
    else { return nil }
    return StorageInfo(totalKilobytes: total, usedKilobytes: used, availableKilobytes: available)
  }
}

struct DevModeStatus: Hashable, Sendable {
  var token: String?
  /// Time left as the LG server reports it, `HH:MM:SS` when it can be parsed.
  var remaining: String?

  var remainingInterval: TimeInterval? {
    guard let remaining else { return nil }
    let parts = remaining.split(separator: ":").compactMap { TimeInterval($0) }
    guard parts.count == 3 else { return nil }
    return parts[0] * 3600 + parts[1] * 60 + parts[2]
  }
}

struct HomebrewConfiguration: Hashable, Sendable {
  var root: Bool?
  var telnetDisabled: Bool?
  var failsafe: Bool?
  var sshdEnabled: Bool?
  var blockUpdates: Bool?
}

enum ScreenshotMethod: String, CaseIterable, Identifiable {
  case display = "DISPLAY"
  case video = "VIDEO"
  case graphic = "GRAPHIC"

  var id: Self { self }

  var title: String {
    switch self {
    case .display: String(localized: "Full Screen")
    case .video: String(localized: "Video Only")
    case .graphic: String(localized: "Graphics Only")
    }
  }
}
