import SwiftUI

struct CrashReportsView: View {
  var service: DeviceService

  @State private var reports: LoadState<[CrashReport]> = .loading
  @State private var reportToDelete: CrashReport?

  var body: some View {
    Group {
      switch reports {
      case .loading:
        ProgressView("Loading…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .failed(let message):
        ErrorStateView(message: message) { Task { await load() } }
      case .loaded(let items):
        List(items) { report in
          NavigationLink {
            CrashReportDetailView(report: report, service: service)
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(report.title).lineLimit(2)
              if !report.summary.isEmpty {
                Text(report.summary)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
              if let modified = report.modified {
                Text(modified.formatted(date: .abbreviated, time: .shortened))
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          }
          .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { reportToDelete = report }
              .tint(.red)
          }
        }
        .overlay {
          if items.isEmpty {
            ContentUnavailableView("No Crash Reports", systemImage: "checkmark.seal")
          }
        }
        .refreshable { await load() }
      }
    }
    .navigationTitle("Crash Reports")
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .confirmationDialog(
      "Delete This Crash Report?", isPresented: isConfirmingDelete, titleVisibility: .visible,
      presenting: reportToDelete
    ) { report in
      Button("Delete", role: .destructive) { delete(report) }
    }
  }

  private var isConfirmingDelete: Binding<Bool> {
    Binding { reportToDelete != nil } set: { if !$0 { reportToDelete = nil } }
  }

  private func load() async {
    do {
      var found: [CrashReport] = []
      // The directory depends on the webOS version, so a missing one isn't a failure.
      for directory in CrashReport.directories
      where try await service.session.execute("test -d \(directory.shellQuoted)").status == 0 {
        found = try await service.session.list(directory).map(CrashReport.init(file:))
        break
      }
      reports = .loaded(found.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) })
    } catch is CancellationError {
    } catch {
      reports = .failed(DeviceError.message(for: error))
    }
  }

  private func delete(_ report: CrashReport) {
    Task {
      do {
        try await service.session.remove(report.path, recursive: false)
        await load()
      } catch {
        reports = .failed(DeviceError.message(for: error))
      }
    }
  }
}

private struct CrashReportDetailView: View {
  var report: CrashReport
  var service: DeviceService

  @State private var content: LoadState<String> = .loading

  var body: some View {
    Group {
      switch content {
      case .loading:
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .failed(let message):
        ErrorStateView(message: message) { Task { await load() } }
      case .loaded(let text):
        ScrollView([.vertical, .horizontal]) {
          Text(text)
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
          ToolbarItem(placement: .primaryAction) {
            ShareLink(item: text, subject: Text(report.saveName))
          }
        }
      }
    }
    .navigationTitle(report.title)
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
  }

  private func load() async {
    do {
      let data = try await service.session.readGzip(report.path)
      content = .loaded(
        String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    } catch is CancellationError {
    } catch {
      content = .failed(DeviceError.message(for: error))
    }
  }
}
