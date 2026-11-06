import SwiftUI

/// The top-left menu shown on every tab in a compact width. In a regular width its screens are in
/// the sidebar instead, unless `isAlwaysShown` is set because there's no sidebar.
struct AppMenu: ToolbarContent {
  var isAlwaysShown = false
  @Environment(AppNavigator.self) private var navigator
  @Environment(\.horizontalSizeClass) private var sizeClass

  var body: some ToolbarContent {
    if isAlwaysShown || sizeClass != .regular {
      menu
    }
  }

  private var menu: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      Menu("Menu", systemImage: "line.3.horizontal") {
        Button("Manage TVs", systemImage: "tv") { navigator.sheet = .manageTVs }
        Button("Certificates", systemImage: "key") { navigator.sheet = .certificates }
        Button("Settings", systemImage: "gearshape") { navigator.sheet = .settings }
        Button("About", systemImage: "info.circle") { navigator.sheet = .about }
      }
    }
  }
}
