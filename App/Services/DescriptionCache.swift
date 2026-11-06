import Crypto
import Foundation

/// Saved copies of app descriptions, in the Caches directory, so they open at once and work offline.
enum DescriptionCache {
  private static var directory: URL {
    URL.cachesDirectory.appending(path: "AppDescriptions", directoryHint: .isDirectory)
  }

  static func read(for url: URL) -> String? {
    try? String(contentsOf: file(for: url), encoding: .utf8)
  }

  /// A cache that can't be written only costs a download next time, so failures are ignored.
  static func write(_ html: String, for url: URL) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? Data(html.utf8).write(to: file(for: url), options: .atomic)
  }

  static func size() -> Int64 {
    let files = (try? FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
    return files.reduce(0) { total, file in
      total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
  }

  static func clear() {
    try? FileManager.default.removeItem(at: directory)
  }

  private static func file(for url: URL) -> URL {
    let name = SHA256.hash(data: Data(url.absoluteString.utf8))
      .map { String(format: "%02x", $0) }.joined()
    return directory.appending(path: name + ".html")
  }
}
