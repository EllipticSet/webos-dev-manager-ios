import Foundation
import Observation

@MainActor
@Observable
final class DeviceStore {
  private(set) var devices: [Device] = []
  var selectedID: UUID? {
    didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: Self.selectedKey) }
  }

  private var sessions: [UUID: DeviceSession] = [:]

  private static let devicesKey = "devices"
  private static let selectedKey = "selectedDevice"

  init() {
    if let data = UserDefaults.standard.data(forKey: Self.devicesKey),
      let saved = try? JSONDecoder().decode([Device].self, from: data)
    {
      devices = saved
    }
    let savedID = UserDefaults.standard.string(forKey: Self.selectedKey).flatMap(UUID.init)
    selectedID = devices.contains { $0.id == savedID } ? savedID : devices.first?.id
  }

  var selected: Device? {
    devices.first { $0.id == selectedID }
  }

  /// A service for the device, sharing its connection across the app.
  func service(for device: Device) -> DeviceService {
    if let session = sessions[device.id], session.device == device {
      return DeviceService(session: session)
    }
    let session = DeviceSession(device: device, secrets: KeychainStore.secrets(for: device.id))
    sessions[device.id] = session
    return DeviceService(session: session)
  }

  func secrets(for device: Device) -> DeviceSecrets {
    KeychainStore.secrets(for: device.id)
  }

  func save(_ device: Device, secrets: DeviceSecrets) throws {
    try KeychainStore.save(secrets, for: device.id)
    closeSession(for: device.id)
    if let index = devices.firstIndex(where: { $0.id == device.id }) {
      devices[index] = device
    } else {
      devices.append(device)
    }
    persist()
    if selected == nil { selectedID = device.id }
  }

  func remove(_ device: Device) {
    closeSession(for: device.id)
    devices.removeAll { $0.id == device.id }
    KeychainStore.remove(for: device.id)
    TrustOnFirstUseValidator.forget(for: device.id)
    persist()
    if selectedID == device.id { selectedID = devices.first?.id }
  }

  func removeAll() {
    for device in devices { remove(device) }
  }

  func forgetHostKey(of device: Device) {
    TrustOnFirstUseValidator.forget(for: device.id)
    closeSession(for: device.id)
  }

  private func closeSession(for id: UUID) {
    guard let session = sessions.removeValue(forKey: id) else { return }
    Task { await session.disconnect() }
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(devices) else { return }
    UserDefaults.standard.set(data, forKey: Self.devicesKey)
  }
}
