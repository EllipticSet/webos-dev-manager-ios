import Foundation

/// A repository the Homebrew catalog lists apps from, published like repo.webosbrew.org.
struct RepositorySource: Identifiable, Hashable, Sendable {
  enum Kind: Hashable, Sendable {
    case official
    case nonFree
    case custom
  }

  var kind: Kind
  /// The repository's `apps.json`, its first page of apps.
  var url: URL

  var id: URL { url }

  static let official = RepositorySource(
    kind: .official, url: URL(string: "https://repo.webosbrew.org/api/apps.json")!)
  static let nonFree = RepositorySource(
    kind: .nonFree, url: URL(string: "https://repo.webosbrew.org/api/non-free/apps.json")!)

  var title: String {
    switch kind {
    case .official: "webOS Homebrew"
    case .nonFree: String(localized: "Non-Free Software")
    case .custom: url.host() ?? url.absoluteString
    }
  }

  /// Reads an address the user typed. Like Homebrew Channel, a repository is the URL of its
  /// `apps.json`, which is assumed when the address names a folder.
  static func customURL(from text: String) -> URL? {
    var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.contains("://") { text = "https://" + text }
    guard var components = URLComponents(string: text),
      let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
      components.host?.isEmpty == false
    else { return nil }
    if !components.path.lowercased().hasSuffix(".json") {
      if !components.path.hasSuffix("/") { components.path += "/" }
      components.path += "apps.json"
    }
    return components.url
  }
}
