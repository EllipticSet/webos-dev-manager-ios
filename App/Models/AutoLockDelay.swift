import Foundation

/// How long the app can stay in the background before it asks for the passcode again.
/// The raw value is the number of seconds, and it's what gets saved.
enum AutoLockDelay: Int, CaseIterable, Identifiable {
  case immediately = 0
  case oneMinute = 60
  case fiveMinutes = 300
  case fifteenMinutes = 900
  case oneHour = 3600

  var id: Self { self }

  var seconds: Double { Double(rawValue) }

  var title: String {
    switch self {
    case .immediately: String(localized: "Immediately")
    case .oneMinute: String(localized: "After 1 Minute")
    case .fiveMinutes: String(localized: "After 5 Minutes")
    case .fifteenMinutes: String(localized: "After 15 Minutes")
    case .oneHour: String(localized: "After 1 Hour")
    }
  }
}
