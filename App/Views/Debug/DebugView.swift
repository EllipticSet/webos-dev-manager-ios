import SwiftUI

struct DebugView: View {
  var device: Device

  @Environment(DeviceStore.self) private var store
  private var service: DeviceService { store.service(for: device) }

  var body: some View {
    NavigationStack {
      List {
        Section {
          NavigationLink(value: DebugDestination.crashReports) {
            Label("Crash Reports", systemImage: "exclamationmark.triangle")
          }
        }
        if device.isDevMode {
          Section {
          } footer: {
            Text("Syslog, dmesg, and ls-monitor require a rooted TV.")
          }
        } else {
          Section("System Logs") {
            NavigationLink(value: DebugDestination.syslog) {
              Label("Syslog", systemImage: "list.bullet.rectangle")
            }
            NavigationLink(value: DebugDestination.dmesg) {
              Label("dmesg", systemImage: "cpu")
            }
            NavigationLink(value: DebugDestination.logLevels) {
              Label("Log Levels", systemImage: "slider.horizontal.3")
            }
          }
          Section("Luna Bus") {
            NavigationLink(value: DebugDestination.lunaMonitor) {
              Label("ls-monitor", systemImage: "point.3.connected.trianglepath.dotted")
            }
          }
        }
      }
      .navigationTitle("Debug")
      .appMenu()
      .navigationDestination(for: DebugDestination.self) { destination in
        switch destination {
        case .crashReports: CrashReportsView(service: service)
        case .crashReport(let report): CrashReportDetailView(report: report, service: service)
        case .syslog: LogStreamView(kind: .syslog, service: service)
        case .dmesg: LogStreamView(kind: .dmesg, service: service)
        case .logLevels: PmLogLevelsView(service: service)
        case .lunaMonitor: LunaMonitorView(service: service)
        }
      }
    }
  }
}

/// Screens are pushed with values rather than destination views: in a regular width, a screen
/// pushed with a destination view stays in place when another sidebar row is chosen.
enum DebugDestination: Hashable {
  case crashReports
  case crashReport(CrashReport)
  case syslog
  case dmesg
  case logLevels
  case lunaMonitor
}
