import Foundation

/// Reads the public webOS Homebrew repository.
struct RepositoryClient: Sendable {
  private static let base = URL(string: "https://repo.webosbrew.org/api/")!

  /// Pages are numbered from 1, and the first has no number in its URL.
  func page(_ number: Int) async throws -> RepositoryPage {
    let path = number > 1 ? "apps/\(number).json" : "apps.json"
    guard let url = URL(string: path, relativeTo: Self.base) else {
      throw DeviceError.invalidResponse
    }
    var page: RepositoryPage = try await fetch(url)
    page.packages = page.packages.map { $0.resolved(against: url) }
    return page
  }

  func latest(appID: String) async throws -> RepositoryItem {
    guard let url = URL(string: "apps/\(appID)/releases/latest.json", relativeTo: Self.base) else {
      throw DeviceError.invalidResponse
    }
    let item: RepositoryItem = try await fetch(url)
    return item.resolved(against: url)
  }

  /// Looks up many apps at once. Apps that aren't in the repository are left out.
  func latest(appIDs: [String]) async -> [String: RepositoryItem] {
    await withTaskGroup(of: RepositoryItem?.self) { group in
      for id in appIDs {
        group.addTask { try? await latest(appID: id) }
      }
      var items: [String: RepositoryItem] = [:]
      for await item in group {
        if let item { items[item.id] = item }
      }
      return items
    }
  }

  /// The HTML the repository publishes as an app's long description.
  func fullDescription(at url: URL) async throws -> String {
    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw DeviceError.repository("Couldn't load the description.")
    }
    return String(decoding: data, as: UTF8.self)
  }

  private func fetch<Value: Decodable>(_ url: URL) async throws -> Value {
    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
      throw DeviceError.repository("The repository request failed (HTTP \(http.statusCode)).")
    }
    do {
      return try JSONDecoder().decode(Value.self, from: data)
    } catch {
      throw DeviceError.repository("The repository sent invalid data.")
    }
  }
}
