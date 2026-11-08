import SwiftUI

/// The add-TV wizard: choose how the TV is reached, get it ready, then enter its details.
struct AddDeviceFlow: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(DeviceSetupMode.allCases) { mode in
            NavigationLink {
              destination(for: mode)
            } label: {
              Label {
                VStack(alignment: .leading, spacing: 2) {
                  Text(mode.title)
                  Text(mode.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              } icon: {
                Image(systemName: mode.systemImage)
              }
            }
          }
        } header: {
          Text("How do you want to connect the TV?")
        }
      }
      .navigationTitle("Add TV")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
      }
    }
    .environment(\.dismissAddFlow, DismissAddFlowAction { dismiss() })
  }

  @ViewBuilder
  private func destination(for mode: DeviceSetupMode) -> some View {
    switch mode {
    case .developerMode:
      DevModeChecklistView()
    case .rooted, .advanced:
      DeviceEditorView(device: mode.makeDevice(), secrets: DeviceSecrets(), isNew: true)
    }
  }
}

struct DismissAddFlowAction {
  var action: () -> Void
  func callAsFunction() { action() }
}

extension EnvironmentValues {
  @Entry var dismissAddFlow: DismissAddFlowAction?
}

private struct DevModeChecklistView: View {
  private struct Step: Identifiable {
    var id: String { title }
    var title: String
    var details: [LocalizedStringKey]
  }

  private let steps = [
    Step(
      title: String(localized: "Prepare a Developer Account"),
      details: [
        "In your browser, open [LG’s Developer Mode guide](https://webostv.developer.lge.com/develop/getting-started/developer-mode-app).",
        "Select “SIGN IN” at the top right of the page.",
        "Create a free LG Developer account, or sign in if you already have one.",
      ]),
    Step(
      title: String(localized: "Install the Developer Mode App"),
      details: [
        "Open the LG Content Store on the TV.", "Search for “Developer Mode”.", "Select Install.",
      ]),
    Step(
      title: String(localized: "Turn On Developer Mode"),
      details: [
        "Open the Developer Mode app.", "Sign in with your developer account.",
        "Turn on Developer Mode and wait for the TV to restart.",
      ]),
    Step(
      title: String(localized: "Prepare the Connection"),
      details: [
        "Open the Developer Mode app again.", "Make sure “Dev Mode Status” is ON.",
        "Turn on Key Server.", "Note the IP address and passphrase shown on the screen.",
      ]),
  ]

  @State private var completed: Set<String> = []

  var body: some View {
    List {
      ForEach(steps) { step in
        Section {
          Toggle(isOn: binding(for: step)) {
            Text(step.title).font(.headline)
          }
          // A finished step folds away, as in Dev Manager for desktop.
          if !completed.contains(step.id) {
            ForEach(Array(step.details.enumerated()), id: \.offset) { index, detail in
              Label(detail, systemImage: "\(index + 1).circle")
                .font(.subheadline)
            }
          }
        }
      }
      Section {
        NavigationLink("Continue") {
          DeviceEditorView(
            device: DeviceSetupMode.developerMode.makeDevice(), secrets: DeviceSecrets(),
            isNew: true)
        }
        .disabled(completed.count < steps.count)
      } footer: {
        Text("Check off each step when you've finished it. Keep your iPhone and TV on the same Wi-Fi network.")
      }
    }
    .navigationTitle("Developer Mode")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func binding(for step: Step) -> Binding<Bool> {
    Binding {
      completed.contains(step.id)
    } set: { isDone in
      withAnimation(.smooth) {
        if isDone { completed.insert(step.id) } else { completed.remove(step.id) }
      }
    }
  }
}
