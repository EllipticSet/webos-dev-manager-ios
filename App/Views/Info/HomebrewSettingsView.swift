import SwiftUI

/// Homebrew Channel's root settings, as on the Settings screen of its app on the TV.
struct HomebrewSettingsView: View {
  var device: Device
  var service: DeviceService

  @Environment(OperationCenter.self) private var operations
  @State private var configuration: LoadState<HomebrewConfiguration> = .loading
  /// Set once a change is made, until the TV restarts.
  @State private var needsRestart = false
  @State private var isConfirmingSSHOff = false
  @State private var isConfirmingRestart = false

  var body: some View {
    Group {
      switch configuration {
      case .loading:
        ProgressView("Loading…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .failed(let message):
        ErrorStateView(message: message) { Task { await load() } }
      case .loaded(let configuration):
        form(configuration)
      }
    }
    .navigationTitle("Root Settings")
    .navigationBarTitleDisplayMode(.inline)
    .task { if configuration.value == nil { await load() } }
  }

  private func form(_ configuration: HomebrewConfiguration) -> some View {
    let isRoot = configuration.root == true
    return Form {
      if needsRestart {
        Section {
          Label("Restart the TV to apply the changes.", systemImage: "arrow.clockwise")
        }
      }

      Section {
        ForEach(HomebrewSetting.allCases) { setting in
          let toggle = Toggle(isOn: binding(for: setting, in: configuration)) {
            Text(setting.title)
            if let details = setting.details { Text(details) }
          }
          if setting == .sshServer {
            toggle.confirmationPopover(
              "Turn Off SSH Server?", isPresented: $isConfirmingSSHOff, arrowEdge: .top,
              message: "This app signs in to \(device.name) with SSH. After the TV restarts, it can't connect until you turn SSH Server back on in Homebrew Channel on the TV.",
              actionTitle: "Turn Off", role: .destructive
            ) { change(.sshServer, to: false) }
          } else {
            toggle
          }
        }
      } header: {
        Text("Root Configuration")
      } footer: {
        if !isRoot {
          Text("These settings need Homebrew Channel to have root. Open it on the TV to check its root status.")
        }
      }
      .disabled(!isRoot)

      Section {
        Button("Restart TV", systemImage: "power") { isConfirmingRestart = true }
          .disabled(!isRoot)
          .confirmationPopover(
            "Restart \(device.name)?", isPresented: $isConfirmingRestart, arrowEdge: .bottom,
            message: "The TV turns off and on again, which closes open terminals and file transfers.",
            actionTitle: "Restart"
          ) { restart() }
      } footer: {
        Text("Configuration changes apply when the TV restarts.")
      }
    }
    .refreshable { await load() }
  }

  /// Shows the TV's value: a change only shows once the TV confirms it.
  private func binding(for setting: HomebrewSetting, in configuration: HomebrewConfiguration)
    -> Binding<Bool>
  {
    Binding {
      configuration.isOn(setting) ?? false
    } set: { isOn in
      if setting == .sshServer, !isOn, device.isRoot {
        isConfirmingSSHOff = true
      } else {
        change(setting, to: isOn)
      }
    }
  }

  private func load() async {
    do {
      configuration = .loaded(try await service.homebrewConfiguration())
    } catch is CancellationError {
    } catch {
      configuration = .failed(DeviceError.message(for: error))
    }
  }

  private func change(_ setting: HomebrewSetting, to isOn: Bool) {
    let service = service
    operations.run("Changing \(setting.title)") { _ in
      configuration = .loaded(try await service.setHomebrewSetting(setting, isOn: isOn))
      needsRestart = true
    }
  }

  private func restart() {
    let service = service
    operations.run("Restarting TV") { _ in
      try await service.restartWithHomebrew()
      needsRestart = false
    }
  }
}
