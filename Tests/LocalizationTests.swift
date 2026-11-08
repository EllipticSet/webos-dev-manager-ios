import Foundation
import Testing

@testable import Dev_Manager

struct LocalizationTests {
  private static let appBundle = Bundle(for: DeviceStore.self)

  private static func strings(for language: String) throws -> [String: String] {
    let url = try #require(appBundle.url(
      forResource: "Localizable", withExtension: "strings", subdirectory: nil,
      localization: language))
    return try #require(NSDictionary(contentsOf: url) as? [String: String])
  }

  /// The placeholders in a format, ignoring their position, which a translation may reorder.
  private static func placeholders(in format: String) -> [String] {
    format.matches(of: /%(?:\d+\$)?(lld|ld|d|@|f)/).map { String($0.output.1) }.sorted()
  }

  @Test func italianIsBundled() throws {
    let italian = try Self.strings(for: "it")
    #expect(italian["Cancel"] == "Annulla")
    #expect(italian["Unknown crash"] == "Crash sconosciuto")
    #expect(italian["Storage.Available"] == "Disponibile")
  }

  /// A translation with other placeholders than its key would show the wrong values or crash.
  @Test func italianKeepsPlaceholders() throws {
    for (key, value) in try Self.strings(for: "it") {
      #expect(Self.placeholders(in: key) == Self.placeholders(in: value), "\(key)")
    }
  }

  /// Errors are built outside SwiftUI views, so they're translated only if they use the catalog.
  @Test func errorsAreTranslated() throws {
    let path = try #require(Self.appBundle.path(forResource: "it", ofType: "lproj"))
    let italian = try #require(Bundle(path: path))
    let message = italian.localizedString(
      forKey: "The TV sent an invalid response.", value: nil, table: nil)
    #expect(message == "La TV ha inviato una risposta non valida.")
  }
}
