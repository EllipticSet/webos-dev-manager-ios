import SwiftTerm
import SwiftUI

struct TerminalsView: View {
  var device: Device
  var terminals: TerminalSessions

  @Environment(DeviceStore.self) private var store

  var body: some View {
    @Bindable var terminals = terminals
    NavigationStack {
      Group {
        if let selected = terminals.selected {
          TerminalContent(session: selected)
        } else {
          ContentUnavailableView {
            Label("No Open Terminals", systemImage: "apple.terminal")
          } description: {
            Text("Open a shell on \(device.name).")
          } actions: {
            Button("Open Terminal", systemImage: "plus") { openTerminal() }
              .buttonStyle(.borderedProminent)
          }
        }
      }
      .navigationTitle("Terminal")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        AppMenu()
        ToolbarItemGroup(placement: .primaryAction) {
          if terminals.sessions.count > 1 {
            Picker("Session", selection: $terminals.selectedID) {
              ForEach(terminals.sessions) { Text($0.title).tag(Optional($0.id)) }
            }
            .pickerStyle(.menu)
          }
          if let selected = terminals.selected {
            // The keyboard covers the tab bar, so this is also the way out of this tab.
            Button("Hide Keyboard", systemImage: "keyboard.chevron.compact.down") {
              _ = selected.view.resignFirstResponder()
            }
            Button("Close Terminal", systemImage: "xmark") { terminals.close(selected) }
          }
          Button("New Terminal", systemImage: "plus") { openTerminal() }
        }
      }
    }
  }

  private func openTerminal() {
    terminals.open(service: store.service(for: device))
  }
}

private struct TerminalContent: View {
  var session: TerminalSession

  var body: some View {
    TerminalRepresentable(view: session.view)
      .id(session.id)
      .ignoresSafeArea(.container, edges: .bottom)
      .overlay(alignment: .top) { statusBanner }
  }

  @ViewBuilder
  private var statusBanner: some View {
    switch session.status {
    case .connecting:
      Label("Connecting…", systemImage: "network")
        .banner()
    case .connected:
      EmptyView()
    case .closed(let message):
      HStack {
        Text(message ?? "Session ended.")
        Button("Reconnect") { session.start() }
          .buttonStyle(.bordered)
      }
      .banner()
    }
  }
}

extension View {
  fileprivate func banner() -> some View {
    font(.subheadline)
      .padding(12)
      .background(.regularMaterial, in: .rect(cornerRadius: 12))
      .padding()
  }
}

private struct TerminalRepresentable: UIViewRepresentable {
  var view: TerminalView

  func makeUIView(context: Context) -> TerminalView {
    DispatchQueue.main.async { _ = view.becomeFirstResponder() }
    return view
  }

  func updateUIView(_ uiView: TerminalView, context: Context) {}
}
