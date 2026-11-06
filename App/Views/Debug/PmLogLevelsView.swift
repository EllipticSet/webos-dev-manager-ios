import SwiftUI

struct PmLogLevelsView: View {
  struct Context: Identifiable, Hashable {
    var name: String
    var level: String
    var id: String { name }
  }

  /// Parses lines of `PmLogCtl show`, such as `PmLogCtl: Context 'name' = info`.
  static func parse(_ output: String) -> [Context] {
    output.split(whereSeparator: \.isNewline).compactMap { line in
      guard let match = line.wholeMatch(of: /PmLogCtl: Context '([^']+)' = (.+)/) else {
        return nil
      }
      return Context(name: String(match.1), level: String(match.2))
    }
  }

  static let levels = ["none"] + LogLevel.allCases.map(\.rawValue)

  var service: DeviceService

  @State private var contexts: LoadState<[Context]> = .loading
  @State private var searchText = ""
  @State private var failure: String?

  var body: some View {
    Group {
      switch contexts {
      case .loading:
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .failed(let message):
        ErrorStateView(message: message) { Task { await load() } }
      case .loaded(let items):
        List {
          Section {
            Picker("All Contexts", selection: allBinding) {
              Text("Choose…").tag("")
              ForEach(Self.levels, id: \.self) { Text($0).tag($0) }
            }
          }
          Section {
            ForEach(filtered(items)) { context in
              Picker(context.name, selection: binding(for: context)) {
                ForEach(Self.levels, id: \.self) { Text($0).tag($0) }
              }
            }
          }
        }
        .searchable(text: $searchText, prompt: "Search Contexts")
      }
    }
    .navigationTitle("Log Levels")
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .alert("Operation Failed", isPresented: isShowingFailure) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(failure ?? "")
    }
  }

  private var isShowingFailure: Binding<Bool> {
    Binding { failure != nil } set: { if !$0 { failure = nil } }
  }

  private var allBinding: Binding<String> {
    Binding {
      ""
    } set: { level in
      guard !level.isEmpty else { return }
      set(level: level, of: "*")
    }
  }

  private func binding(for context: Context) -> Binding<String> {
    Binding {
      context.level
    } set: { level in
      set(level: level, of: context.name)
    }
  }

  private func filtered(_ items: [Context]) -> [Context] {
    guard !searchText.isEmpty else { return items }
    return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
  }

  private func load() async {
    do {
      let output = try await service.session.execute("PmLogCtl show")
      let text = output.text.isEmpty ? String(decoding: output.stderr, as: UTF8.self) : output.text
      contexts = .loaded(Self.parse(text))
    } catch {
      contexts = .failed(DeviceError.message(for: error))
    }
  }

  private func set(level: String, of context: String) {
    Task {
      do {
        try await service.session.run("PmLogCtl set \(context.shellQuoted) \(level)")
        await load()
      } catch {
        failure = DeviceError.message(for: error)
      }
    }
  }
}
