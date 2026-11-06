import Foundation
import Security

/// Stores each device's credentials as one Keychain item, only on this device.
enum KeychainStore {
  private static let service = "DeviceSecrets"

  static func secrets(for id: UUID) -> DeviceSecrets {
    var query = baseQuery(for: id)
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data,
      let secrets = try? JSONDecoder().decode(DeviceSecrets.self, from: data)
    else { return DeviceSecrets() }
    return secrets
  }

  static func save(_ secrets: DeviceSecrets, for id: UUID) throws {
    let data = try JSONEncoder().encode(secrets)
    // Updating in place means a failure can't lose the credentials already saved.
    let changes: [CFString: Any] = [
      kSecValueData: data,
      kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    var status = SecItemUpdate(baseQuery(for: id) as CFDictionary, changes as CFDictionary)
    if status == errSecItemNotFound {
      let attributes = baseQuery(for: id).merging(changes) { $1 }
      status = SecItemAdd(attributes as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw DeviceError.keychain(status) }
  }

  static func remove(for id: UUID) {
    SecItemDelete(baseQuery(for: id) as CFDictionary)
  }

  static func removeAll() {
    let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service]
    SecItemDelete(query as CFDictionary)
  }

  /// The passcode's salted hash, as a fixed item separate from any device.
  static var passcodeRecordID: UUID { UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")! }

  private static func baseQuery(for id: UUID) -> [CFString: Any] {
    [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: id.uuidString,
    ]
  }
}
