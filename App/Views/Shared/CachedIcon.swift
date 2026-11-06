import SwiftUI

/// An app icon that shows the cached copy at once, then replaces it if `load` returns a newer one.
struct CachedIcon: View {
  /// The icon's `IconCache` key, or nil when the app has no icon.
  var key: String?
  var size: CGFloat
  var load: @Sendable () async throws -> Data

  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
      } else {
        Image(systemName: "app.dashed")
          .font(.title)
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: size, height: size)
    .clipShape(.rect(cornerRadius: size * 0.22))
    .accessibilityHidden(true)
    .task(id: key) {
      guard let key else {
        image = nil
        return
      }
      image = IconCache.image(for: key)
      guard IconCache.needsRefresh(key), let data = try? await load(),
        let loaded = IconCache.store(data, for: key)
      else { return }
      image = loaded
    }
  }
}
