import SwiftUI

struct RepositoryListView: View {
  @Binding var section: AppsSection
  var device: Device
  var model: AppsModel
  var service: DeviceService

  @Environment(RepositoryStore.self) private var repositories
  @State private var feeds: [RepositoryFeed] = []
  @State private var isLoading = false
  /// Changes after every load, so the loading row asks for the next page.
  @State private var loadCount = 0
  @State private var searchText = ""

  private var isPending: Bool { feeds.contains(where: \.isPending) }

  var body: some View {
    List {
      AppsSectionPicker(section: $section)
      ForEach(feeds) { feed in
        let items = visibleItems(of: feed)
        let showsError = feed.errorMessage != nil && searchText.isEmpty && !hasOnlyErrors
        if !items.isEmpty || showsError {
          Section {
            ForEach(items) { item in
              NavigationLink {
                AppDetailView(appID: item.id, catalogItem: item, model: model, service: service)
              } label: {
                RepositoryRow(item: item, installed: model.installedApp(id: item.id))
              }
            }
            if showsError, let errorMessage = feed.errorMessage {
              Text(errorMessage).foregroundStyle(.secondary).font(.footnote)
              Button("Try Again", systemImage: "arrow.clockwise") { retry(feed) }
            }
          } header: {
            if feeds.count > 1 { Text(feed.source.title) }
          }
        }
      }
      if isPending {
        HStack {
          Spacer()
          ProgressView()
          Spacer()
        }
        .listRowSeparator(.hidden)
        .task(id: loadCount) { await loadNext() }
      }
    }
    .listSectionSpacing(.compact)
    .overlay { stateOverlay }
    .searchable(text: $searchText, prompt: "Search Apps")
    .refreshable { reset() }
    .task(id: repositories.enabledSources) {
      if feeds.map(\.source) != repositories.enabledSources { reset() }
    }
  }

  /// Every repository failed before listing any app.
  private var hasOnlyErrors: Bool {
    !feeds.isEmpty && feeds.allSatisfy { $0.items.isEmpty && $0.errorMessage != nil }
  }

  @ViewBuilder
  private var stateOverlay: some View {
    if repositories.enabledSources.isEmpty {
      ContentUnavailableView {
        Label("No Repositories", systemImage: "server.rack")
      } description: {
        Text("Turn on a repository to browse its apps.")
      } actions: {
        NavigationLink("Repositories", value: AppsDestination.repositories)
      }
    } else if hasOnlyErrors, let message = feeds.first?.errorMessage {
      ErrorStateView(message: message) { feeds.indices.forEach { feeds[$0].errorMessage = nil } }
    } else if !feeds.isEmpty, feeds.allSatisfy({ $0.items.isEmpty && !$0.isPending && $0.errorMessage == nil }) {
      ContentUnavailableView(
        "No Apps", systemImage: "square.grid.2x2",
        description: Text("The repositories you turned on don't have any apps."))
    }
  }

  private func visibleItems(of feed: RepositoryFeed) -> [RepositoryItem] {
    guard !searchText.isEmpty else { return feed.items }
    return feed.items.filter {
      $0.title.localizedCaseInsensitiveContains(searchText)
        || $0.id.localizedCaseInsensitiveContains(searchText)
    }
  }

  private func reset() {
    feeds = repositories.enabledSources.map(RepositoryFeed.init(source:))
  }

  private func retry(_ feed: RepositoryFeed) {
    guard let index = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
    feeds[index].errorMessage = nil
  }

  /// Loads the repositories one page at a time, in order.
  private func loadNext() async {
    guard !isLoading, let index = feeds.firstIndex(where: \.isPending),
      let url = feeds[index].nextURL
    else { return }
    let source = feeds[index].source
    isLoading = true
    defer {
      isLoading = false
      loadCount += 1
    }
    do {
      let page = try await RepositoryClient().page(at: url)
      // The repositories may have changed while the page loaded.
      guard index < feeds.count, feeds[index].source == source else { return }
      feeds[index].items.append(contentsOf: page.packages)
      feeds[index].nextURL = page.nextURL(after: url, in: source)
    } catch is CancellationError {
    } catch let error as URLError where error.code == .cancelled {
    } catch {
      guard index < feeds.count, feeds[index].source == source else { return }
      feeds[index].errorMessage = DeviceError.message(for: error)
    }
  }
}

/// A repository's apps, as far as they've loaded.
private struct RepositoryFeed: Identifiable {
  var source: RepositorySource
  var items: [RepositoryItem] = []
  var nextURL: URL?
  var errorMessage: String?

  var id: URL { source.id }
  var isPending: Bool { nextURL != nil && errorMessage == nil }

  init(source: RepositorySource) {
    self.source = source
    nextURL = source.url
  }
}

private struct RepositoryRow: View {
  var item: RepositoryItem
  var installed: InstalledApp?

  var body: some View {
    HStack(spacing: 12) {
      RepositoryIcon(uri: item.iconUri, size: 44)
      VStack(alignment: .leading, spacing: 2) {
        Text(item.title).lineLimit(2)
        if let summary = item.shortDescription {
          Text(summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        if let installed {
          let hasUpdate = item.manifest?.hasUpdate(over: installed.version) == true
          Text(hasUpdate ? "Update Available" : "Installed")
            .font(.caption)
            .foregroundStyle(.tint)
        }
      }
    }
  }
}

/// A repository app's icon, downloaded from the repository.
struct RepositoryIcon: View {
  var uri: String?
  var size: CGFloat

  private var url: URL? { uri.flatMap(URL.init(string:)) }

  var body: some View {
    let url = url
    CachedIcon(key: url.map(IconCache.key(url:)), size: size) {
      guard let url else { throw URLError(.badURL) }
      let (data, response) = try await URLSession.shared.data(from: url)
      if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        throw URLError(.badServerResponse)
      }
      return data
    }
  }
}
