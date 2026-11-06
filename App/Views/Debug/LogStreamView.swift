import SwiftUI

enum LogStreamKind {
  case syslog
  case dmesg

  var title: String {
    switch self {
    case .syslog: "Syslog"
    case .dmesg: "dmesg"
    }
  }

  var command: String {
    switch self {
    case .syslog: "tail -f -n 100 /var/log/messages"
    case .dmesg: "dmesg -w -x"
    }
  }

  var clearCommand: String {
    switch self {
    case .syslog: "echo > /var/log/messages"
    case .dmesg: "dmesg -c"
    }
  }

  func parse(_ line: String) -> LogEntry? {
    switch self {
    case .syslog: LogEntry.parsePmLog(line)
    case .dmesg: LogEntry.parseDmesg(line)
    }
  }
}

struct LogStreamView: View {
  var kind: LogStreamKind
  var service: DeviceService

  private static let maximumEntries = 2000

  @State private var entries: [LogEntry] = []
  /// Lines waiting for the next refresh. A busy TV sends far more than the list can redraw one by one.
  @State private var pendingEntries = PendingLogEntries()
  @State private var errorMessage: String?
  @State private var searchText = ""
  @State private var isPaused = false
  @State private var isConfirmingClear = false

  private var visibleEntries: [LogEntry] {
    guard !searchText.isEmpty else { return entries }
    return entries.filter {
      $0.message.localizedCaseInsensitiveContains(searchText)
        || ($0.context?.localizedCaseInsensitiveContains(searchText) ?? false)
        || ($0.process?.localizedCaseInsensitiveContains(searchText) ?? false)
    }
  }

  var body: some View {
    ScrollViewReader { proxy in
      List(visibleEntries) { entry in
        LogEntryRow(entry: entry)
          .id(entry.id)
      }
      .listStyle(.plain)
      .overlay {
        if let errorMessage, entries.isEmpty {
          ContentUnavailableView(
            "Log Unavailable", systemImage: "exclamationmark.triangle",
            description: Text(errorMessage))
        } else if entries.isEmpty {
          ProgressView("Waiting for messages…")
        }
      }
      .onChange(of: entries.last?.id) { _, last in
        if let last, !isPaused, searchText.isEmpty { proxy.scrollTo(last, anchor: .bottom) }
      }
    }
    .searchable(text: $searchText, prompt: "Filter")
    .navigationTitle(kind.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Toggle(isOn: $isPaused) {
          Label("Pause Scrolling", systemImage: "pause")
        }
        Button("Clear Log", systemImage: "trash") { isConfirmingClear = true }
      }
    }
    .confirmationDialog(
      "Clear the Log on the TV?", isPresented: $isConfirmingClear, titleVisibility: .visible
    ) {
      Button("Clear", role: .destructive) { clear() }
    }
    .task { await stream() }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(250))
        showPendingEntries()
      }
    }
  }

  private func stream() async {
    do {
      if kind == .syslog { await enableDeveloperLogs() }
      for try await line in service.session.lines(of: kind.command) {
        guard let entry = kind.parse(line) else { continue }
        pendingEntries.items.append(entry)
      }
    } catch is CancellationError {
    } catch {
      errorMessage = DeviceError.message(for: error)
    }
  }

  private func showPendingEntries() {
    guard !pendingEntries.items.isEmpty else { return }
    var updated = entries + pendingEntries.items
    pendingEntries.items = []
    if updated.count > Self.maximumEntries { updated.removeFirst(updated.count - Self.maximumEntries) }
    entries = updated
  }

  /// webOS only records application logs after being asked to, in a way that depends on its version.
  private func enableDeveloperLogs() async {
    guard let release = try? await service.details().osVersion,
      let version = PackageVersion(release)
    else { return }
    if version.major >= 4 {
      _ = try? await service.luna.call(
        "luna://com.webos.service.config/setConfigs",
        parameters: ["configs": ["system.collectDevLogs": true]], isPublic: false)
    } else if version.major == 3 {
      _ = try? await service.luna.call(
        "luna://com.webos.pmlogd/setdevlogstatus", parameters: ["recordDevLogs": true],
        isPublic: false)
    }
  }

  private func clear() {
    Task {
      do {
        try await service.session.run(kind.clearCommand)
        pendingEntries.items = []
        entries = []
      } catch {
        errorMessage = DeviceError.message(for: error)
      }
    }
  }
}

@MainActor
private final class PendingLogEntries {
  var items: [LogEntry] = []
}

private struct LogEntryRow: View {
  var entry: LogEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Text(entry.level.rawValue.uppercased())
          .fontWeight(.semibold)
          .foregroundStyle(entry.level.isProblem ? Color.red : Color.secondary)
        if let source = entry.process ?? entry.context {
          Text(source).lineLimit(1)
        }
        Spacer(minLength: 0)
        if let date = entry.date {
          Text(date.formatted(date: .omitted, time: .standard))
        } else if let monotonic = entry.monotonic {
          Text(monotonic.formatted(.number.precision(.fractionLength(3))))
        }
      }
      .font(.caption2.monospaced())
      .foregroundStyle(.secondary)
      Text(entry.message)
        .font(.caption.monospaced())
        .textSelection(.enabled)
    }
  }
}
