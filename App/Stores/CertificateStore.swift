import Foundation
import Observation

@MainActor
@Observable
final class CertificateStore {
  private(set) var certificates: [SSHCertificate] = []

  private static let defaultsKey = "certificates"

  init() {
    if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
      let saved = try? JSONDecoder().decode([SSHCertificate].self, from: data)
    {
      certificates = saved
    }
  }

  func add(name: String, typeName: String, privateKey: String, passphrase: String?) throws {
    let publicKey = try SSHKeyLoader.publicKeyLine(fromPrivateKey: privateKey, passphrase: passphrase)
    try SSHKeyLoader.validate(key: privateKey, passphrase: passphrase)
    let certificate = SSHCertificate(name: name, typeName: typeName, publicKey: publicKey)
    try KeychainStore.save(
      DeviceSecrets(privateKey: privateKey, passphrase: passphrase), for: certificate.id)
    certificates.append(certificate)
    persist()
  }

  func rename(_ id: UUID, to name: String) {
    guard let index = certificates.firstIndex(where: { $0.id == id }) else { return }
    certificates[index].name = name
    persist()
  }

  func markSent(_ id: UUID, to deviceID: UUID) {
    guard let index = certificates.firstIndex(where: { $0.id == id }) else { return }
    certificates[index].sentToDeviceIDs.insert(deviceID)
    persist()
  }

  func remove(_ certificate: SSHCertificate) {
    certificates.removeAll { $0.id == certificate.id }
    KeychainStore.remove(for: certificate.id)
    persist()
  }

  func removeAll() {
    for certificate in certificates { KeychainStore.remove(for: certificate.id) }
    certificates = []
    persist()
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(certificates) else { return }
    UserDefaults.standard.set(data, forKey: Self.defaultsKey)
  }
}
