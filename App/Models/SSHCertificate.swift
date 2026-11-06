import Crypto
import Foundation

/// A saved SSH key pair. The private key lives in the Keychain; this holds only public details.
struct SSHCertificate: Identifiable, Codable, Hashable, Sendable {
  var id = UUID()
  var name: String
  var typeName: String
  var publicKey: String
  var created = Date()
  /// The TVs this key was sent to, by the time it was sent.
  var sentToDeviceIDs: Set<UUID> = []

  /// The same `SHA256:…` form `ssh-keygen -l` prints.
  var fingerprint: String {
    let parts = publicKey.split(separator: " ")
    guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else { return "" }
    let digest = Data(SHA256.hash(data: blob)).base64EncodedString()
    return "SHA256:" + digest.replacingOccurrences(of: "=", with: "")
  }

  /// A command that adds the key to the remote user's `authorized_keys`, once.
  var installCommand: String {
    let key = publicKey.shellQuoted
    return """
      mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh" && touch "$HOME/.ssh/authorized_keys" \
      && chmod 600 "$HOME/.ssh/authorized_keys" \
      && { grep -qxF \(key) "$HOME/.ssh/authorized_keys" \
      || echo \(key) >> "$HOME/.ssh/authorized_keys"; }
      """
  }
}

enum CertificateKind: String, CaseIterable, Identifiable, Sendable {
  case rsa2048, rsa4096, ed25519

  var id: Self { self }

  var title: String {
    switch self {
    case .rsa2048: "RSA 2048"
    case .rsa4096: "RSA 4096"
    case .ed25519: "Ed25519"
    }
  }
}
