import Citadel
import CommonCrypto
import Crypto
import Foundation

/// Turns a stored private key into something Citadel can sign with.
///
/// webOS TVs hand out passphrase-protected PEM keys, while Citadel only reads the OpenSSH format,
/// so PKCS#1 and PKCS#8 RSA keys are decrypted here and rewritten as unencrypted OpenSSH keys.
enum SSHKeyLoader {
  static func authentication(username: String, key: String, passphrase: String?) throws
    -> SSHAuthenticationMethod
  {
    let pem = try openSSHPEM(from: key, passphrase: passphrase)
    let decryptionKey = passphrase.flatMap { $0.isEmpty ? nil : Data($0.utf8) }
    let isEncrypted = pem.isEncryptedOpenSSH
    if isEncrypted && decryptionKey == nil { throw DeviceError.passphraseRequired }
    do {
      switch try SSHKeyDetection.detectPrivateKeyType(from: pem) {
      case .rsa:
        let privateKey = try Insecure.RSA.PrivateKey(sshRsa: pem, decryptionKey: decryptionKey)
        return .rsa(username: username, privateKey: privateKey)
      case .ed25519:
        let privateKey = try Curve25519.Signing.PrivateKey(
          sshEd25519: pem, decryptionKey: decryptionKey)
        return .ed25519(username: username, privateKey: privateKey)
      default:
        throw DeviceError.unsupportedKey
      }
    } catch let error as DeviceError {
      throw error
    } catch {
      throw isEncrypted ? DeviceError.wrongPassphrase : DeviceError.unsupportedKey
    }
  }

  /// Checks that a key can be used, so a wrong passphrase is reported before connecting.
  static func validate(key: String, passphrase: String?) throws {
    _ = try authentication(username: "check", key: key, passphrase: passphrase)
  }

  static func openSSHPEM(from key: String, passphrase: String?) throws -> String {
    let block = try PEMBlock(key)
    switch block.label {
    case "OPENSSH PRIVATE KEY":
      return block.canonical
    case "RSA PRIVATE KEY":
      let der = try decryptTraditional(block, passphrase: passphrase)
      return try openSSHKey(pkcs1: der, encrypted: block.headers["Proc-Type"] != nil)
    case "PRIVATE KEY":
      return try openSSHKey(pkcs1: rsaKey(pkcs8: block.body), encrypted: false)
    case "ENCRYPTED PRIVATE KEY":
      guard let passphrase, !passphrase.isEmpty else { throw DeviceError.passphraseRequired }
      let der = try decryptPKCS8(block.body, passphrase: passphrase)
      // Wrong keys occasionally produce valid padding, which only the contents can reveal.
      guard let rsa = try? rsaKey(pkcs8: der) else { throw DeviceError.wrongPassphrase }
      return try openSSHKey(pkcs1: rsa, encrypted: true)
    default:
      throw DeviceError.unsupportedKey
    }
  }

  /// The `ssh-rsa AAAA…` line to put in `authorized_keys`. OpenSSH keys store the public part
  /// unencrypted, so this works without the passphrase.
  static func publicKeyLine(fromPrivateKey key: String, passphrase: String?) throws -> String {
    let pem = try openSSHPEM(from: key, passphrase: passphrase)
    let base64 = pem.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("-----") }.joined()
    guard let data = Data(base64Encoded: base64) else { throw DeviceError.unsupportedKey }
    var reader = data.dropFirst("openssh-key-v1\0".utf8.count)
    for _ in 0..<3 { _ = try reader.readSSHString() }  // Cipher, KDF and KDF options.
    reader = reader.dropFirst(4)  // Key count.
    let blob = try reader.readSSHString()
    var blobReader = blob
    let type = String(decoding: try blobReader.readSSHString(), as: UTF8.self)
    return "\(type) \(Data(blob).base64EncodedString())"
  }

  // MARK: Traditional OpenSSL encryption

  private static func decryptTraditional(_ block: PEMBlock, passphrase: String?) throws -> Data {
    guard let info = block.headers["DEK-Info"] else { return block.body }
    guard let passphrase, !passphrase.isEmpty else { throw DeviceError.passphraseRequired }
    let parts = info.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count == 2, let iv = Data(hex: parts[1]) else { throw DeviceError.unsupportedKey }
    let cipher = try BlockCipher(pemName: parts[0])
    let key = legacyKey(passphrase: Data(passphrase.utf8), salt: iv.prefix(8), count: cipher.keySize)
    guard let plain = cipher.decrypt(block.body, key: key, iv: iv) else {
      throw DeviceError.wrongPassphrase
    }
    return plain
  }

  /// OpenSSL's `EVP_BytesToKey` with MD5 and one iteration, which PEM encryption is defined with.
  private static func legacyKey(passphrase: Data, salt: Data, count: Int) -> Data {
    var key = Data()
    var previous = Data()
    while key.count < count {
      previous = Data(Insecure.MD5.hash(data: previous + passphrase + salt))
      key += previous
    }
    return key.prefix(count)
  }

  // MARK: PKCS#8

  private static func rsaKey(pkcs8 der: Data) throws -> Data {
    var outer = try DERReader.sequence(in: der)
    _ = try outer.element(tag: 0x02)
    _ = try outer.element(tag: 0x30)
    return try outer.element(tag: 0x04)
  }

  private static func decryptPKCS8(_ der: Data, passphrase: String) throws -> Data {
    var outer = try DERReader.sequence(in: der)
    var algorithm = try outer.sequence()
    guard try algorithm.objectIdentifier() == "2a864886f70d01050d" else {  // PBES2
      throw DeviceError.unsupportedKey
    }
    var parameters = try algorithm.sequence()
    var derivation = try parameters.sequence()
    guard try derivation.objectIdentifier() == "2a864886f70d01050c" else {  // PBKDF2
      throw DeviceError.unsupportedKey
    }
    var kdf = try derivation.sequence()
    let salt = try kdf.element(tag: 0x04)
    let iterations = try kdf.element(tag: 0x02).reduce(0) { $0 << 8 | Int($1) }
    var prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
    if kdf.hasNext, kdf.peekTag == 0x02 { _ = try kdf.element(tag: 0x02) }
    if kdf.hasNext {
      var prfSequence = try kdf.sequence()
      switch try prfSequence.objectIdentifier() {
      case "2a864886f70d0207": prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
      case "2a864886f70d0209": prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256)
      case "2a864886f70d020b": prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512)
      default: throw DeviceError.unsupportedKey
      }
    }
    var scheme = try parameters.sequence()
    let keySize: Int
    switch try scheme.objectIdentifier() {
    case "608648016503040102": keySize = 16  // aes128-cbc
    case "60864801650304012a": keySize = 32  // aes256-cbc
    default: throw DeviceError.unsupportedKey
    }
    let iv = try scheme.element(tag: 0x04)
    let body = try outer.element(tag: 0x04)

    var key = Data(count: keySize)
    let status = key.withUnsafeMutableBytes { keyBytes in
      salt.withUnsafeBytes { saltBytes in
        CCKeyDerivationPBKDF(
          CCPBKDFAlgorithm(kCCPBKDF2), passphrase, passphrase.utf8.count,
          saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count, prf, UInt32(iterations),
          keyBytes.bindMemory(to: UInt8.self).baseAddress, keySize)
      }
    }
    guard status == kCCSuccess else { throw DeviceError.unsupportedKey }
    guard let plain = BlockCipher.aes(keySize: keySize).decrypt(body, key: key, iv: iv) else {
      throw DeviceError.wrongPassphrase
    }
    return plain
  }

  // MARK: OpenSSH format

  static func openSSHKey(pkcs1 der: Data, encrypted: Bool) throws -> String {
    do {
      var sequence = try DERReader.sequence(in: der)
      _ = try sequence.element(tag: 0x02)
      let modulus = try sequence.element(tag: 0x02)
      let publicExponent = try sequence.element(tag: 0x02)
      let privateExponent = try sequence.element(tag: 0x02)
      let prime1 = try sequence.element(tag: 0x02)
      let prime2 = try sequence.element(tag: 0x02)
      _ = try sequence.element(tag: 0x02)
      _ = try sequence.element(tag: 0x02)
      let coefficient = try sequence.element(tag: 0x02)

      var publicBlob = Data()
      publicBlob.appendSSHString(Data("ssh-rsa".utf8))
      publicBlob.appendSSHString(publicExponent)
      publicBlob.appendSSHString(modulus)

      var privateBlob = Data()
      privateBlob.append(contentsOf: [0x53, 0x53, 0x48, 0x21, 0x53, 0x53, 0x48, 0x21])
      privateBlob.appendSSHString(Data("ssh-rsa".utf8))
      for value in [modulus, publicExponent, privateExponent, coefficient, prime1, prime2] {
        privateBlob.appendSSHString(value)
      }
      privateBlob.appendSSHString(Data())
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
    } catch {
      throw encrypted ? DeviceError.wrongPassphrase : DeviceError.unsupportedKey
    }
  }
}

private struct PEMBlock {
  var label: String
  var headers: [String: String] = [:]
  var body: Data
  var canonical: String

  init(_ text: String) throws {
    let lines = text.components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
    guard let start = lines.firstIndex(where: { $0.hasPrefix("-----BEGIN ") }),
      let end = lines.firstIndex(where: { $0.hasPrefix("-----END ") }), start < end
    else { throw DeviceError.unsupportedKey }
    label = String(lines[start].dropFirst(11).dropLast(5))
    var base64 = ""
    for line in lines[(start + 1)..<end] where !line.isEmpty {
      if let colon = line.firstIndex(of: ":") {
        headers[String(line[..<colon])] = String(line[line.index(after: colon)...])
          .trimmingCharacters(in: .whitespaces)
      } else {
        base64 += line
      }
    }
    guard let decoded = Data(base64Encoded: base64) else { throw DeviceError.unsupportedKey }
    body = decoded
    canonical = "\(lines[start])\n\(base64)\n\(lines[end])\n"
  }
}

private struct BlockCipher {
  var algorithm: CCAlgorithm
  var keySize: Int

  static func aes(keySize: Int) -> BlockCipher {
    BlockCipher(algorithm: CCAlgorithm(kCCAlgorithmAES), keySize: keySize)
  }

  private init(algorithm: CCAlgorithm, keySize: Int) {
    self.algorithm = algorithm
    self.keySize = keySize
  }

  init(pemName: String) throws {
    switch pemName.uppercased() {
    case "AES-128-CBC": self = .aes(keySize: 16)
    case "AES-192-CBC": self = .aes(keySize: 24)
    case "AES-256-CBC": self = .aes(keySize: 32)
    case "DES-EDE3-CBC": self.init(algorithm: CCAlgorithm(kCCAlgorithm3DES), keySize: 24)
    default: throw DeviceError.unsupportedKey
    }
  }

  /// Returns `nil` when the PKCS#7 padding is wrong, which usually means a wrong passphrase.
  func decrypt(_ data: Data, key: Data, iv: Data) -> Data? {
    var output = Data(count: data.count + kCCBlockSizeAES128)
    var written = 0
    let capacity = output.count
    let status = output.withUnsafeMutableBytes { outputBytes in
      data.withUnsafeBytes { dataBytes in
        key.withUnsafeBytes { keyBytes in
          iv.withUnsafeBytes { ivBytes in
            CCCrypt(
              CCOperation(kCCDecrypt), algorithm, CCOptions(kCCOptionPKCS7Padding),
              keyBytes.baseAddress, key.count, ivBytes.baseAddress, dataBytes.baseAddress,
              data.count, outputBytes.baseAddress, capacity, &written)
          }
        }
      }
    }
    guard status == kCCSuccess else { return nil }
    return output.prefix(written)
  }
}

/// Just enough of a DER reader for RSA private keys and their PKCS#8 wrappers.
private struct DERReader {
  private var bytes: [UInt8]
  private var offset = 0

  init(_ data: Data) {
    bytes = Array(data)
  }

  var hasNext: Bool { offset < bytes.count }
  var peekTag: UInt8? { hasNext ? bytes[offset] : nil }

  mutating func element(tag: UInt8) throws -> Data {
    guard offset + 2 <= bytes.count, bytes[offset] == tag else {
      throw DeviceError.invalidResponse
    }
    offset += 1
    var length = Int(bytes[offset])
    offset += 1
    if length & 0x80 != 0 {
      let count = length & 0x7f
      guard count <= 4, offset + count <= bytes.count else { throw DeviceError.invalidResponse }
      length = bytes[offset..<(offset + count)].reduce(0) { $0 << 8 | Int($1) }
      offset += count
    }
    guard offset + length <= bytes.count else { throw DeviceError.invalidResponse }
    defer { offset += length }
    return Data(bytes[offset..<(offset + length)])
  }

  static func sequence(in data: Data) throws -> DERReader {
    var reader = DERReader(data)
    return try reader.sequence()
  }

  mutating func sequence() throws -> DERReader {
    DERReader(try element(tag: 0x30))
  }

  mutating func objectIdentifier() throws -> String {
    try element(tag: 0x06).map { String(format: "%02x", $0) }.joined()
  }
}

extension Data {
  fileprivate mutating func readSSHString() throws -> Data {
    guard count >= 4 else { throw DeviceError.unsupportedKey }
    let length = prefix(4).reduce(0) { $0 << 8 | Int($1) }
    guard count >= 4 + length else { throw DeviceError.unsupportedKey }
    defer { self = dropFirst(4 + length) }
    return Data(dropFirst(4).prefix(length))
  }

  mutating func appendSSHString(_ value: Data) {
    var length = UInt32(value.count).bigEndian
    Swift.withUnsafeBytes(of: &length) { append(contentsOf: $0) }
    append(value)
  }

  fileprivate init?(hex: String) {
    guard hex.count.isMultiple(of: 2) else { return nil }
    var data = Data()
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
      data.append(byte)
      index = next
    }
    self = data
  }
}

extension String {
  /// Encrypted OpenSSH keys name their cipher in the blob; only `none` is unencrypted.
  fileprivate var isEncryptedOpenSSH: Bool {
    let base64 = split(whereSeparator: \.isNewline)
      .filter { !$0.hasPrefix("-----") }.joined()
    guard let data = Data(base64Encoded: base64) else { return false }
    let prefixLength = "openssh-key-v1\0".utf8.count
    guard data.count > prefixLength + 8 else { return false }
    let name = data.dropFirst(prefixLength + 4).prefix(4)
    return String(decoding: name, as: UTF8.self) != "none"
  }
}
