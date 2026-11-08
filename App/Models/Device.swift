import Foundation

struct Device: Identifiable, Codable, Hashable, Sendable {
  var id = UUID()
  var name: String
  var host: String
  var port: Int = 9922
  var username: String = "prisoner"
  var authentication: DeviceAuthentication = .devModeKey
  var notes: String = ""
  /// The saved certificate used when `authentication` is `.certificate`.
  var certificateID: UUID?

  var isDevMode: Bool { username == "prisoner" }
  var isRoot: Bool { username == "root" }
}

enum DeviceAuthentication: String, Codable, CaseIterable, Identifiable, Sendable {
  case devModeKey
  case importedKey
  case password
  case certificate

  var id: Self { self }

  var title: String {
    switch self {
    case .devModeKey: String(localized: "Developer Mode Key")
    case .importedKey: String(localized: "Private Key")
    case .password: String(localized: "Password")
    case .certificate: String(localized: "Saved Certificate")
    }
  }
}

/// Credentials for a device, kept in the Keychain and never in UserDefaults.
struct DeviceSecrets: Codable, Hashable, Sendable {
  var privateKey: String?
  var passphrase: String?
  var password: String?
}

enum DeviceSetupMode: String, CaseIterable, Identifiable {
  case developerMode
  case rooted
  case advanced

  var id: Self { self }

  var title: String {
    switch self {
    case .developerMode: String(localized: "Developer Mode")
    case .rooted: String(localized: "Rooted TV")
    case .advanced: String(localized: "Manual Setup")
    }
  }

  var summary: String {
    switch self {
    case .developerMode: String(localized: "Uses the Developer Mode app on the TV. No command line needed.")
    case .rooted: String(localized: "Sign in as root with the password or key you set up.")
    case .advanced: String(localized: "Choose the port, user, and sign-in method.")
    }
  }

  var systemImage: String {
    switch self {
    case .developerMode: "hammer.fill"
    case .rooted: "lock.open.fill"
    case .advanced: "slider.horizontal.3"
    }
  }

  func makeDevice() -> Device {
    switch self {
    case .developerMode:
      Device(name: "", host: "")
    case .rooted:
      Device(name: "", host: "", port: 22, username: "root", authentication: .password)
    case .advanced:
      Device(name: "", host: "", port: 22, username: "root", authentication: .importedKey)
    }
  }
}
