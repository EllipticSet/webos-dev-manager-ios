import SwiftUI
import UniformTypeIdentifiers

struct LunaMonitorView: View {
  var service: DeviceService

  @State private var builder = LunaCallBuilder()
  @State private var captureTask: Task<Void, Never>?
  @State private var captureID: UUID?
  @State private var errorMessage: String?
  @State private var searchText = ""
  @State private var isImporting = false
  @State private var selectedCall: LunaCall?

  private var isCapturing: Bool { captureTask != nil }

  private var visibleCalls: [LunaCall] {
    guard !searchText.isEmpty else { return builder.calls }
    return builder.calls.filter {
      $0.sender.localizedCaseInsensitiveContains(searchText)
        || $0.destination.localizedCaseInsensitiveContains(searchText)
        || $0.method.localizedCaseInsensitiveContains(searchText)
    }
  }

  var body: some View {
    List(visibleCalls) { call in
      Button {
        selectedCall = call
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text("\(call.destination)/\(call.method)")
            .font(.caption.monospaced())
            .foregroundStyle(.primary)
            .lineLimit(2)
          Text(call.sender)
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
    .listStyle(.plain)
    .overlay {
      if let errorMessage, builder.calls.isEmpty {
        ContentUnavailableView(
          "Monitor Unavailable", systemImage: "exclamationmark.triangle",
          description: Text(errorMessage))
      } else if builder.calls.isEmpty {
        ContentUnavailableView(
          isCapturing ? String(localized: "Waiting for calls…") : String(localized: "No Capture"),
          systemImage: "point.3.connected.trianglepath.dotted",
          description: Text("Start a capture or open a .jsonl file recorded with ls-monitor -j."))
      }
    }
    .searchable(text: $searchText, prompt: "Filter")
    .navigationTitle("ls-monitor")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Button("Open Capture", systemImage: "folder") { isImporting = true }
        if isCapturing {
          Button("Stop", systemImage: "stop.fill") { stop() }
        } else {
          Button("Start Capture", systemImage: "record.circle") { start() }
        }
      }
    }
    .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item]) { result in
      open(result)
    }
    .sheet(item: $selectedCall) { call in
      NavigationStack {
        LunaCallDetailView(call: call)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done", role: .confirm) { selectedCall = nil }
            }
          }
      }
    }
    .onDisappear { stop() }
  }

  private func start() {
    builder = LunaCallBuilder()
    errorMessage = nil
    let id = UUID()
    captureID = id
    captureTask = Task {
      do {
        for try await line in service.session.lines(of: "ls-monitor -j") {
          builder.add(line: line)
        }
      } catch is CancellationError {
      } catch {
        errorMessage = DeviceError.message(for: error)
      }
      // A capture that was stopped can end after the next one has started.
      if captureID == id { captureTask = nil }
    }
  }

  private func stop() {
    captureTask?.cancel()
    captureTask = nil
    captureID = nil
  }

  private func open(_ result: Result<URL, Error>) {
    guard case .success(let url) = result else { return }
    stop()
    let didAccess = url.startAccessingSecurityScopedResource()
    defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
      errorMessage = String(localized: "Couldn't read the file.")
      return
    }
    var imported = LunaCallBuilder()
    text.enumerateLines { line, _ in imported.add(line: line) }
    builder = imported
  }
}

private struct LunaCallDetailView: View {
  var call: LunaCall

  var body: some View {
    List {
      Section("Call") {
        DetailRow(title: "Sender", value: call.sender)
        DetailRow(title: "Destination", value: call.destination)
        DetailRow(title: "Method", value: call.method)
      }
      Section("Messages") {
        ForEach(call.messages) { message in
          VStack(alignment: .leading, spacing: 4) {
            Text(message.type)
              .font(.caption.bold())
            Text(message.payload)
              .font(.caption.monospaced())
              .textSelection(.enabled)
          }
        }
      }
    }
    .navigationTitle(call.method)
    .navigationBarTitleDisplayMode(.inline)
  }
}
