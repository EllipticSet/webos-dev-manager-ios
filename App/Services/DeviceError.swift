import Citadel
import Foundation
import NIOCore
import NIOPosix
import Security

enum DeviceError: LocalizedError {
  case passphraseRequired
  case wrongPassphrase
  case unsupportedKey
  case missingCredentials
  case keyServerUnavailable
  case hostKeyChanged
  case commandFailed(command: String, status: Int, message: String)
  case lunaResponse(String)
  case lunaUnknownMethod(String)
  case lunaServiceNotFound(String)
  case notWebOS
  case invalidResponse
  case timedOut
  case insufficientSpace
  case installFailed(String)
  /// The TV closed the connection before reporting whether an install or uninstall worked.
  case resultNotReported(isUninstall: Bool)
  case repository(String)
  case keychain(OSStatus)

  var errorDescription: String? {
    switch self {
    case .passphraseRequired:
      String(localized: "Enter the key's passphrase.")
    case .wrongPassphrase:
      String(localized: "Incorrect passphrase. Check the one shown in the Developer Mode app on the TV.")
    case .unsupportedKey:
      String(localized: "This private key format isn't supported. Use an RSA or Ed25519 key.")
    case .missingCredentials:
      String(localized: "Sign-in credentials are missing. Edit the TV and enter them again.")
    case .keyServerUnavailable:
      String(localized: "Can't reach the Key Server. Turn it on in the Developer Mode app and try again.")
    case .hostKeyChanged:
      String(localized: "The TV's identity has changed since the last connection. If you reset the TV, use “Forget TV Identity” in its settings.")
    case .commandFailed(_, let status, let message):
      message.isEmpty ? String(localized: "The command failed on the TV (code \(status)).") : message
    case .lunaResponse(let text), .lunaUnknownMethod(let text), .lunaServiceNotFound(let text):
      text
    case .notWebOS:
      String(localized: "Couldn't find the luna-send command. Is this device really running webOS?")
    case .invalidResponse:
      String(localized: "The TV sent an invalid response.")
    case .timedOut:
      String(localized: "The TV isn't responding. Make sure it's on and on the same network.")
    case .insufficientSpace:
      String(localized: "There isn't enough space on the TV to install this app.")
    case .installFailed(let reason):
      String(localized: "The operation failed: \(reason)")
    case .resultNotReported(let isUninstall):
      isUninstall
        ? String(localized: "The connection closed before the TV reported whether the app was uninstalled.")
        : String(localized: "The connection closed before the TV reported whether the app was installed.")
    case .repository(let message):
      message
    case .keychain(let status):
      String(localized: "Couldn't save the credentials (error \(status)).")
    }
  }

  /// A user-readable message for any error thrown by the networking stack.
  static func message(for error: Error) -> String {
    switch error {
    case is AuthenticationFailed, SSHClientError.allAuthenticationOptionsFailed:
      return String(localized: "The TV rejected the sign-in. Check the user and credentials. With Developer Mode, also make sure the session is active and the key is up to date.")
    case CitadelError.channelCreationFailed, SSHClientError.channelCreationFailed:
      return DeviceError.timedOut.errorDescription ?? ""
    case let error as LocalizedError where error.errorDescription != nil:
      return error.errorDescription!
    case is IOError, is ChannelError:
      return String(localized: "Couldn't connect to the TV. Make sure it's on and on the same Wi-Fi network.")
    case is NIOConnectionError:
      return String(localized: "Can't reach the TV. Check the address and port, and that Developer Mode is on.")
    default:
      // Citadel's handshake errors are internal types with no readable description.
      return String(localized: "The TV closed the connection during sign-in. Make sure Developer Mode is on and try again.")
    }
  }
}
