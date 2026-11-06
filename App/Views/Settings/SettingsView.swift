import SwiftUI

struct SettingsView: View {
  /// False in the sidebar, where there's nothing to dismiss.
  var isPresentedAsSheet = true
  @Environment(AppSettings.self) private var settings
  @Environment(AppLock.self) private var lock
  @Environment(\.dismiss) private var dismiss
  @State private var passcodePurpose: PasscodeSheet.Purpose?
  @State private var cacheSize: Int64 = 0

  var body: some View {
    @Bindable var settings = settings
    @Bindable var lock = lock
    NavigationStack {
      Form {
        Section {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 52))], spacing: 14) {
            ForEach(AccentChoice.allCases.filter { $0 != .custom }) { choice in
              swatch(for: choice)
            }
          }
          .padding(.vertical, 6)
          ColorPicker("Custom Color", selection: $settings.customAccent, supportsOpacity: false)
        } header: {
          Text("Accent Color")
        } footer: {
          Text("Colors the app's buttons and icons. Very light or dark colors can be hard to read.")
        }

        Section {
          Toggle("Passcode", isOn: passcodeBinding)
          if lock.hasPasscode {
            Button("Change Passcode") { passcodePurpose = .change }
            Picker("Require Passcode", selection: $lock.lockDelay) {
              ForEach(AutoLockDelay.allCases) { delay in
                Text(delay.title).tag(delay)
              }
            }
            Toggle(lock.biometryName, isOn: biometricsBinding)
              .disabled(!lock.isBiometryAvailable)
          }
        } header: {
          Text("Security")
        } footer: {
          Text(securityFooter)
        }

        Section {
          Button(role: .destructive) {
            DescriptionCache.clear()
            IconCache.clear()
            cacheSize = Self.cacheSize()
          } label: {
            LabeledContent(
              "Clear Cache",
              value: cacheSize.formatted(.byteCount(style: .file)))
          }
          .disabled(cacheSize == 0)
        } header: {
          Text("Storage")
        } footer: {
          Text("Saved app icons and descriptions show at once and work offline. They download again the next time they're needed.")
        }
      }
      .onAppear { cacheSize = Self.cacheSize() }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if isPresentedAsSheet {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done", role: .confirm) { dismiss() }
          }
        }
      }
      .sheet(item: $passcodePurpose) { PasscodeSheet(purpose: $0).tint(settings.accent) }
    }
  }

  private static func cacheSize() -> Int64 {
    DescriptionCache.size() + IconCache.size()
  }

  private var securityFooter: String {
    if lock.hasPasscode && !lock.isBiometryAvailable {
      return "The app always asks for the passcode when it opens, and when it returns from the background after the time you choose. Face ID and Touch ID are unavailable because they aren't set up on this device."
    }
    return "The app always asks for the passcode when it opens, and when it returns from the background after the time you choose. A forgotten passcode can't be recovered: the only way back in is to erase the app's data."
  }

  private func swatch(for choice: AccentChoice) -> some View {
    let isSelected = settings.accentChoice == choice
    return Button {
      withAnimation(.snappy) { settings.accentChoice = choice }
    } label: {
      Circle()
        .fill(settings.color(for: choice))
        .frame(width: 44, height: 44)
        .overlay {
          if isSelected {
            Image(systemName: "checkmark")
              .font(.headline)
              .foregroundStyle(.white)
          }
        }
        .frame(minWidth: 44, minHeight: 44)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(choice.title)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  /// Shows the sheet instead of changing the value: the toggle follows once the flow succeeds.
  private var passcodeBinding: Binding<Bool> {
    Binding {
      lock.hasPasscode
    } set: { isOn in
      passcodePurpose = isOn ? .create : .remove
    }
  }

  private var biometricsBinding: Binding<Bool> {
    Binding {
      lock.biometricsEnabled
    } set: { isOn in
      if isOn {
        Task { _ = await lock.enableBiometrics() }
      } else {
        lock.biometricsEnabled = false
      }
    }
  }
}
