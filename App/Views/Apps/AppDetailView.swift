import SwiftUI

/// An app's details, for both installed apps and the Homebrew catalog. Installed apps that aren't in
/// the catalog have no `catalogItem`, and show what the TV reports about them instead.
struct AppDetailView: View {
  var appID: String
  var catalogItem: RepositoryItem?
  var model: AppsModel
  var service: DeviceService

  @Environment(OperationCenter.self) private var operations
  @Environment(\.dismiss) private var dismiss
  @State private var isConfirmingRemoval = false

  private var installed: InstalledApp? { model.installedApp(id: appID) }
  private var title: String { catalogItem?.title ?? installed?.title ?? appID }
  private var manifest: PackageManifest? { catalogItem?.manifest }
  private var reasons: [IncompatibleReason] {
    catalogItem?.incompatibilities(with: model.details, homebrew: model.homebrew) ?? []
  }
  private var descriptionURL: URL? {
    catalogItem?.fullDescriptionUrl.flatMap(URL.init(string:))
  }

  var body: some View {
    Form {
      Section {
        header
      }

      if !reasons.isEmpty || manifest?.rootRequired == .required
        || manifest?.rootRequired == .optional
      {
        Section {
          ForEach(reasons, id: \.self) { reason in
            Label(reason.message, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
          }
          if manifest?.rootRequired == .required, !reasons.contains(.root) {
            Label("Requires a rooted TV.", systemImage: "lock.open")
          } else if manifest?.rootRequired == .optional {
            Label("Some features require root.", systemImage: "lock.open")
          }
        }
      }

      Section {
        if let manifest {
          let hasUpdate = manifest.hasUpdate(over: installed?.version)
          if installed == nil || hasUpdate {
            Button(
              hasUpdate ? "Update" : "Install",
              systemImage: hasUpdate ? "arrow.down" : "square.and.arrow.down"
            ) { install(manifest) }
            .disabled(!reasons.isEmpty)
          }
        }
        if installed != nil {
          Button("Open on TV", systemImage: "play.fill") { launch() }
          Button("Uninstall", systemImage: "trash", role: .destructive) {
            isConfirmingRemoval = true
          }
        }
      }

      descriptionSection

      if let source = manifest?.sourceUrl.flatMap(URL.init(string:)) {
        Section("Project Page") {
          Link(source.absoluteString, destination: source)
            .font(.subheadline)
        }
      }
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog(
      "Uninstall \(title)?", isPresented: $isConfirmingRemoval, titleVisibility: .visible
    ) {
      Button("Uninstall", role: .destructive) { uninstall() }
    } message: {
      if appID == InstalledApp.homebrewChannelID {
        Text("You're about to remove Homebrew Channel. If the TV is rooted, you'll lose root immediately.")
      }
    }
  }

  private var header: some View {
    HStack(spacing: 16) {
      if let catalogItem {
        RepositoryIcon(uri: catalogItem.detailIconUri ?? catalogItem.iconUri, size: 80)
      } else {
        RemoteAppIcon(path: installed?.iconPath, session: service.session, size: 80)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.title3.bold())
        if let version = manifest?.version {
          Text("Version \(version)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        if let installed {
          Text("Installed: \(installed.version)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  @ViewBuilder
  private var descriptionSection: some View {
    if let descriptionURL {
      Section("Description") {
        AppDescriptionView(
          url: descriptionURL,
          fallback: catalogItem?.shortDescription ?? installed?.appDescription)
      }
    } else if let text = catalogItem?.shortDescription ?? installed?.appDescription, !text.isEmpty {
      Section("Description") {
        Text(text)
      }
    }
  }

  private func install(_ manifest: PackageManifest) {
    let service = service
    let model = model
    operations.run("Installing \(title)") { progress in
      try await service.install(manifest: manifest, progress: progress)
      await model.load(service: service)
    }
  }

  private func launch() {
    let service = service
    let id = appID
    operations.run("Opening \(title)") { _ in
      try await service.launch(appID: id)
    }
  }

  private func uninstall() {
    let service = service
    let model = model
    let id = appID
    let leavesNothingToShow = catalogItem == nil
    operations.run("Uninstalling \(title)") { _ in
      try await service.uninstall(appID: id)
      await model.load(service: service)
      if leavesNothingToShow { dismiss() }
    }
  }
}
