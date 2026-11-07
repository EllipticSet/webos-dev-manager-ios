import SwiftUI

extension View {
  /// Adds the top-left menu. On iPhone Duo's outer display in landscape, the vertical bar only has
  /// room for the overflow menu, so the menu's screens go straight into it rather than into a
  /// submenu.
  func appMenu(isAlwaysShown: Bool = false) -> some View {
    modifier(AppMenuModifier(isAlwaysShown: isAlwaysShown))
  }
}

/// The top-left menu shown on every tab in a compact width. In a regular width its screens are in
/// the sidebar instead, unless `isAlwaysShown` is set because there's no sidebar.
private struct AppMenuModifier: ViewModifier {
  var isAlwaysShown: Bool
  @Environment(AppNavigator.self) private var navigator
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @State private var hasHinge = false

  private var isShown: Bool { isAlwaysShown || horizontalSizeClass != .regular }
  private var usesOverflowMenu: Bool { hasHinge && verticalSizeClass == .compact }

  // Only the toolbar's items change with the layout, never the branch, so the content keeps its
  // state when the device rotates, opens or closes.
  func body(content: Content) -> some View {
    if #available(iOS 27.1, *) {
      content
        .toolbar {
          if isShown && !usesOverflowMenu { menu }
        }
        .toolbar {
          if isShown && usesOverflowMenu { ToolbarOverflowMenu { items } }
        }
        .onHingeChange { _, context in hasHinge = context.hinge != nil }
    } else {
      content.toolbar {
        if isShown { menu }
      }
    }
  }

  private var menu: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      Menu("Menu", systemImage: "line.3.horizontal") { items }
    }
  }

  @ViewBuilder
  private var items: some View {
    Button("Manage TVs", systemImage: "tv") { navigator.sheet = .manageTVs }
    Button("Certificates", systemImage: "key") { navigator.sheet = .certificates }
    Button("Settings", systemImage: "gearshape") { navigator.sheet = .settings }
    Button("About", systemImage: "info.circle") { navigator.sheet = .about }
  }
}
