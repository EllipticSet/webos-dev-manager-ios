import SwiftUI

/// Sets, changes or turns off the passcode, asking for the current one first when there is one.
struct PasscodeSheet: View {
  enum Purpose: String, Identifiable {
    case create, change, remove
    var id: Self { self }
  }

  private enum Step {
    case current, new, confirm
  }

  var purpose: Purpose

  @Environment(AppLock.self) private var lock
  @Environment(\.dismiss) private var dismiss
  @State private var step = Step.new
  @State private var entered = ""
  @State private var firstEntry = ""
  @State private var message: String?
  @State private var failures = 0

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Text(prompt)
          .font(.headline)
        PasscodePad(entered: $entered, onComplete: submit)
        Text(message ?? " ")
          .font(.subheadline)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
      }
      .padding()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
      }
      .sensoryFeedback(.error, trigger: failures)
      .onAppear { step = purpose == .create ? .new : .current }
    }
    .interactiveDismissDisabled()
  }

  private var title: String {
    switch purpose {
    case .create: String(localized: "Set Passcode")
    case .change: String(localized: "Change Passcode")
    case .remove: String(localized: "Turn Off Passcode")
    }
  }

  private var prompt: String {
    switch step {
    case .current: String(localized: "Enter your current passcode")
    case .new: String(localized: "Enter a new 6-digit passcode")
    case .confirm: String(localized: "Enter it again to confirm")
    }
  }

  private func submit(_ value: String) {
    entered = ""
    message = nil
    switch step {
    case .current:
      guard lock.verify(value) else {
        failures += 1
        message = (lock.lockedUntil ?? .distantPast) > .now
          ? String(localized: "Too many attempts. Try again later.") : String(localized: "Incorrect passcode.")
        return
      }
      if purpose == .remove {
        lock.removePasscode()
        dismiss()
      } else {
        step = .new
      }
    case .new:
      firstEntry = value
      step = .confirm
    case .confirm:
      guard value == firstEntry else {
        failures += 1
        message = String(localized: "The passcodes didn't match. Try again.")
        step = .new
        return
      }
      do {
        try lock.setPasscode(value)
        dismiss()
      } catch {
        message = DeviceError.message(for: error)
        step = .new
      }
    }
  }
}
