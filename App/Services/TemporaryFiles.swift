import Foundation

/// Copies of TV files kept for a preview or an export, each in its own folder to preserve its name.
enum TemporaryFiles {
  private static var directory: URL {
    FileManager.default.temporaryDirectory.appending(path: "RemoteFiles", directoryHint: .isDirectory)
  }

  static func makeURL(named name: String) throws -> URL {
    let folder = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appending(path: name, directoryHint: .notDirectory)
  }

  static func remove(_ file: URL) {
    try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
  }

  static func removeAll() {
    try? FileManager.default.removeItem(at: directory)
  }
}
