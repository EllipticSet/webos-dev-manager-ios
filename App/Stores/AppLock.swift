import CommonCrypto
import Foundation
import LocalAuthentication
import Observation
import Security

/// A salted PBKDF2 hash; the passcode itself is never stored.
struct PasscodeRecord: Codable, Equatable {
  var salt: Data
  var hash: Data
  var rounds: UInt32

  static let defaultRounds: UInt32 = 200_000
  static let length = 6

  init(passcode: String, rounds: UInt32 = defaultRounds) {
    var salt = Data(count: 16)
    _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
    self.salt = salt
    self.rounds = rounds
    hash = Self.derive(passcode: passcode, salt: salt, rounds: rounds)
  }

  func matches(_ passcode: String) -> Bool {
    Self.derive(passcode: passcode, salt: salt, rounds: rounds) == hash
  }

  private static func derive(passcode: String, salt: Data, rounds: UInt32) -> Data {
    var output = Data(count: 32)
    _ = output.withUnsafeMutableBytes { outputBytes in
      salt.withUnsafeBytes { saltBytes in
        CCKeyDerivationPBKDF(
          CCPBKDFAlgorithm(kCCPBKDF2), passcode, passcode.utf8.count,
          saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
          outputBytes.bindMemory(to: UInt8.self).baseAddress, 32)
      }
    }
    return output
  }
}

/// Gates the interface behind a passcode and biometrics. This hides the app from whoever is holding
/// the phone; the credentials themselves are protected by the Keychain, not by this passcode.
@MainActor
@Observable
final class AppLock {
  private(set) var isLocked: Bool
  private(set) var hasPasscode: Bool
  private(set) var lockedUntil: Date?
  var biometricsEnabled: Bool {
    didSet { UserDefaults.standard.set(biometricsEnabled, forKey: Self.biometricsKey) }
  }
  var lockDelay: AutoLockDelay {
    didSet { UserDefaults.standard.set(lockDelay.rawValue, forKey: Self.lockDelayKey) }
  }

  private var failedAttempts: Int {
    didSet { UserDefaults.standard.set(failedAttempts, forKey: Self.attemptsKey) }
  }
  private var backgroundedAt: Double?
  /// True from launch or leaving the app until the next prompt. The prompt itself makes the app
  /// inactive and active again, so asking every time it becomes active would never stop.
  private var shouldPromptBiometrics = true

  private static let biometricsKey = "biometricsEnabled"
  private static let lockDelayKey = "autoLockDelay"
  private static let attemptsKey = "failedPasscodeAttempts"
  private static let lockoutKey = "passcodeLockedUntil"
  private static let lockoutClockStartKey = "passcodeLockoutClockStart"
  private static let lockoutClockEndKey = "passcodeLockoutClockEnd"
  private static let hasLaunchedKey = "hasLaunchedBefore"
  private static let freeAttempts = 5

  init() {
    Self.removeKeychainLeftovers()
    let exists = Self.storedRecord() != nil
    hasPasscode = exists
    isLocked = exists
    biometricsEnabled = UserDefaults.standard.bool(forKey: Self.biometricsKey)
    lockDelay = AutoLockDelay(rawValue: UserDefaults.standard.integer(forKey: Self.lockDelayKey)) ?? .immediately
    failedAttempts = UserDefaults.standard.integer(forKey: Self.attemptsKey)
    lockedUntil = UserDefaults.standard.object(forKey: Self.lockoutKey) as? Date
    syncLockout()
  }

  /// The Keychain outlives the app, unlike UserDefaults. After a reinstall, an old passcode would
  /// otherwise lock an empty app. Anything saved by an older version keeps its devices, so stays.
  private static func removeKeychainLeftovers() {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: hasLaunchedKey) else { return }
    defaults.set(true, forKey: hasLaunchedKey)
    if defaults.object(forKey: "devices") == nil, defaults.object(forKey: "certificates") == nil {
      KeychainStore.removeAll()
    }
  }

  var biometryType: LABiometryType {
    let context = LAContext()
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
      return .none
    }
    return context.biometryType
  }

  var biometryName: String {
    switch biometryType {
    case .faceID: "Face ID"
    case .touchID: "Touch ID"
    case .opticID: "Optic ID"
    default: "Face ID or Touch ID"
    }
  }

  var isBiometryAvailable: Bool { biometryType != .none }

  func didEnterBackground() {
    guard hasPasscode else { return }
    backgroundedAt = Self.monotonicSeconds
    shouldPromptBiometrics = true
    if lockDelay == .immediately { isLocked = true }
  }

  func didBecomeActive() {
    if hasPasscode, let backgroundedAt, Self.monotonicSeconds - backgroundedAt >= lockDelay.seconds {
      isLocked = true
    }
    backgroundedAt = nil
  }

  /// Biometrics fail unless the app is active, so this has to wait until it is.
  func promptBiometricsIfNeeded() async {
    guard shouldPromptBiometrics else { return }
    shouldPromptBiometrics = false
    if await unlockWithBiometrics() == .notInteractive {
      // Asked too early; the next time the app becomes active tries again.
      shouldPromptBiometrics = true
    }
  }

  /// Compares without unlocking, for confirming a change in Settings. Failures still count.
  func verify(_ passcode: String) -> Bool {
    syncLockout()
    if let lockedUntil, lockedUntil > .now { return false }
    guard let record = Self.storedRecord() else { return false }
    if record.matches(passcode) {
      failedAttempts = 0
      setLockout(nil)
      return true
    }
    failedAttempts += 1
    if failedAttempts >= Self.freeAttempts {
      // 30 seconds, doubling with each further failure, up to an hour.
      let extra = Double(min(failedAttempts - Self.freeAttempts, 7))
      setLockout(.now.addingTimeInterval(min(30 * pow(2, extra), 3600)))
    }
    return false
  }

  func unlock(with passcode: String) -> Bool {
    guard verify(passcode) else { return false }
    isLocked = false
    return true
  }

  /// Returns why biometrics failed, if they were tried and did.
  @discardableResult
  func unlockWithBiometrics() async -> LAError.Code? {
    guard biometricsEnabled, isLocked else { return nil }
    let context = LAContext()
    context.localizedFallbackTitle = ""
    do {
      _ = try await context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock Dev Manager")
      failedAttempts = 0
      setLockout(nil)
      isLocked = false
      return nil
    } catch {
      return (error as? LAError)?.code ?? .authenticationFailed
    }
  }

  /// Confirms the person can use biometrics before turning them on.
  func enableBiometrics() async -> Bool {
    let success = try? await LAContext().evaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock Dev Manager")
    biometricsEnabled = success == true
    return biometricsEnabled
  }

  func setPasscode(_ passcode: String) throws {
    let data = try JSONEncoder().encode(PasscodeRecord(passcode: passcode))
    try KeychainStore.save(
      DeviceSecrets(privateKey: data.base64EncodedString()), for: KeychainStore.passcodeRecordID)
    hasPasscode = true
    failedAttempts = 0
    setLockout(nil)
  }

  func removePasscode() {
    KeychainStore.remove(for: KeychainStore.passcodeRecordID)
    hasPasscode = false
    isLocked = false
    biometricsEnabled = false
    lockDelay = .immediately
    failedAttempts = 0
    setLockout(nil)
  }

  private func setLockout(_ date: Date?) {
    lockedUntil = date
    let defaults = UserDefaults.standard
    defaults.set(date, forKey: Self.lockoutKey)
    let now = Self.monotonicSeconds
    defaults.set(now, forKey: Self.lockoutClockStartKey)
    defaults.set(date.map { now + $0.timeIntervalSinceNow } ?? 0, forKey: Self.lockoutClockEndKey)
  }

  /// Times the wait so that changing the date in Settings doesn't shorten it. A clock lower than when
  /// the wait started means the phone restarted, and then only the saved date is left to go by.
  private func syncLockout() {
    let defaults = UserDefaults.standard
    let start = defaults.double(forKey: Self.lockoutClockStartKey)
    let end = defaults.double(forKey: Self.lockoutClockEndKey)
    let now = Self.monotonicSeconds
    guard end > 0, now >= start else { return }
    lockedUntil = now < end ? Date.now.addingTimeInterval(end - now) : nil
  }

  /// Unlike the date, this can't be changed by the user, and it keeps counting while the phone sleeps.
  private static var monotonicSeconds: Double {
    Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
  }

  private static func storedRecord() -> PasscodeRecord? {
    guard let encoded = KeychainStore.secrets(for: KeychainStore.passcodeRecordID).privateKey,
      let data = Data(base64Encoded: encoded)
    else { return nil }
    return try? JSONDecoder().decode(PasscodeRecord.self, from: data)
  }
}
