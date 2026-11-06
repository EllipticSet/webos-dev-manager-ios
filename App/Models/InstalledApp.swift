import Foundation

struct InstalledApp: Identifiable, Decodable, Hashable, Sendable {
  var id: String
  var type: String?
  var title: String
  var appDescription: String?
  var vendor: String?
  var version: String
  var folderPath: String?
  var icon: String?

  var iconPath: String? {
    guard let folderPath, let icon else { return nil }
    return folderPath.appendingPathSegment(icon)
  }

  static let homebrewChannelID = "org.webosbrew.hbchannel"
}
