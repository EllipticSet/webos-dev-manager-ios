import Observation
import SwiftUI

enum AccentChoice: String, CaseIterable, Identifiable {
  case lgRed, blue, indigo, purple, pink, orange, green, teal, custom

  var id: Self { self }

  var title: String {
    switch self {
    case .lgRed: "LG Red"
    case .blue: "Blue"
    case .indigo: "Indigo"
    case .purple: "Purple"
    case .pink: "Pink"
    case .orange: "Orange"
    case .green: "Green"
    case .teal: "Teal"
    case .custom: "Custom"
    }
  }
}

@MainActor
@Observable
final class AppSettings {
  var accentChoice: AccentChoice {
    didSet { UserDefaults.standard.set(accentChoice.rawValue, forKey: Self.choiceKey) }
  }
  var customAccentHex: String {
    didSet { UserDefaults.standard.set(customAccentHex, forKey: Self.customKey) }
  }

  private static let choiceKey = "accentChoice"
  private static let customKey = "customAccent"

  init() {
    let stored = UserDefaults.standard.string(forKey: Self.choiceKey)
    accentChoice = stored.flatMap(AccentChoice.init(rawValue:)) ?? .lgRed
    customAccentHex = UserDefaults.standard.string(forKey: Self.customKey) ?? "A50034"
  }

  var accent: Color { color(for: accentChoice) }

  func color(for choice: AccentChoice) -> Color {
    switch choice {
    case .lgRed: Color("AccentColor")
    case .blue: .blue
    case .indigo: .indigo
    case .purple: .purple
    case .pink: .pink
    case .orange: .orange
    case .green: .green
    case .teal: .teal
    case .custom: Color(hex: customAccentHex) ?? Color("AccentColor")
    }
  }

  /// The custom color, for a `ColorPicker`. Choosing one also selects it.
  var customAccent: Color {
    get { Color(hex: customAccentHex) ?? Color("AccentColor") }
    set {
      customAccentHex = newValue.hexString
      accentChoice = .custom
    }
  }
}

extension Color {
  init?(hex: String) {
    guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
    self.init(
      red: Double(value >> 16 & 0xFF) / 255,
      green: Double(value >> 8 & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255)
  }

  var hexString: String {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: nil)
    let clamp = { (value: CGFloat) in Int((min(max(value, 0), 1) * 255).rounded()) }
    return String(format: "%02X%02X%02X", clamp(red), clamp(green), clamp(blue))
  }
}
