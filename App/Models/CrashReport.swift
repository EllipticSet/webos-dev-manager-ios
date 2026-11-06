import Foundation

struct CrashReport: Identifiable, Hashable, Sendable {
  var path: String
  var title: String
  var summary: String
  var saveName: String
  var modified: Date?

  var id: String { path }

  static let directories = ["/tmp/faultmanager/crash/", "/tmp/var/log/reports/librdx/"]

  /// Crash file names encode their path with control characters in place of `/`.
  init(file: RemoteFile) {
    path = file.path
    modified = file.modified

    let name = file.name
      .replacing(/[\x00-\x1f]/, with: "/")
      .replacing(/\.gz$/, with: "")
    saveName = name.replacingOccurrences(of: "/", with: "_")
    var processName = ""
    var processID = ""
    var summaryText = ""
    if let match = name.wholeMatch(of: /.*____(.+)\.(\d+)\..+/) {
      processName = String(match.1)
      processID = String(match.2)
      if let start = name.firstIndex(of: "/"), let end = name.range(of: "____", options: .backwards)
      {
        summaryText = String(name[start..<end.lowerBound])
        saveName = summaryText.replacingOccurrences(of: "/", with: "_")
      }
    }

    let appPrefix = ["/usr/palm/applications/", "/var/palm/jail/"]
      .lazy.compactMap { name.range(of: $0) }.first
    guard let appPrefix else {
      if !processName.isEmpty, !processID.isEmpty, !summaryText.isEmpty {
        title = "\(processName) (\(processID))"
        summary = summaryText
      } else {
        title = "Unknown crash"
        summary = name
      }
      return
    }

    let remainder = name[appPrefix.upperBound...]
    let appID = remainder.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
    if let lastSlash = remainder.lastIndex(of: "/"),
      let marker = remainder.range(of: "____", options: .backwards),
      lastSlash < marker.lowerBound
    {
      summaryText = String(remainder[remainder.index(after: lastSlash)..<marker.lowerBound])
    }
    title = processID.isEmpty ? appID : "\(appID) (\(processID))"
    summary = summaryText
  }
}
