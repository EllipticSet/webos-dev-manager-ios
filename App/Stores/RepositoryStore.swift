import Observation
import SwiftUI

/// The repositories the Homebrew catalog uses, saved on this iPhone. Homebrew Channel keeps its own
/// list inside its app on the TV, where other apps can't read or change it.
@MainActor
@Observable
final class RepositoryStore {
  var isOfficialEnabled: Bool {
    didSet { UserDefaults.standard.set(isOfficialEnabled, forKey: Self.officialKey) }
  }
  var isNonFreeEnabled: Bool {
    didSet { UserDefaults.standard.set(isNonFreeEnabled, forKey: Self.nonFreeKey) }
  }
  private(set) var customSources: [RepositorySource] {
    didSet {
      UserDefaults.standard.set(customSources.map(\.url.absoluteString), forKey: Self.customKey)
    }
  }

  private static let officialKey = "repositories.officialEnabled"
  private static let nonFreeKey = "repositories.nonFreeEnabled"
  private static let customKey = "repositories.custom"

  init() {
    let defaults = UserDefaults.standard
    isOfficialEnabled = defaults.object(forKey: Self.officialKey) as? Bool ?? true
    isNonFreeEnabled = defaults.bool(forKey: Self.nonFreeKey)
    customSources = (defaults.stringArray(forKey: Self.customKey) ?? [])
      .compactMap(URL.init(string:))
      .map { RepositorySource(kind: .custom, url: $0) }
  }

  /// In the order the catalog lists them, which also decides whose entry wins for an app that's in
  /// more than one.
  var enabledSources: [RepositorySource] {
    (isOfficialEnabled ? [.official] : []) + (isNonFreeEnabled ? [.nonFree] : []) + customSources
  }

  func contains(_ url: URL) -> Bool {
    url == RepositorySource.official.url || url == RepositorySource.nonFree.url
      || customSources.contains { $0.url == url }
  }

  func add(_ url: URL) {
    guard !contains(url) else { return }
    customSources.append(RepositorySource(kind: .custom, url: url))
  }

  func remove(_ source: RepositorySource) {
    customSources.removeAll { $0 == source }
  }

  func remove(atOffsets offsets: IndexSet) {
    customSources.remove(atOffsets: offsets)
  }
}
