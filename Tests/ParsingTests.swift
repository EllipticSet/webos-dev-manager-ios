import Foundation
import Testing

@testable import Dev_Manager

struct SSHKeyLoaderTests {
  @Test(arguments: [TestKeys.aes128, TestKeys.des3, TestKeys.pkcs8enc, TestKeys.ed25519Encrypted])
  func encryptedKeysOpenWithPassphrase(key: String) throws {
    try SSHKeyLoader.validate(key: key, passphrase: "ABC123")
  }

  @Test(arguments: [TestKeys.rsa, TestKeys.pkcs8])
  func plainKeysOpenWithoutPassphrase(key: String) throws {
    try SSHKeyLoader.validate(key: key, passphrase: nil)
  }

  @Test(arguments: [TestKeys.aes128, TestKeys.des3, TestKeys.pkcs8enc, TestKeys.ed25519Encrypted])
  func encryptedKeysReportMissingPassphrase(key: String) {
    #expect {
      try SSHKeyLoader.validate(key: key, passphrase: nil)
    } throws: { error in
      if case DeviceError.passphraseRequired = error { return true }
      return false
    }
  }

  @Test(arguments: [TestKeys.aes128, TestKeys.pkcs8enc, TestKeys.ed25519Encrypted])
  func wrongPassphraseIsReported(key: String) {
    #expect {
      try SSHKeyLoader.validate(key: key, passphrase: "WRONG9")
    } throws: { error in
      if case DeviceError.wrongPassphrase = error { return true }
      return false
    }
  }

  @Test func garbageIsRejected() {
    #expect(throws: DeviceError.self) {
      try SSHKeyLoader.validate(key: "<html>not a key</html>", passphrase: "x")
    }
  }
}

struct VersionTests {
  @Test func comparesVersions() throws {
    #expect(try #require(PackageVersion("1.2.3.4")) > #require(PackageVersion("1.2.3.3")))
    #expect(try #require(PackageVersion("1.10.0")) > #require(PackageVersion("1.9.9")))
    #expect(try #require(PackageVersion("1.0.0-beta")) < #require(PackageVersion("1.0.0")))
    #expect(PackageVersion("not.a.version") == nil)
  }

  @Test(arguments: [
    (">=4.0.0", "5.1.0", true), (">=4.0.0", "3.9.0", false), ("<6", "5.9.0", true),
    (">=4 <6", "6.0.0", false), ("4.x || 6.x", "6.2.0", true), ("^4.1.0", "5.0.0", false),
    ("~4.1.0", "4.1.9", true), ("4", "5.0.0", false),
  ])
  func evaluatesRanges(range: String, version: String, expected: Bool) throws {
    #expect(VersionRange(range).contains(try #require(PackageVersion(version))) == expected)
  }

  @Test func detectsUpdates() {
    let manifest = PackageManifest(id: "a", version: "1.2.0", ipkUrl: "x")
    #expect(manifest.hasUpdate(over: "1.1.9"))
    #expect(!manifest.hasUpdate(over: "1.2.0"))
    #expect(!manifest.hasUpdate(over: nil))
  }
}

struct RepositoryTests {
  @Test func decodesPageWithRootVariants() throws {
    let json = """
      {"paging":{"page":1,"count":2,"maxPage":3,"itemsTotal":50},"packages":[
      {"id":"a","title":"A","iconUri":"icons/a.png","manifest":{"id":"a","version":"1.0.0","ipkUrl":"u","rootRequired":true,"ipkHash":{"sha256":"h"}},
       "requirements":{"webosRelease":">=5","deviceSoC":["!m16"]}},
      {"id":"b","title":"B","manifest":{"id":"b","version":"1.0.0","ipkUrl":"u","rootRequired":"optional"}}]}
      """
    let page = try JSONDecoder().decode(RepositoryPage.self, from: Data(json.utf8))
    let first = page.packages[0].resolved(against: URL(string: "https://repo.webosbrew.org/api/apps.json")!)
    #expect(first.iconUri == "https://repo.webosbrew.org/api/icons/a.png")
    #expect(first.manifest?.rootRequired == .required)
    #expect(page.packages[1].manifest?.rootRequired == .optional)
    let reasons = first.incompatibilities(
      with: DeviceDetails(osVersion: "4.9.0", socName: "m16"),
      homebrew: HomebrewConfiguration(root: false))
    #expect(reasons == [.release, .soc, .root])
  }
}

struct DeviceOutputTests {
  @Test func parsesListing() {
    let output = """
      total 8
      drwxr-xr-x    2 prisoner prisoner      4096 Jan  1 00:00 .
      drwxr-xr-x    2 root     root          4096 Jan  1 00:00 ..
      drwxr-xr-x    2 prisoner prisoner      4096 Jan  1 00:00 my apps
      -rw-r--r--    1 prisoner prisoner       123 Jan  1 00:00 a.txt
      lrwxrwxrwx    1 root     root             3 Jan  1 00:00 link -> a.txt
      """
    let files = RemoteFile.parseListing(output, directory: "/media")
    #expect(files.map(\.name) == ["my apps", "a.txt", "link"])
    #expect(files[0].isDirectory && files[0].path == "/media/my apps")
    #expect(files[1].size == 123)
    #expect(files[2].isLink && files[2].linkTarget == "a.txt")
  }

  @Test func quotesForShell() {
    #expect("it's".shellQuoted == #"'it'\''s'"#)
  }

  @Test func formatsMode() {
    #expect(RemoteFile.modeString(permissions: 0o040755) == "drwxr-xr-x")
    #expect(RemoteFile.modeString(permissions: 0o100644) == "-rw-r--r--")
  }

  @Test func parsesDf() {
    let info = StorageInfo.parse(df: "Filesystem 1K-blocks Used Available Use% Mounted\n/dev/x 1000 250 750 25% /media\n")
    #expect(info == StorageInfo(totalKilobytes: 1000, usedKilobytes: 250, availableKilobytes: 750))
  }

  @Test func parsesDevModeRemaining() {
    #expect(DevModeStatus(remaining: "120:30:15").remainingInterval == 433815)
    #expect(DevModeStatus(remaining: "soon").remainingInterval == nil)
  }

  @Test func namesCrashReports() {
    let file = RemoteFile(
      name: "x\u{01}usr\u{01}palm\u{01}applications\u{01}com.app\u{01}bin\u{01}main____main.123.456.gz",
      path: "/c/f", kind: .file)
    let report = CrashReport(file: file)
    #expect(report.title == "com.app (123)")
    #expect(report.summary == "main")
    let unknown = CrashReport(file: RemoteFile(name: "weird", path: "/c/g", kind: .file))
    #expect(unknown.title == "Unknown crash")
  }

  @Test func splitsLinesAcrossChunks() {
    var splitter = LineSplitter()
    #expect(splitter.append(Data("ab".utf8)).isEmpty)
    #expect(splitter.append(Data("c\nde\nf".utf8)) == ["abc", "de"])
    #expect(splitter.finish() == "f")
  }

  @Test func parsesLogs() throws {
    let line = #"2024-01-02T03:04:05.123456Z [12.5] user.err proc [1:2] ctx MSG {"a":{"b":"}"}} hello"#
    let entry = try #require(LogEntry.parsePmLog(line))
    #expect(entry.level == .err && entry.process == "proc" && entry.message == "hello")
    let dmesg = try #require(LogEntry.parseDmesg("kern  :warn  : [   1.5] usb: found"))
    #expect(dmesg.level == .warning && dmesg.context == "usb" && dmesg.message == "found")
  }

  @Test func foldsLunaCalls() {
    var builder = LunaCallBuilder()
    builder.add(line: #"{"type":"call","transport":"TX","token":5,"senderUniqueName":"s","sender":"com.a","destination":"com.b","methodCategory":"/x","method":"go","payload":{"k":1}}"#)
    builder.add(line: #"{"type":"return","transport":"TX","replyToken":5,"destinationUniqueName":"s","payload":{"ok":true}}"#)
    #expect(builder.calls.count == 1)
    #expect(builder.calls[0].messages.map(\.type) == ["call", "return"])
  }

  @Test func recognisesInstallerResponses() throws {
    #expect(try DeviceService.isFinished(appInstallResponse: ["details": ["state": "installed"]], expected: /installed/.ignoresCase()))
    #expect(try !DeviceService.isFinished(appInstallResponse: ["details": ["state": "installing"]], expected: /installed/.ignoresCase()))
    #expect(throws: DeviceError.self) {
      try DeviceService.isFinished(appInstallResponse: ["details": ["state": "FAILED", "reason": "FAILED_IPKG_INSTALL", "errorCode": -5]], expected: /installed/.ignoresCase())
    }
  }

  @Test func renewalScriptHasNoKey() {
    let script = RenewalScript.make(deviceName: "TV", token: "abc123")
    #expect(script.contains("sessionToken=$SESSION_TOKEN"))
    #expect(!script.contains("PRIVATE KEY"))
  }
}

struct ChecksumTests {
  @Test func verifiesDownloads() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("abc".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let good = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    try DeviceService.verify(fileAt: url, sha256: good)
    try DeviceService.verify(fileAt: url, sha256: good.uppercased())
    try DeviceService.verify(fileAt: url, sha256: nil)
    #expect(throws: DeviceError.self) { try DeviceService.verify(fileAt: url, sha256: "00") }
  }
}

struct CertificateTests {
  @Test(arguments: CertificateKind.allCases)
  func generatedKeysAreUsable(kind: CertificateKind) throws {
    let key = try SSHKeyGenerator.generate(kind, comment: "test")
    try SSHKeyLoader.validate(key: key, passphrase: nil)
    let line = try SSHKeyLoader.publicKeyLine(fromPrivateKey: key, passphrase: nil)
    #expect(line.hasPrefix(kind == .ed25519 ? "ssh-ed25519 AAAA" : "ssh-rsa AAAA"))
    let certificate = SSHCertificate(name: "t", typeName: kind.title, publicKey: line)
    #expect(certificate.fingerprint.hasPrefix("SHA256:"))
    #expect(certificate.installCommand.contains(line.shellQuoted))
  }

  @Test(arguments: [TestKeys.aes128, TestKeys.pkcs8enc, TestKeys.ed25519Encrypted])
  func publicKeyIsReadFromImportedKeys(key: String) throws {
    let line = try SSHKeyLoader.publicKeyLine(fromPrivateKey: key, passphrase: "ABC123")
    #expect(line.hasPrefix("ssh-"))
  }

}

struct PasscodeTests {
  @Test func recordOnlyMatchesItsPasscode() {
    let record = PasscodeRecord(passcode: "123456", rounds: 1000)
    #expect(record.matches("123456"))
    #expect(!record.matches("654321"))
    #expect(record.salt != PasscodeRecord(passcode: "123456", rounds: 1000).salt)
  }
}

struct DescriptionCacheTests {
  @Test func savesMeasuresAndClears() {
    let url = URL(string: "https://example.com/\(UUID().uuidString).html")!
    DescriptionCache.clear()
    #expect(DescriptionCache.read(for: url) == nil)
    #expect(DescriptionCache.size() == 0)
    DescriptionCache.write("<p>ciao</p>", for: url)
    #expect(DescriptionCache.read(for: url) == "<p>ciao</p>")
    #expect(DescriptionCache.size() == 11)
    DescriptionCache.clear()
    #expect(DescriptionCache.read(for: url) == nil)
    #expect(DescriptionCache.size() == 0)
  }
}

struct TimeoutTests {
  @Test func stalledOperationTimesOut() async {
    await #expect(throws: DeviceError.self) {
      try await withTimeout(seconds: 0.1) {
        try await Task.sleep(for: .seconds(30))
        return 1
      }
    }
  }

  @Test func activityPostponesTheTimeout() async throws {
    let value = try await withInactivityTimeout(seconds: 0.3) { touch in
      for _ in 0..<5 {
        try await Task.sleep(for: .milliseconds(100))
        touch()
      }
      return 7
    }
    #expect(value == 7)
  }

  /// The operation ignores cancellation, as NIO futures do, so only the caller can stop waiting.
  @Test func cancellingDoesNotWaitForTheOperation() async {
    let start = Date()
    let task = Task {
      try await withTimeout(seconds: 30) {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
          DispatchQueue.global().asyncAfter(deadline: .now() + 5) { continuation.resume() }
        }
      }
    }
    try? await Task.sleep(for: .milliseconds(50))
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(Date().timeIntervalSince(start) < 2)
  }
}

struct HostKeyTrialTests {
  @Test func keyIsSavedOnlyOnCommit() {
    let id = UUID()
    defer { TrustOnFirstUseValidator.forget(for: id) }
    TrustOnFirstUseValidator.remember("old", for: id)
    let trial = HostKeyTrial()
    trial.record("new")
    #expect(TrustOnFirstUseValidator.knownKey(for: id) == "old")
    trial.commit(for: id)
    #expect(TrustOnFirstUseValidator.knownKey(for: id) == "new")
  }
}

struct LunaCallLimitTests {
  @Test func oldCallsAreDroppedAndRepliesStillMatch() {
    var builder = LunaCallBuilder()
    for token in 0...2000 {
      builder.add(line: #"{"type":"call","token":\#(token),"senderUniqueName":"s","method":"go"}"#)
    }
    #expect(builder.calls.count == 1801)
    builder.add(line: #"{"type":"return","replyToken":2000,"destinationUniqueName":"s"}"#)
    #expect(builder.calls.last?.messages.count == 2)
    builder.add(line: #"{"type":"return","replyToken":0,"destinationUniqueName":"s"}"#)
    #expect(builder.calls.first?.messages.count == 1)
  }
}
