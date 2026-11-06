import SwiftUI

/// The repositories the Homebrew catalog lists apps from. Custom ones can also be offered to
/// Homebrew Channel on the TV, which asks to confirm with the remote.
struct RepositoriesView: View {
  var model: AppsModel
  var service: DeviceService

  @Environment(RepositoryStore.self) private var repositories
  @Environment(OperationCenter.self) private var operations
  @State private var isAdding = false
  @State private var address = ""
  @State private var offeredURL: URL?

  private var hasHomebrewChannel: Bool {
    model.installedApp(id: InstalledApp.homebrewChannelID) != nil
  }

  var body: some View {
    @Bindable var repositories = repositories
    Form {
      Section {
        Toggle(isOn: $repositories.isOfficialEnabled) {
          Text(RepositorySource.official.title)
          Text("repo.webosbrew.org")
        }
        Toggle(isOn: $repositories.isNonFreeEnabled) {
          Text(RepositorySource.nonFree.title)
          Text("Extra apps from repo.webosbrew.org that aren't open source")
        }
      } header: {
        Text("Built In")
      } footer: {
        Text("Homebrew Channel on the TV has the same options in its settings.")
      }

      Section {
        ForEach(repositories.customSources) { source in
          row(for: source)
        }
        .onDelete { repositories.remove(atOffsets: $0) }
        Button("Add Repository…", systemImage: "plus") {
          address = ""
          isAdding = true
        }
      } header: {
        Text("Custom")
      } footer: {
        Text(customFooter)
      }
    }
    .navigationTitle("Repositories")
    .navigationBarTitleDisplayMode(.inline)
    .alert("Add Repository", isPresented: $isAdding) {
      TextField("https://…/apps.json", text: $address)
        .keyboardType(.URL)
        .textContentType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      Button("Add") { add() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Enter the address of the repository's apps.json.")
    }
    .alert("Confirm on the TV", isPresented: isShowingOffer, presenting: offeredURL) { _ in
      Button("OK", role: .cancel) {}
    } message: { url in
      Text("Homebrew Channel opened on the TV with \(url.absoluteString). Select Add Repository with the remote to finish.")
    }
  }

  private var customFooter: String {
    let base = "Custom repositories are used by this app's catalog."
    guard hasHomebrewChannel else { return base }
    return base
      + " To use one in Homebrew Channel too, choose Add to TV and confirm on the TV. Remove repositories from the TV in Homebrew Channel's settings."
  }

  private func row(for source: RepositorySource) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(source.title)
        Text(source.url.absoluteString)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .textSelection(.enabled)
      }
      Spacer(minLength: 0)
      if hasHomebrewChannel {
        Button("Add to TV", systemImage: "tv") { offer(source) }
          .labelStyle(.iconOnly)
          .buttonStyle(.bordered)
          .accessibilityLabel("Add \(source.title) to the TV")
      }
    }
    .contextMenu {
      if hasHomebrewChannel {
        Button("Add to TV", systemImage: "tv") { offer(source) }
      }
      Button("Copy Address", systemImage: "doc.on.doc") {
        UIPasteboard.general.url = source.url
      }
      Button("Remove", systemImage: "trash", role: .destructive) {
        repositories.remove(source)
      }
    }
  }

  private var isShowingOffer: Binding<Bool> {
    Binding { offeredURL != nil } set: { if !$0 { offeredURL = nil } }
  }

  /// Checks that the address lists apps before keeping it.
  private func add() {
    guard let url = RepositorySource.customURL(from: address) else {
      operations.failure = .init(
        title: "Invalid Address", message: "Enter a web address, such as https://example.com/api/apps.json.")
      return
    }
    guard !repositories.contains(url) else {
      operations.failure = .init(
        title: "Already Added", message: "\(url.absoluteString) is already in the list.")
      return
    }
    let repositories = repositories
    operations.run("Checking Repository") { _ in
      _ = try await RepositoryClient().page(at: url)
      repositories.add(url)
    }
  }

  private func offer(_ source: RepositorySource) {
    let service = service
    operations.run("Opening Homebrew Channel") { _ in
      try await service.offerRepositoryToHomebrew(source.url)
      offeredURL = source.url
    }
  }
}
