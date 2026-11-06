import Foundation

/// A package version: semver, plus the four-part `1.2.3.4` form some webOS packages use.
struct PackageVersion: Comparable, Hashable, Sendable {
  var major: Int
  var minor: Int
  var patch: Int
  var revision: Int = 0
  var prerelease: String?

  init(major: Int, minor: Int, patch: Int, revision: Int = 0, prerelease: String? = nil) {
    self.major = major
    self.minor = minor
    self.patch = patch
    self.revision = revision
    self.prerelease = prerelease
  }

  init?(_ text: String) {
    var core = text.trimmingCharacters(in: .whitespaces)
    if core.hasPrefix("v") { core.removeFirst() }
    if let plus = core.firstIndex(of: "+") { core = String(core[..<plus]) }
    if let dash = core.firstIndex(of: "-") {
      prerelease = String(core[core.index(after: dash)...])
      core = String(core[..<dash])
    }
    let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
    guard (1...4).contains(parts.count), !parts.contains(where: { $0 == nil }) else { return nil }
    major = parts[0]!
    minor = parts.count > 1 ? parts[1]! : 0
    patch = parts.count > 2 ? parts[2]! : 0
    revision = parts.count > 3 ? parts[3]! : 0
  }

  static func < (lhs: PackageVersion, rhs: PackageVersion) -> Bool {
    let left = (lhs.major, lhs.minor, lhs.patch, lhs.revision)
    let right = (rhs.major, rhs.minor, rhs.patch, rhs.revision)
    if left != right { return left < right }
    switch (lhs.prerelease, rhs.prerelease) {
    case (nil, nil), (nil, _): return false
    case (_, nil): return true
    case let (left?, right?): return left.compare(right, options: .numeric) == .orderedAscending
    }
  }
}

/// The subset of npm semver ranges the Homebrew repository uses in `webosRelease`.
struct VersionRange: Sendable {
  private enum Comparator: Sendable {
    case atLeast(PackageVersion)
    case above(PackageVersion)
    case atMost(PackageVersion)
    case below(PackageVersion)
    case exactly(PackageVersion)
  }

  private var alternatives: [[Comparator]]

  init(_ text: String) {
    alternatives = text.components(separatedBy: "||").map { alternative in
      alternative.split(whereSeparator: \.isWhitespace).flatMap(Self.comparators)
    }
  }

  func contains(_ version: PackageVersion) -> Bool {
    alternatives.contains { comparators in
      comparators.allSatisfy { comparator in
        switch comparator {
        case .atLeast(let bound): version >= bound
        case .above(let bound): version > bound
        case .atMost(let bound): version <= bound
        case .below(let bound): version < bound
        case .exactly(let bound): version == bound
        }
      }
    }
  }

  private static func comparators(_ token: Substring) -> [Comparator] {
    let text = String(token)
    for (prefix, make) in [
      (">=", Comparator.atLeast), ("<=", Comparator.atMost), (">", Comparator.above),
      ("<", Comparator.below), ("=", Comparator.exactly),
    ] where text.hasPrefix(prefix) {
      return PackageVersion(String(text.dropFirst(prefix.count))).map { [make($0)] } ?? []
    }
    if text.hasPrefix("^"), let low = PackageVersion(String(text.dropFirst())) {
      return [.atLeast(low), .below(PackageVersion(major: low.major + 1, minor: 0, patch: 0))]
    }
    if text.hasPrefix("~"), let low = PackageVersion(String(text.dropFirst())) {
      return [
        .atLeast(low), .below(PackageVersion(major: low.major, minor: low.minor + 1, patch: 0)),
      ]
    }
    // Partial or wildcard versions, such as `4`, `4.x` and `*`.
    let parts = text.split(separator: ".").map(String.init)
    let numbers = parts.prefix { Int($0) != nil }.compactMap { Int($0) }
    switch numbers.count {
    case 0:
      return []
    case 1 where parts.count < 3:
      return [
        .atLeast(PackageVersion(major: numbers[0], minor: 0, patch: 0)),
        .below(PackageVersion(major: numbers[0] + 1, minor: 0, patch: 0)),
      ]
    case 2 where parts.count < 3 || Int(parts[2]) == nil:
      return [
        .atLeast(PackageVersion(major: numbers[0], minor: numbers[1], patch: 0)),
        .below(PackageVersion(major: numbers[0], minor: numbers[1] + 1, patch: 0)),
      ]
    default:
      return PackageVersion(text).map { [.exactly($0)] } ?? []
    }
  }
}
