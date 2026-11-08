import SwiftUI

struct LockView: View {
  var eraseEverything: () -> Void

  @Environment(AppLock.self) private var lock
  @State private var entered = ""
  @State private var failures = 0
  @State private var isConfirmingErase = false
  @State private var lockoutRefresh = 0

  var body: some View {
    VStack(spacing: 24) {
      Spacer(minLength: 0)
      Image(systemName: "lock.fill")
        .font(.largeTitle)
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
      Text("Enter Passcode")
        .font(.title2.bold())
      PasscodePad(entered: $entered, isDisabled: isLockedOut, onComplete: submit)
      // The space is reserved so the pad doesn't move when a message appears.
      ZStack {
        Color.clear.frame(height: 22)
        status
      }
      Spacer(minLength: 0)
      VStack(spacing: 14) {
        if lock.biometricsEnabled && lock.isBiometryAvailable {
          Button(lock.biometryName, systemImage: lock.biometrySymbol) {
            Task { await lock.unlockWithBiometrics() }
          }
        }
        Button("Forgot Passcode?") { isConfirmingErase = true }
      }
      .font(.subheadline)
      .frame(maxWidth: .infinity)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
    .sensoryFeedback(.error, trigger: failures)
    .task(id: lock.lockedUntil) {
      // Re-enables the pad when the wait is over.
      guard let until = lock.lockedUntil, until > .now else { return }
      try? await Task.sleep(until: .now + .seconds(until.timeIntervalSinceNow))
      lockoutRefresh += 1
    }
    .alert("Erase All Data?", isPresented: $isConfirmingErase) {
      Button("Erase Data and Passcode", role: .destructive, action: eraseEverything)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("A forgotten passcode can't be recovered. This removes the passcode, saved TVs, and certificates from this iPhone. Your TVs aren't changed.")
    }
  }

  private var isLockedOut: Bool {
    _ = lockoutRefresh
    return (lock.lockedUntil ?? .distantPast) > .now
  }

  @ViewBuilder
  private var status: some View {
    if let until = lock.lockedUntil, until > .now {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        let seconds = Int(until.timeIntervalSince(context.date).rounded(.up))
        Text(seconds > 0 ? String(localized: "Too many attempts. Try again in \(seconds) s.") : String(localized: "You can try again now."))
          .foregroundStyle(.secondary)
      }
      .font(.subheadline)
    } else if failures > 0 {
      Text("Incorrect passcode.")
        .font(.subheadline)
        .foregroundStyle(.red)
    }
  }

  private func submit(_ passcode: String) {
    if !lock.unlock(with: passcode) { failures += 1 }
    entered = ""
  }
}
