import Foundation

/// A root setting of Homebrew Channel, which it keeps as a flag file on the TV. Changes apply when
/// the TV restarts.
enum HomebrewSetting: String, CaseIterable, Identifiable {
  case telnet
  case sshServer
  case blockSystemUpdates
  case failsafeMode

  var id: Self { self }

  var title: String {
    switch self {
    case .telnet: "Telnet"
    case .sshServer: "SSH Server"
    case .blockSystemUpdates: "Block System Updates"
    case .failsafeMode: "Failsafe Mode"
    }
  }

  var details: String? {
    switch self {
    case .telnet, .sshServer: nil
    case .blockSystemUpdates: "Keeps LG firmware updates, which can remove root, from installing."
    case .failsafeMode:
      "Disables all early system modifications and leaves recovery telnet running. Turns on by itself if the TV restarts or crashes during early startup."
    }
  }

  /// The name `setConfiguration` and `getConfiguration` use.
  var key: String {
    switch self {
    case .telnet: "telnetDisabled"
    case .sshServer: "sshdEnabled"
    case .blockSystemUpdates: "blockUpdates"
    case .failsafeMode: "failsafe"
    }
  }

  /// The flag's value for the setting being on: Homebrew Channel stores Telnet as disabled.
  func flag(isOn: Bool) -> Bool {
    self == .telnet ? !isOn : isOn
  }
}

extension HomebrewConfiguration {
  func isOn(_ setting: HomebrewSetting) -> Bool? {
    switch setting {
    case .telnet: telnetDisabled.map(!)
    case .sshServer: sshdEnabled
    case .blockSystemUpdates: blockUpdates
    case .failsafeMode: failsafe
    }
  }
}
