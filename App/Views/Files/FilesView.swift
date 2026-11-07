import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct FilesRootView: View {
  var device: Device

  @Environment(DeviceStore.self) private var store
  @State private var home: LoadState<String> = .loading
  @State private var path: [String] = []

  var body: some View {
    NavigationStack(path: $path) {
      Group {
        switch home {
        case .loading:
          ProgressView("Connecting…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
          ErrorStateView(message: message) { Task { await loadHome() } }
        case .loaded(let directory):
          DirectoryView(directory: directory, device: device) { path.append($0) }
        }
      }
      .appMenu()
      .navigationDestination(for: String.self) { directory in
        DirectoryView(directory: directory, device: device) { path.append($0) }
      }
    }
    .task { if home.value == nil { await loadHome() } }
  }

  private func loadHome() async {
    home = .loading
    do {
      home = .loaded(try await store.service(for: device).session.homeDirectory())
    } catch is CancellationError {
    } catch {
      home = .failed(DeviceError.message(for: error))
    }
  }
}

struct DirectoryView: View {
  var directory: String
  var device: Device
  var navigate: (String) -> Void

  @Environment(DeviceStore.self) private var store
  @Environment(OperationCenter.self) private var operations
  @State private var files: LoadState<[RemoteFile]> = .loading
  @State private var selection = Set<String>()
  @State private var editMode = EditMode.inactive
  @State private var isUploading = false
  @State private var uploadsToConfirm: [URL] = []
  @State private var isCreatingFolder = false
  @State private var newFolderName = ""
  @State private var isGoingToPath = false
  @State private var pathToOpen = ""
  @State private var filesToDelete: [RemoteFile] = []
  @State private var previewURL: URL?
  @State private var exportURLs: [URL] = []
  @State private var isExporting = false

  private var session: DeviceSession { store.service(for: device).session }
  private var selectedFiles: [RemoteFile] {
    files.value?.filter { selection.contains($0.id) } ?? []
  }

  var body: some View {
    content
      .navigationTitle(directory == "/" ? "/" : (directory as NSString).lastPathComponent)
      .navigationBarTitleDisplayMode(.inline)
      .environment(\.editMode, $editMode)
      .toolbar { toolbar }
      .toolbar(editMode.isEditing ? .hidden : .automatic, for: .tabBar)
      .task { await load() }
      .refreshable { await load() }
      // SwiftUI honors only one file panel per view, so each gets its own.
      .background {
        Color.clear.fileImporter(
          isPresented: $isUploading, allowedContentTypes: [.item], allowsMultipleSelection: true
        ) { result in
          upload(result)
        }
      }
      .background {
        Color.clear.fileMover(isPresented: $isExporting, files: exportURLs) { _ in
          removeExportedCopies()
        } onCancellation: {
          removeExportedCopies()
        }
      }
      .quickLookPreview($previewURL)
      .onChange(of: previewURL) { previous, current in
        if let previous, current == nil { TemporaryFiles.remove(previous) }
      }
      .alert(replaceTitle, isPresented: isConfirmingReplace, presenting: uploadsToConfirm) { urls in
        Button("Replace", role: .destructive) { startUpload(urls) }
        Button("Cancel", role: .cancel) {}
      } message: { _ in
        Text("Files with the same name in this folder will be overwritten.")
      }
      .alert("New Folder", isPresented: $isCreatingFolder) {
        TextField("Name", text: $newFolderName)
        Button("Create") { createFolder() }
        Button("Cancel", role: .cancel) {}
      }
      .alert("Go to Folder", isPresented: $isGoingToPath) {
        TextField("Path", text: $pathToOpen)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        Button("Go") { goToPath() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Enter an absolute path, such as /media/developer.")
      }
      .confirmationDialog(
        deleteTitle, isPresented: isConfirmingDelete, titleVisibility: .visible
      ) {
        Button("Delete", role: .destructive) { delete(filesToDelete) }
      } message: {
        Text("This action can't be undone.")
      }
  }

  @ViewBuilder
  private var content: some View {
    switch files {
    case .loading:
      ProgressView("Loading…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let message):
      ErrorStateView(message: message) { Task { await load() } }
    case .loaded(let items):
      // A list with a selection binding treats a tap as selecting, which would stop rows from opening.
      List(items, selection: editMode.isEditing ? $selection : nil) { file in
        row(for: file)
      }
      .overlay {
        if items.isEmpty {
          ContentUnavailableView("Empty Folder", systemImage: "folder")
        }
      }
    }
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .principal) {
      VStack(spacing: 0) {
        Text(directory == "/" ? "/" : (directory as NSString).lastPathComponent)
          .font(.headline)
        Text(directory)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.head)
      }
    }
    if editMode.isEditing {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done", role: .confirm) { setEditing(false) }
      }
    } else {
      // Separate items rather than one menu, so the system moves the ones that don't fit into its
      // own overflow menu, which on iPhone Duo is the only one the vertical bar should have.
      ToolbarItemGroup(placement: .primaryAction) {
        Button("Upload Files…", systemImage: "square.and.arrow.up") { isUploading = true }
        Button("New Folder…", systemImage: "folder.badge.plus") {
          newFolderName = ""
          isCreatingFolder = true
        }
      }
      ToolbarItemGroup(placement: .primaryAction) {
        Button("Select", systemImage: "checklist") { setEditing(true) }
        Menu("Go To", systemImage: "arrow.turn.left.up") {
          if directory != "/" {
            Button("Parent Folder", systemImage: "arrow.up") {
              navigate((directory as NSString).deletingLastPathComponent)
            }
          }
          Button("Go to Folder…", systemImage: "arrow.right") {
            pathToOpen = directory
            isGoingToPath = true
          }
        }
      }
    }
    if editMode.isEditing {
      ToolbarItemGroup(placement: .bottomBar) {
        Button("Download", systemImage: "square.and.arrow.down") { download(selectedFiles) }
          .disabled(selectedFiles.isEmpty || selectedFiles.contains { $0.isDirectory })
        Spacer()
        Button("Delete", systemImage: "trash", role: .destructive) { filesToDelete = selectedFiles }
          .disabled(selectedFiles.isEmpty)
      }
    }
  }

  private func setEditing(_ isEditing: Bool) {
    withAnimation(.smooth) {
      editMode = isEditing ? .active : .inactive
      selection = []
    }
  }

  private func goToPath() {
    let target = pathToOpen.trimmingCharacters(in: .whitespacesAndNewlines)
    guard target.hasPrefix("/"), target != directory else { return }
    navigate(target)
  }

  private func row(for file: RemoteFile) -> some View {
    Group {
      if file.isDirectory {
        NavigationLink(value: file.path) { FileRow(file: file) }
      } else {
        Button { open(file) } label: { FileRow(file: file) }
          .foregroundStyle(.primary)
      }
    }
    .swipeActions {
      Button("Delete", systemImage: "trash", role: .destructive) { filesToDelete = [file] }
        .tint(.red)
      if !file.isDirectory {
        Button("Download", systemImage: "square.and.arrow.down") { download([file]) }
      }
    }
    .contextMenu {
      if !file.isDirectory {
        Button("Open", systemImage: "eye") { open(file) }
        Button("Download", systemImage: "square.and.arrow.down") { download([file]) }
      }
      Button("Delete", systemImage: "trash", role: .destructive) { filesToDelete = [file] }
    }
  }

  private var deleteTitle: String {
    filesToDelete.count == 1
      ? "Delete \(filesToDelete[0].name)?" : "Delete \(filesToDelete.count) Items?"
  }

  private var isConfirmingDelete: Binding<Bool> {
    Binding { !filesToDelete.isEmpty } set: { if !$0 { filesToDelete = [] } }
  }

  private func load() async {
    do {
      files = .loaded(try await session.list(directory))
    } catch is CancellationError {
    } catch {
      files = .failed(DeviceError.message(for: error))
    }
  }

  private func fetch(_ file: RemoteFile, progress: OperationCenter.Progress?) async throws -> URL {
    let destination = try TemporaryFiles.makeURL(named: file.name)
    let total = file.size
    do {
      try await session.download(file.path, to: destination) { written in
        progress?(total > 0 ? Double(written) / Double(total) : nil, file.name)
      }
    } catch {
      TemporaryFiles.remove(destination)
      throw error
    }
    return destination
  }

  private func removeExportedCopies() {
    exportURLs.forEach(TemporaryFiles.remove)
    exportURLs = []
  }

  private func open(_ file: RemoteFile) {
    operations.run("Opening \(file.name)") { progress in
      let url = try await fetch(file, progress: progress)
      previewURL = url
    }
  }

  private func download(_ items: [RemoteFile]) {
    guard !items.isEmpty else { return }
    operations.run("Downloading from TV") { progress in
      var urls: [URL] = []
      do {
        for file in items {
          urls.append(try await fetch(file, progress: progress))
        }
      } catch {
        urls.forEach(TemporaryFiles.remove)
        throw error
      }
      exportURLs = urls
      isExporting = true
    }
  }

  private func upload(_ result: Result<[URL], Error>) {
    guard case .success(let urls) = result, !urls.isEmpty else { return }
    let existing = Set(files.value?.map(\.name) ?? [])
    if urls.contains(where: { existing.contains($0.lastPathComponent) }) {
      uploadsToConfirm = urls
    } else {
      startUpload(urls)
    }
  }

  private var replaceTitle: String {
    uploadsToConfirm.count == 1
      ? "Replace \(uploadsToConfirm[0].lastPathComponent)?" : "Replace Existing Files?"
  }

  private var isConfirmingReplace: Binding<Bool> {
    Binding { !uploadsToConfirm.isEmpty } set: { if !$0 { uploadsToConfirm = [] } }
  }

  private func startUpload(_ urls: [URL]) {
    let directory = directory
    let session = session
    operations.run("Uploading to TV") { progress in
      for url in urls {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        try await session.uploadReplacing(url, to: directory.appendingPathSegment(name)) {
          progress($0, name)
        }
      }
      await load()
    }
  }

  private func createFolder() {
    let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !name.contains("/") else { return }
    let path = directory.appendingPathSegment(name)
    let session = session
    operations.run("Creating Folder") { _ in
      try await session.makeDirectory(path)
      await load()
    }
  }

  private func delete(_ items: [RemoteFile]) {
    let session = session
    operations.run("Deleting") { progress in
      for file in items {
        progress(nil, file.name)
        try await session.remove(file.path, recursive: file.isDirectory && !file.isLink)
      }
      selection = []
      editMode = .inactive
      await load()
    }
  }
}

private struct FileRow: View {
  var file: RemoteFile

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: file.systemImage)
        .foregroundStyle(file.isDirectory ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(width: 28)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(file.name).lineLimit(2)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .contentShape(.rect)
  }

  private var subtitle: String {
    var parts: [String] = []
    if !file.isDirectory {
      parts.append(file.size.formatted(.byteCount(style: .file)))
    }
    if let modified = file.modified {
      parts.append(modified.formatted(date: .abbreviated, time: .shortened))
    }
    if !file.mode.isEmpty { parts.append(file.mode) }
    return parts.joined(separator: " · ")
  }
}
