import Crypto
import Foundation
import Synchronization
import UIKit

/// App icons from TVs and repositories, kept in memory and in the Caches directory so lists show
/// them at once and offline. Each one is checked for changes once per launch.
enum IconCache {
  private static let memory = NSCache<NSString, UIImage>()
  private static let refreshed = Mutex<Set<String>>([])

  private static var directory: URL {
    URL.cachesDirectory.appending(path: "AppIcons", directoryHint: .isDirectory)
  }

  /// An installed app's icon, which can differ from TV to TV for the same path.
  static func key(device: Device.ID, path: String) -> String {
    "tv:\(device.uuidString):\(path)"
  }

  static func key(url: URL) -> String {
    url.absoluteString
  }

  static func image(for key: String) -> UIImage? {
    if let image = memory.object(forKey: key as NSString) { return image }
    guard let data = try? Data(contentsOf: file(for: key)), let image = UIImage(data: data) else {
      return nil
    }
    memory.setObject(image, forKey: key as NSString)
    return image
  }

  static func needsRefresh(_ key: String) -> Bool {
    !refreshed.withLock { $0.contains(key) }
  }

  /// Saves a downloaded icon, unless the data isn't an image. A cache that can't be written only
  /// costs a download next time, so write failures are ignored.
  @discardableResult
  static func store(_ data: Data, for key: String) -> UIImage? {
    guard let image = UIImage(data: data) else { return nil }
    refreshed.withLock { _ = $0.insert(key) }
    memory.setObject(image, forKey: key as NSString)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? data.write(to: file(for: key), options: .atomic)
    return image
  }

  static func size() -> Int64 {
    let files = (try? FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
    return files.reduce(0) { total, file in
      total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
  }

  static func clear() {
    memory.removeAllObjects()
    refreshed.withLock { $0.removeAll() }
    try? FileManager.default.removeItem(at: directory)
  }

  private static func file(for key: String) -> URL {
    let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    return directory.appending(path: name)
  }
}
