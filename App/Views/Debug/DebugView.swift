import SwiftUI

struct DebugView: View {
  var device: Device

  @Environment(DeviceStore.self) private var store
  private var service: DeviceService { store.service(for: device) }

  var body: some View {
    NavigationStack {
      List {
        Section {
          NavigationLink {
            CrashReportsView(service: service)
          } label: {
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
            NavigationLink {
              LogStreamView(kind: .syslog, service: service)
            } label: {
              Label("Syslog", systemImage: "list.bullet.rectangle")
            }
            NavigationLink {
              LogStreamView(kind: .dmesg, service: service)
            } label: {
              Label("dmesg", systemImage: "cpu")
            }
            NavigationLink {
              PmLogLevelsView(service: service)
            } label: {
              Label("Log Levels", systemImage: "slider.horizontal.3")
            }
          }
          Section("Luna Bus") {
            NavigationLink {
              LunaMonitorView(service: service)
            } label: {
              Label("ls-monitor", systemImage: "point.3.connected.trianglepath.dotted")
            }
          }
        }
      }
      .navigationTitle("Debug")
      .toolbar { AppMenu() }
    }
  }
}
