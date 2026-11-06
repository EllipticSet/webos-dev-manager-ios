import SwiftUI
import UniformTypeIdentifiers

struct AppsView: View {
  var device: Device

  @Environment(DeviceStore.self) private var store
  @Environment(OperationCenter.self) private var operations
  @Environment(RepositoryStore.self) private var repositories
  @State private var section = AppsSection.installed
  @State private var model = AppsModel()
  @State private var isImporting = false

  private var service: DeviceService { store.service(for: device) }

  var body: some View {
    NavigationStack {
      Group {
        switch section {
        case .installed:
          InstalledAppsList(section: $section, device: device, model: model, service: service)
        case .homebrew:
          RepositoryListView(section: $section, device: device, model: model, service: service)
        }
      }
      .navigationTitle("Apps")
      .navigationDestination(for: AppsDestination.self) { _ in
        RepositoriesView(model: model, service: service)
      }
      .toolbar {
        AppMenu()
        ToolbarItemGroup(placement: .primaryAction) {
          if section == .homebrew {
            NavigationLink(value: AppsDestination.repositories) {
              Label("Repositories", systemImage: "server.rack")
            }
          }
          Button("Install IPK", systemImage: "square.and.arrow.down") { isImporting = true }
        }
      }
      .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item]) { result in
        install(result)
      }
      .task(id: repositories.enabledSources) {
        let sources = repositories.enabledSources
        guard model.installed.value == nil || model.sources != sources else { return }
        model.sources = sources
        await model.load(service: service)
      }
    }
  }

  private func install(_ result: Result<URL, Error>) {
    guard case .success(let url) = result else { return }
    guard url.pathExtension.lowercased() == "ipk" else {
      operations.failure = .init(
        title: "Invalid File", message: "Choose a package with the .ipk extension.")
      return
    }
    let service = service
    let model = model
    operations.run("Installing \(url.lastPathComponent)") { progress in
      let didAccess = url.startAccessingSecurityScopedResource()
      defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
      try await service.install(fileAt: url, progress: progress)
      await model.load(service: service)
    }
  }
}

enum AppsDestination: Hashable {
  case repositories
}

enum AppsSection: String, CaseIterable, Identifiable {
  case installed = "Installed"
  case homebrew = "Homebrew"

  var id: Self { self }
}

/// The picker between the Apps tab's lists, as their first row. Scrolling with the content keeps it
/// out of the navigation bar, where it would stop responding, and leaves the list's insets alone.
struct AppsSectionPicker: View {
  @Binding var section: AppsSection

  var body: some View {
    Section {
      Picker("Section", selection: $section) {
        ForEach(AppsSection.allCases) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())
    }
  }
}

/// The installed apps and repository lookups shared by both sections of the Apps tab.
@MainActor
@Observable
final class AppsModel {
  var installed: LoadState<[InstalledApp]> = .loading
  var updates: [String: RepositoryItem] = [:]
  var details: DeviceDetails?
  var homebrew: HomebrewConfiguration?
  /// The repositories updates are looked up in.
  var sources: [RepositorySource] = []

  func load(service: DeviceService) async {
    do {
      let apps = try await service.installedApps()
      installed = .loaded(apps)
      let ids = Set(apps.map(\.id))
      updates = await RepositoryClient().catalog(from: sources).filter { ids.contains($0.key) }
      details = try? await service.details()
      homebrew = try? await service.homebrewConfiguration()
    } catch is CancellationError {
    } catch {
      installed = .failed(DeviceError.message(for: error))
    }
  }

  func installedApp(id: String) -> InstalledApp? {
    installed.value?.first { $0.id == id }
  }
}

private struct InstalledAppsList: View {
  @Binding var section: AppsSection
  var device: Device
  var model: AppsModel
  var service: DeviceService

  @Environment(OperationCenter.self) private var operations
  @Environment(AppSettings.self) private var settings
  @State private var appToRemove: InstalledApp?

  var body: some View {
    List {
      AppsSectionPicker(section: $section)
      if let apps = model.installed.value {
        Section {
          ForEach(apps) { row(for: $0) }
        }
      }
    }
    .listSectionSpacing(.compact)
    .overlay { stateOverlay }
    .refreshable { await model.load(service: service) }
    .alert(
      removalTitle, isPresented: isConfirmingRemoval, presenting: appToRemove
    ) { app in
      Button("Uninstall", role: .destructive) { uninstall(app) }
      Button("Cancel", role: .cancel) {}
    } message: { app in
      if app.id == InstalledApp.homebrewChannelID {
        Text("You're about to remove Homebrew Channel. If the TV is rooted, you'll lose root immediately.")
      } else {
        Text("The app and its data will be removed from the TV.")
      }
    }
  }

  @ViewBuilder
  private var stateOverlay: some View {
    switch model.installed {
    case .loading:
      ProgressView("Loading…")
    case .failed(let message):
      ErrorStateView(message: message) { reload() }
    case .loaded(let apps):
      if apps.isEmpty {
        ContentUnavailableView(
          "No Apps Installed", systemImage: "square.grid.2x2",
          description: Text("Install an IPK or choose an app from the Homebrew catalog."))
      }
    }
  }

  private var removalTitle: String {
    "Uninstall \(appToRemove?.title ?? "the app")?"
  }

  private var isConfirmingRemoval: Binding<Bool> {
    Binding { appToRemove != nil } set: { if !$0 { appToRemove = nil } }
  }

  private func row(for app: InstalledApp) -> some View {
    let update = model.updates[app.id]
    let hasUpdate = update?.manifest?.hasUpdate(over: app.version) == true
    return NavigationLink {
      AppDetailView(appID: app.id, catalogItem: update, model: model, service: service)
    } label: {
      HStack(spacing: 12) {
        RemoteAppIcon(path: app.iconPath, session: service.session)
        VStack(alignment: .leading, spacing: 2) {
          Text(app.title).lineLimit(2)
          Text("\(app.version) · \(app.vendor ?? app.id)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
          if hasUpdate, let version = update?.manifest?.version {
            Text("Update available: \(version)")
              .font(.caption)
              .foregroundStyle(.tint)
          }
        }
        Spacer(minLength: 0)
        if hasUpdate, let manifest = update?.manifest {
          Button("Update", systemImage: "arrow.down") { installUpdate(manifest, of: app) }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Update \(app.title)")
        } else {
          Button("Open", systemImage: "play.fill") { launch(app) }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .accessibilityLabel("Open \(app.title)")
        }
      }
    }
    .swipeActions {
      Button("Uninstall", systemImage: "trash", role: .destructive) { appToRemove = app }
        .tint(.red)
      if hasUpdate, let manifest = update?.manifest {
        Button("Update", systemImage: "arrow.down.circle") { installUpdate(manifest, of: app) }
          .tint(settings.accent)
      }
    }
    .contextMenu {
      Button("Open on TV", systemImage: "play.fill") { launch(app) }
      if hasUpdate, let manifest = update?.manifest {
        Button("Update", systemImage: "arrow.down.circle") { installUpdate(manifest, of: app) }
      }
      Button("Uninstall", systemImage: "trash", role: .destructive) { appToRemove = app }
    }
  }

  private func reload() {
    model.installed = .loading
    Task { await model.load(service: service) }
  }

  private func launch(_ app: InstalledApp) {
    let service = service
    operations.run("Opening \(app.title)") { _ in
      try await service.launch(appID: app.id)
    }
  }

  private func installUpdate(_ manifest: PackageManifest, of app: InstalledApp) {
    let service = service
    let model = model
    operations.run("Updating \(app.title)") { progress in
      try await service.install(manifest: manifest, progress: progress)
      await model.load(service: service)
    }
  }

  private func uninstall(_ app: InstalledApp) {
    let service = service
    let model = model
    operations.run("Uninstalling \(app.title)") { _ in
      try await service.uninstall(appID: app.id)
      await model.load(service: service)
    }
  }
}

/// An installed app's icon, read from the TV over SSH.
struct RemoteAppIcon: View {
  var path: String?
  var session: DeviceSession
  var size: CGFloat = 44

  var body: some View {
    let session = session
    CachedIcon(key: path.map { IconCache.key(device: session.device.id, path: $0) }, size: size) {
      guard let path else { throw DeviceError.invalidResponse }
      return try await session.read(path)
    }
  }
}
