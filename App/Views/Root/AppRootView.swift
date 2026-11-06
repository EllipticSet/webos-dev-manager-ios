import SwiftUI

/// Hosts the app's content with the splash screen and the lock above it.
struct AppRootView: View {
  @Environment(DeviceStore.self) private var store
  @Environment(CertificateStore.self) private var certificates
  @Environment(AppSettings.self) private var settings
  @Environment(AppLock.self) private var lock
  @Environment(\.scenePhase) private var scenePhase

  @State private var isShowingSplash = true
  @State private var lockWindow = LockWindowPresenter()

  var body: some View {
    ContentView()
      .tint(settings.accent)
      .overlay {
        if isShowingSplash {
          SplashView()
            .transition(.opacity)
        }
      }
      .task {
        TemporaryFiles.removeAll()
        try? await Task.sleep(for: .seconds(0.9))
        // The lock goes up first so the content is never visible between the two.
        updateLockWindow()
        withAnimation(.smooth) { isShowingSplash = false }
        // `scenePhase` here is the value from when the task started, before the app became active
        // on a cold launch, so the app's live state is asked instead. If it isn't active yet, the
        // prompt comes from the phase change below.
        if UIApplication.shared.applicationState == .active { await lock.promptBiometricsIfNeeded() }
      }
      .onChange(of: lock.isLocked) {
        if !isShowingSplash { updateLockWindow() }
      }
      .onChange(of: scenePhase) { _, phase in
        switch phase {
        case .background:
          lock.didEnterBackground()
        case .inactive:
          // iOS takes the app switcher's snapshot before the lock from entering the background can
          // appear, so the content has to be covered as soon as the app stops being active.
          if lock.hasPasscode, !lock.isLocked { lockWindow.show(PrivacyCover()) }
        case .active:
          lock.didBecomeActive()
          if !lock.isLocked { lockWindow.hide() }
          if !isShowingSplash {
            Task { await lock.promptBiometricsIfNeeded() }
          }
        @unknown default:
          break
        }
      }
  }

  private func updateLockWindow() {
    if lock.isLocked {
      lockWindow.show(
        LockView { eraseEverything() }
          .tint(settings.accent)
          .environment(lock))
    } else {
      lockWindow.hide()
    }
  }

  private func eraseEverything() {
    store.removeAll()
    certificates.removeAll()
    TemporaryFiles.removeAll()
    lock.removePasscode()
  }
}

/// Hides the content from the app switcher while the app isn't active.
private struct PrivacyCover: View {
  var body: some View {
    Image(systemName: "lock.fill")
      .font(.largeTitle)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(.systemBackground))
      .accessibilityHidden(true)
  }
}
