import Foundation

struct RepositoryItem: Identifiable, Decodable, Hashable, Sendable {
  var id: String
  var title: String
  var iconUri: String?
  var detailIconUri: String?
  var manifest: PackageManifest?
  var manifestUrl: String?
  var requirements: PackageRequirements?
  var shortDescription: String?
  var fullDescriptionUrl: String?

  func resolved(against base: URL) -> RepositoryItem {
    var item = self
    item.iconUri = iconUri.flatMap { URL(string: $0, relativeTo: base)?.absoluteString }
    item.detailIconUri = detailIconUri.flatMap { URL(string: $0, relativeTo: base)?.absoluteString }
    item.fullDescriptionUrl = fullDescriptionUrl.flatMap {
      URL(string: $0, relativeTo: base)?.absoluteString
    }
    return item
  }

  func incompatibilities(with details: DeviceDetails?, homebrew: HomebrewConfiguration?)
    -> [IncompatibleReason]
  {
    var reasons = requirements?.incompatibilities(with: details) ?? []
    if homebrew?.root == false, manifest?.rootRequired == .required {
      reasons.append(.root)
    }
    return reasons
  }
}

struct PackageManifest: Decodable, Hashable, Sendable {
  struct Hash: Decodable, Hashable, Sendable {
    var sha256: String
  }

  enum RootRequirement: Decodable, Hashable, Sendable {
    case notRequired
    case optional
    case required

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let flag = try? container.decode(Bool.self) {
        self = flag ? .required : .notRequired
      } else {
        self = (try? container.decode(String.self)) == "optional" ? .optional : .notRequired
      }
    }
  }

  var id: String
  var version: String
  var ipkUrl: String
  var ipkHash: Hash?
  var sourceUrl: String?
  var appDescription: String?
  var rootRequired: RootRequirement?

  func hasUpdate(over installed: String?) -> Bool {
    guard let installed, let available = PackageVersion(version),
      let current = PackageVersion(installed)
    else { return false }
    return available > current
  }
}

struct PackageRequirements: Decodable, Hashable, Sendable {
  var webosRelease: String?
  var deviceSoC: [String]?

  func incompatibilities(with details: DeviceDetails?) -> [IncompatibleReason] {
    var reasons: [IncompatibleReason] = []
    if let release = details?.osVersion, let webosRelease,
      let version = PackageVersion(release), !VersionRange(webosRelease).contains(version)
    {
      reasons.append(.release)
    }
    if let soc = details?.socName, let deviceSoC {
      let excluded = deviceSoC.filter { $0.hasPrefix("!") }.map { String($0.dropFirst()) }
      let included = deviceSoC.filter { !$0.hasPrefix("!") }
      if (!included.isEmpty && !included.contains(soc)) || excluded.contains(soc) {
        reasons.append(.soc)
      }
    }
    return reasons
  }
}

enum IncompatibleReason: String, Hashable, Sendable {
  case release
  case soc
  case root

  var message: String {
    switch self {
    case .release: "Not compatible with this TV's webOS version."
    case .soc: "Not compatible with this TV's processor."
    case .root: "Requires a rooted TV."
    }
  }
}

struct RepositoryPage: Decodable, Sendable {
  struct Paging: Decodable, Sendable {
    var page: Int
    var maxPage: Int
    var nextUrl: String?
  }

  /// Missing from repositories that publish all their apps on one page.
  var paging: Paging?
  var packages: [RepositoryItem]

  /// The page after this one, at `url`. Repositories link to it, or else number their pages from
  /// the first, such as `apps/2.json` next to `apps.json`.
  func nextURL(after url: URL, in source: RepositorySource) -> URL? {
    guard let paging, paging.page < paging.maxPage else { return nil }
    if let next = paging.nextUrl {
      return URL(string: next, relativeTo: url)?.absoluteURL
    }
    return source.url.deletingPathExtension().appendingPathComponent("\(paging.page + 1).json")
  }
}
