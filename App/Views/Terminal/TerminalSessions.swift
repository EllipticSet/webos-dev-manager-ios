import Observation

/// The open terminals for one TV. They're kept above the tabs, which are rebuilt when the layout
/// switches between the tab bar and the sidebar, such as when iPhone Duo opens or closes.
@MainActor
@Observable
final class TerminalSessions {
  private(set) var sessions: [TerminalSession] = []
  var selectedID: TerminalSession.ID?
  private var nextNumber = 1

  var selected: TerminalSession? {
    sessions.first { $0.id == selectedID }
  }

  func open(service: DeviceService) {
    let session = TerminalSession(title: "Terminal \(nextNumber)", service: service)
    nextNumber += 1
    sessions.append(session)
    selectedID = session.id
  }

  func close(_ session: TerminalSession) {
    session.close()
    sessions.removeAll { $0.id == session.id }
    selectedID = sessions.last?.id
  }

  func closeAll() {
    sessions.forEach { $0.close() }
    sessions = []
    selectedID = nil
  }
}
