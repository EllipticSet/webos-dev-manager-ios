import Foundation

/// Reads webOS Homebrew repositories, which publish their apps in pages of JSON.
struct RepositoryClient: Sendable {
  private static let base = URL(string: "https://repo.webosbrew.org/api/")!
  /// Guards against a repository whose pages link back to each other.
  static let maximumPages = 50

  func page(at url: URL) async throws -> RepositoryPage {
    var page = try await pageWithoutManifests(at: url)
    page.packages = await withManifests(page.packages)
    return page
  }

  private func pageWithoutManifests(at url: URL) async throws -> RepositoryPage {
    var page: RepositoryPage = try await fetch(url)
    page.packages = page.packages.map { $0.resolved(against: url) }
    return page
  }

  /// Repositories can link an app's manifest instead of including it, and without it the app can't
  /// be installed. An app whose manifest can't be loaded is still listed.
  private func withManifests(_ items: [RepositoryItem]) async -> [RepositoryItem] {
    await withTaskGroup(of: (Int, PackageManifest?).self) { group in
      for (index, item) in items.enumerated() where item.manifest == nil {
        guard let url = item.manifestUrl.flatMap(URL.init(string:)) else { continue }
        group.addTask {
          let manifest: PackageManifest? = try? await fetch(url)
          return (index, manifest?.resolved(against: url))
        }
      }
      var items = items
      for await (index, manifest) in group {
        items[index].manifest = manifest
      }
      return items
    }
  }

  /// The latest release of an app in the official repository.
  func latest(appID: String) async throws -> RepositoryItem {
    guard let url = URL(string: "apps/\(appID)/releases/latest.json", relativeTo: Self.base) else {
      throw DeviceError.invalidResponse
    }
    let item: RepositoryItem = try await fetch(url)
    return await withManifests([item.resolved(against: url)])[0]
  }

  /// The apps with `appIDs` in the repositories, by ID. An app in more than one keeps the entry of
  /// the first. Only their manifests are loaded, and a repository that can't be read, in full or
  /// from one of its pages on, contributes the apps of the pages read before.
  func catalog(from sources: [RepositorySource], appIDs: Set<String>) async
    -> [String: RepositoryItem]
  {
    let lists = await withTaskGroup(of: (Int, [RepositoryItem]).self) { group in
      for (index, source) in sources.enumerated() {
        group.addTask { (index, await allItems(in: source)) }
      }
      var lists: [Int: [RepositoryItem]] = [:]
      for await (index, items) in group { lists[index] = items }
      return lists
    }
    var items: [String: RepositoryItem] = [:]
    for index in sources.indices {
      for item in lists[index] ?? [] where appIDs.contains(item.id) && items[item.id] == nil {
        items[item.id] = item
      }
    }
    let resolved = await withManifests(Array(items.values))
    return Dictionary(uniqueKeysWithValues: resolved.map { ($0.id, $0) })
  }

  /// The apps on every page of `source` up to the first that can't be read, without manifests.
  private func allItems(in source: RepositorySource) async -> [RepositoryItem] {
    var items: [RepositoryItem] = []
    var visited: Set<URL> = []
    var next: URL? = source.url
    while let url = next, visited.count < Self.maximumPages, visited.insert(url).inserted {
      guard let page = try? await pageWithoutManifests(at: url) else { break }
      items += page.packages
      next = page.nextURL(after: url, in: source)
    }
    return items
  }

  /// The HTML the repository publishes as an app's long description.
  func fullDescription(at url: URL) async throws -> String {
    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw DeviceError.repository(String(localized: "Couldn't load the description."))
    }
    return String(decoding: data, as: UTF8.self)
  }

  private func fetch<Value: Decodable>(_ url: URL) async throws -> Value {
    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
      throw DeviceError.repository(String(localized: "The repository request failed (HTTP \(http.statusCode))."))
    }
    do {
      return try JSONDecoder().decode(Value.self, from: data)
    } catch {
      throw DeviceError.repository(String(localized: "The repository sent invalid data."))
    }
  }
}
