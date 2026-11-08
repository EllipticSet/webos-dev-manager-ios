import SwiftUI

extension EdgeInsets {
  /// While iPhone Duo is partially folded, insets that keep a centered panel off the fold: on the
  /// trailing half when it's held like a book, and on the top half, the one that stands up, when it
  /// stands like a laptop. Zero otherwise.
  static func offFold(in proxy: GeometryProxy) -> EdgeInsets {
    guard #available(iOS 27.1, *),
      let fold = proxy.reservedRegions(kind: .division).first(where: \.isActive)
    else { return EdgeInsets() }
    if fold.frame.height > fold.frame.width {
      return EdgeInsets(top: 0, leading: fold.frame.maxX + fold.margins.trailing, bottom: 0, trailing: 0)
    } else {
      let bottom = proxy.size.height - fold.frame.minY + fold.margins.top
      return EdgeInsets(top: 0, leading: 0, bottom: bottom, trailing: 0)
    }
  }
}

extension EnvironmentValues {
  /// Whether iPhone Duo is partially folded, where system alerts can't be moved to the side of the
  /// fold the app wants them on.
  @Entry var isPartiallyFolded = false
}

extension View {
  /// Tells the views inside, including those in sheets, whether iPhone Duo is partially folded.
  func readsFold() -> some View {
    modifier(FoldReader())
  }
}

private struct FoldReader: ViewModifier {
  @State private var isPartiallyFolded = false

  func body(content: Content) -> some View {
    content
      .environment(\.isPartiallyFolded, isPartiallyFolded)
      .background {
        GeometryReader { proxy in
          Color.clear
            .onChange(of: EdgeInsets.offFold(in: proxy), initial: true) { _, insets in
              isPartiallyFolded = insets != EdgeInsets()
            }
        }
        .ignoresSafeArea()
      }
  }
}
