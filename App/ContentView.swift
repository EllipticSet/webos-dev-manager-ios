import SwiftUI

struct ContentView: View {
  @Environment(DeviceStore.self) private var store
  @Environment(OperationCenter.self) private var operations
  @Environment(AppNavigator.self) private var navigator
  @State private var isAddingDevice = false

  var body: some View {
    @Bindable var navigator = navigator
    Group {
      if let device = store.selected {
        MainTabsView(device: device)
      } else {
        NavigationStack {
          WelcomeView { isAddingDevice = true }
            .appMenu(isAlwaysShown: true)
        }
      }
    }
    .sheet(isPresented: $isAddingDevice) {
      AddDeviceFlow()
    }
    .sheet(item: $navigator.sheet) { sheet in
      switch sheet {
      case .manageTVs: DevicesView()
      case .certificates: CertificatesView()
      case .settings: SettingsView()
      case .about: AboutSheet()
      }
    }
    .overlay {
      if let activity = operations.activity {
        OperationProgressOverlay(activity: activity)
      }
    }
    .alert(
      operations.failure?.title ?? "", isPresented: isShowingFailure,
      presenting: operations.failure
    ) { _ in
      Button("OK", role: .cancel) {}
    } message: { failure in
      Text(failure.message)
    }
    .readsFold()
  }

  private var isShowingFailure: Binding<Bool> {
    Binding { operations.failure != nil } set: { if !$0 { operations.failure = nil } }
  }
}

/// In a regular width, such as on the inner display of iPhone Duo, the tabs move into a sidebar
/// that also holds the screens the top-left menu opens in a compact width.
private struct MainTabsView: View {
  var device: Device
  @Environment(AppNavigator.self) private var navigator
  @Environment(\.horizontalSizeClass) private var sizeClass
  @AppStorage("selectedTab") private var selectedTab = MainTab.apps
  @State private var lastDeviceTab = MainTab.apps
  @State private var terminals = TerminalSessions()

  var body: some View {
    Group {
      if sizeClass == .regular {
        NavigationSplitView {
          MainSidebar(device: device, selection: $selectedTab)
        } detail: {
          // A new identity for each row, because a screen pushed inside the detail, such as an
          // app's page, would otherwise stay in place when another row is chosen.
          screen(for: selectedTab)
            .id(selectedTab)
        }
        .navigationSplitViewStyle(.balanced)
      } else {
        TabView(selection: $selectedTab) {
          Tab("Apps", systemImage: "square.grid.2x2.fill", value: MainTab.apps) {
            screen(for: .apps)
          }
          Tab("Files", systemImage: "folder.fill", value: MainTab.files) {
            screen(for: .files)
          }
          Tab("Terminal", systemImage: "apple.terminal.fill", value: MainTab.terminal) {
            screen(for: .terminal)
          }
          Tab("Info", systemImage: "info.circle.fill", value: MainTab.info) {
            screen(for: .info)
          }
          Tab("Debug", systemImage: "ladybug.fill", value: MainTab.debug) {
            screen(for: .debug)
          }
        }
      }
    }
    .onChange(of: selectedTab, initial: true) {
      if selectedTab.sheet == nil { lastDeviceTab = selectedTab }
    }
    .onChange(of: sizeClass, initial: true) { carryScreenAcrossLayouts() }
    .onChange(of: device.id) { terminals.closeAll() }
  }

  /// The TV's screens are rebuilt for a new TV, but the sidebar isn't, so choosing a TV keeps it in
  /// place.
  @ViewBuilder
  private func screen(for tab: MainTab) -> some View {
    switch tab {
    case .apps: AppsView(device: device).id(device.id)
    case .files: FilesRootView(device: device).id(device.id)
    case .terminal: TerminalsView(device: device, terminals: terminals).id(device.id)
    case .info: InfoView(device: device).id(device.id)
    case .debug: DebugView(device: device).id(device.id)
    case .manageTVs: DevicesView(isPresentedAsSheet: false)
    case .certificates: CertificatesView(isPresentedAsSheet: false)
    case .settings: SettingsView(isPresentedAsSheet: false)
    case .about: NavigationStack { AboutView() }
    }
  }

  /// Keeps a menu screen open when the width changes, such as when iPhone Duo opens or closes: as a
  /// sheet in a compact width, where the sidebar's screens aren't available, and in the sidebar
  /// otherwise.
  private func carryScreenAcrossLayouts() {
    if sizeClass == .compact {
      guard let sheet = selectedTab.sheet else { return }
      selectedTab = lastDeviceTab
      navigator.sheet = sheet
    } else if let sheet = navigator.sheet {
      navigator.sheet = nil
      selectedTab = MainTab(sheet)
    }
  }
}

private struct MainSidebar: View {
  var device: Device
  @Binding var selection: MainTab

  var body: some View {
    List(selection: selectionBinding) {
      Section(device.name) {
        Label("Apps", systemImage: "square.grid.2x2").tag(MainTab.apps)
        Label("Files", systemImage: "folder").tag(MainTab.files)
        Label("Terminal", systemImage: "apple.terminal").tag(MainTab.terminal)
        Label("Info", systemImage: "info.circle").tag(MainTab.info)
        Label("Debug", systemImage: "ladybug").tag(MainTab.debug)
      }
      Section {
        Label("Manage TVs", systemImage: "tv").tag(MainTab.manageTVs)
        Label("Certificates", systemImage: "key").tag(MainTab.certificates)
        Label("Settings", systemImage: "gearshape").tag(MainTab.settings)
        Label("About", systemImage: "info.circle").tag(MainTab.about)
      }
    }
    .navigationTitle("Dev Manager")
  }

  /// A sidebar row can't be deselected, so the selection is never empty.
  private var selectionBinding: Binding<MainTab?> {
    Binding { selection } set: { if let tab = $0 { selection = tab } }
  }
}

private enum MainTab: String {
  case apps, files, terminal, info, debug
  case manageTVs, certificates, settings, about

  init(_ sheet: AppSheet) {
    switch sheet {
    case .manageTVs: self = .manageTVs
    case .certificates: self = .certificates
    case .settings: self = .settings
    case .about: self = .about
    }
  }

  /// The sheet that shows this tab's screen in a compact width, for the tabs that are sidebar-only.
  var sheet: AppSheet? {
    switch self {
    case .apps, .files, .terminal, .info, .debug: nil
    case .manageTVs: .manageTVs
    case .certificates: .certificates
    case .settings: .settings
    case .about: .about
    }
  }
}

private struct WelcomeView: View {
  var onAdd: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label("No TVs", systemImage: "tv")
    } description: {
      Text("Add a webOS TV with Developer Mode or root to install apps, manage files, and open a terminal.")
    } actions: {
      Button("Add TV", systemImage: "plus", action: onAdd)
        .buttonStyle(.borderedProminent)
    }
  }
}

private struct AboutSheet: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      AboutView()
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done", role: .confirm) { dismiss() }
          }
        }
    }
  }
}

/// An overlay rather than a sheet: what an operation presents when it ends, such as a file preview,
/// would otherwise collide with a sheet that is still dismissing.
private struct OperationProgressOverlay: View {
  var activity: OperationCenter.Activity
  @Environment(OperationCenter.self) private var operations

  var body: some View {
    ZStack {
      Color.black.opacity(0.3)
        .ignoresSafeArea()
      GeometryReader { proxy in
        panel
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(.offFold(in: proxy))
          .animation(.smooth, value: EdgeInsets.offFold(in: proxy))
      }
    }
  }

  private var panel: some View {
    VStack(spacing: 16) {
      Text(activity.title)
        .font(.headline)
        .multilineTextAlignment(.center)
      if let fraction = activity.fraction {
        ProgressView(value: min(max(fraction, 0), 1))
      } else {
        ProgressView()
      }
      if !activity.status.isEmpty {
        Text(activity.status)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      Button("Cancel", role: .cancel) { operations.cancel() }
        .buttonStyle(.bordered)
    }
    .padding(24)
    .frame(maxWidth: 340)
    .background(.regularMaterial, in: .rect(cornerRadius: 24))
    .padding()
    .accessibilityAddTraits(.isModal)
  }
}
