import Crypto
import Foundation
import Security

/// Creates new key pairs as unencrypted OpenSSH private keys, ready for Citadel and the Keychain.
enum SSHKeyGenerator {
  static func generate(_ kind: CertificateKind, comment: String) throws -> String {
    switch kind {
    case .rsa2048: try rsa(bits: 2048)
    case .rsa4096: try rsa(bits: 4096)
    case .ed25519: ed25519(comment: comment)
    }
  }

  private static func rsa(bits: Int) throws -> String {
    let attributes: [CFString: Any] = [
      kSecAttrKeyType: kSecAttrKeyTypeRSA,
      kSecAttrKeySizeInBits: bits,
    ]
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
      let der = SecKeyCopyExternalRepresentation(key, &error) as Data?
    else { throw DeviceError.unsupportedKey }
    return try SSHKeyLoader.openSSHKey(pkcs1: der, encrypted: false)
  }

  private static func ed25519(comment: String) -> String {
    let key = Curve25519.Signing.PrivateKey()
    let publicKey = key.publicKey.rawRepresentation
    let type = Data("ssh-ed25519".utf8)

    var publicBlob = Data()
    publicBlob.appendSSHString(type)
    publicBlob.appendSSHString(publicKey)

    var check = UInt32.random(in: .min ... .max).bigEndian
    var privateBlob = withUnsafeBytes(of: &check) { Data($0) + Data($0) }
    privateBlob.appendSSHString(type)
    privateBlob.appendSSHString(publicKey)
    privateBlob.appendSSHString(key.rawRepresentation + publicKey)
    privateBlob.appendSSHString(Data(comment.utf8))
    var padding: UInt8 = 1
    while privateBlob.count % 8 != 0 {
      privateBlob.append(padding)
      padding += 1
    }

    var blob = Data("openssh-key-v1\0".utf8)
    blob.appendSSHString(Data("none".utf8))
    blob.appendSSHString(Data("none".utf8))
    blob.appendSSHString(Data())
    blob.append(contentsOf: [0, 0, 0, 1])
    blob.appendSSHString(publicBlob)
    blob.appendSSHString(privateBlob)
    let encoded = blob.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
    return "-----BEGIN OPENSSH PRIVATE KEY-----\n\(encoded)\n-----END OPENSSH PRIVATE KEY-----\n"
  }
}
