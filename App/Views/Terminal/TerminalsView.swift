import SwiftTerm
import SwiftUI

struct TerminalsView: View {
  var device: Device
  var terminals: TerminalSessions

  @Environment(DeviceStore.self) private var store

  var body: some View {
    NavigationStack {
      Group {
        if let selected = terminals.selected {
          TerminalContent(session: selected)
            .safeAreaInset(edge: .top, spacing: 0) {
              SessionStrip(terminals: terminals)
            }
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
      .appMenu()
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
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

/// The open terminals, so it's clear which one is showing and how many are open.
private struct SessionStrip: View {
  var terminals: TerminalSessions

  var body: some View {
    ScrollViewReader { reader in
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(terminals.sessions) { session in
            chip(for: session)
              .id(session.id)
          }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
      }
      .scrollIndicators(.hidden)
      .background(.bar)
      .onChange(of: terminals.selectedID) {
        withAnimation(.smooth) { reader.scrollTo(terminals.selectedID) }
      }
    }
  }

  private func chip(for session: TerminalSession) -> some View {
    let isSelected = session.id == terminals.selectedID
    return Button {
      terminals.selectedID = session.id
    } label: {
      HStack(spacing: 6) {
        Circle()
          .fill(statusColor(session.status))
          .frame(width: 7, height: 7)
        Text(session.title)
      }
      .font(.subheadline.weight(isSelected ? .semibold : .regular))
      .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary), in: .capsule)
    }
    .buttonStyle(.plain)
    .accessibilityValue(statusDescription(session.status))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func statusColor(_ status: TerminalSession.Status) -> SwiftUI.Color {
    switch status {
    case .connecting: .orange
    case .connected: .green
    case .closed: .gray
    }
  }

  private func statusDescription(_ status: TerminalSession.Status) -> String {
    switch status {
    case .connecting: String(localized: "Connecting")
    case .connected: String(localized: "Connected")
    case .closed: String(localized: "Disconnected")
    }
  }
}

private struct TerminalContent: View {
  var session: TerminalSession

  var body: some View {
    TerminalRepresentable(view: session.view)
      .id(session.id)
      // Keeps the text off the display's rounded corners and, in a regular width, the sidebar.
      .padding(.horizontal, 8)
      .background(Color(uiColor: session.view.nativeBackgroundColor))
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
        Text(message ?? String(localized: "Session ended."))
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
