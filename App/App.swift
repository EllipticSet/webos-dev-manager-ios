import SwiftUI

@main
struct DevManagerApp: App {
  @State private var store = DeviceStore()
  @State private var certificates = CertificateStore()
  @State private var operations = OperationCenter()
  @State private var navigator = AppNavigator()
  @State private var settings = AppSettings()
  @State private var lock = AppLock()
  @State private var repositories = RepositoryStore()

  var body: some Scene {
    WindowGroup {
      AppRootView()
        .environment(store)
        .environment(certificates)
        .environment(operations)
        .environment(navigator)
        .environment(settings)
        .environment(lock)
        .environment(repositories)
    }
  }
}
