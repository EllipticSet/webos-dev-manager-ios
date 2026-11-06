import Observation

enum AppSheet: String, Identifiable {
  case manageTVs, certificates, settings, about

  var id: Self { self }
}

/// The screens opened from the top-left menu. They're presented above the tabs, which are rebuilt
/// when the selected TV changes, so that choosing a TV doesn't close the screen it was chosen on.
@MainActor
@Observable
final class AppNavigator {
  var sheet: AppSheet?
}
