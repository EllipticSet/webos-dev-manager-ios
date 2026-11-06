import SwiftUI

struct RepositoryListView: View {
  @Binding var section: AppsSection
  var device: Device
  var model: AppsModel
  var service: DeviceService

  @State private var items: [RepositoryItem] = []
  @State private var nextPage: Int? = 1
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var searchText = ""

  private var visibleItems: [RepositoryItem] {
    guard !searchText.isEmpty else { return items }
    return items.filter {
      $0.title.localizedCaseInsensitiveContains(searchText)
        || $0.id.localizedCaseInsensitiveContains(searchText)
    }
  }

  var body: some View {
    List {
      AppsSectionPicker(section: $section)
      Section {
        ForEach(visibleItems) { item in
          NavigationLink {
            AppDetailView(appID: item.id, catalogItem: item, model: model, service: service)
          } label: {
            RepositoryRow(item: item, installed: model.installedApp(id: item.id))
          }
        }
        if nextPage != nil {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
          .listRowSeparator(.hidden)
          .task(id: items.count) { await loadNext() }
        }
        if let errorMessage, !items.isEmpty {
          Text(errorMessage).foregroundStyle(.secondary).font(.footnote)
        }
      }
    }
    .listSectionSpacing(.compact)
    .overlay {
      if let errorMessage, items.isEmpty {
        ErrorStateView(message: errorMessage) { Task { await loadNext() } }
      }
    }
    .searchable(text: $searchText, prompt: "Search Apps")
    .refreshable {
      items = []
      nextPage = 1
      errorMessage = nil
    }
  }

  private func loadNext() async {
    guard let page = nextPage, !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let result = try await RepositoryClient().page(page)
      items.append(contentsOf: result.packages)
      nextPage = result.paging.page < result.paging.maxPage ? result.paging.page + 1 : nil
      errorMessage = nil
    } catch is CancellationError {
    } catch let error as URLError where error.code == .cancelled {
    } catch {
      errorMessage = DeviceError.message(for: error)
      nextPage = items.isEmpty ? 1 : nil
    }
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

struct RepositoryIcon: View {
  var uri: String?
  var size: CGFloat

  var body: some View {
    AsyncImage(url: uri.flatMap(URL.init(string:))) { image in
      image.resizable().scaledToFit()
    } placeholder: {
      Image(systemName: "app.dashed")
        .font(.title)
        .foregroundStyle(.secondary)
    }
    .frame(width: size, height: size)
    .clipShape(.rect(cornerRadius: size * 0.22))
    .accessibilityHidden(true)
  }
}
