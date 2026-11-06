import SwiftUI

enum LoadState<Value> {
  case loading
  case loaded(Value)
  case failed(String)

  var value: Value? {
    if case .loaded(let value) = self { return value }
    return nil
  }
}

struct ErrorStateView: View {
  var message: String
  var retry: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label("Couldn't Load", systemImage: "exclamationmark.triangle")
    } description: {
      Text(message)
    } actions: {
      Button("Try Again", systemImage: "arrow.clockwise", action: retry)
    }
  }
}

/// A plain value row, with the value selectable so it can be copied.
struct DetailRow: View {
  var title: LocalizedStringKey
  var value: String

  var body: some View {
    LabeledContent(title) {
      Text(value)
        .textSelection(.enabled)
        .multilineTextAlignment(.trailing)
    }
  }
}
