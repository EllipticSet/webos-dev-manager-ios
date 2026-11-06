import SwiftUI
import UniformTypeIdentifiers

struct DeviceEditorView: View {
  @State var device: Device
  @State var secrets: DeviceSecrets
  var isNew: Bool

  @Environment(DeviceStore.self) private var store
  @Environment(CertificateStore.self) private var certificates
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dismissAddFlow) private var dismissAddFlow

  @State private var portText = ""
  @State private var isImportingKey = false
  @State private var isSaving = false
  @State private var errorMessage: String?
  @State private var check: ConnectionCheck?
  @State private var isChecking = false
  @State private var keyFileName: String?
  @State private var didForgetHostKey = false
  @State private var shouldUpdateKey = false

  private var canSave: Bool {
    guard !device.name.trimmed.isEmpty, !device.host.trimmed.isEmpty,
      let port = Int(portText), (1...65535).contains(port), !device.username.trimmed.isEmpty
    else { return false }
    switch device.authentication {
    case .devModeKey: return !(secrets.passphrase ?? "").isEmpty
    case .importedKey: return secrets.privateKey != nil
    case .password: return !(secrets.password ?? "").isEmpty
    case .certificate: return device.certificateID != nil
    }
  }

  var body: some View {
    Form {
      Section("TV") {
        LabeledContent("Name") {
          TextField("Name", text: $device.name, prompt: Text("Living Room TV"))
            .textInputAutocapitalization(.words)
            .multilineTextAlignment(.trailing)
        }
        LabeledContent("IP Address") {
          TextField("IP Address", text: $device.host, prompt: Text("192.168.1.50"))
            .keyboardType(.numbersAndPunctuation)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .multilineTextAlignment(.trailing)
        }
      }

      Section("Sign-In") {
        LabeledContent("Port") {
          TextField("Port", text: $portText)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
        }
        LabeledContent("User") {
          TextField("User", text: $device.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .multilineTextAlignment(.trailing)
        }
        Picker("Method", selection: $device.authentication) {
          ForEach(DeviceAuthentication.allCases) { method in
            Text(method.title).tag(method)
          }
        }
        credentialFields
      }

      Section {
        Button("Check Connection", systemImage: "network") { checkConnection() }
          .disabled(device.host.trimmed.isEmpty || isChecking)
        if isChecking {
          ProgressView()
        }
        if let check {
          reachabilityRow("Key Server (9991)", check.keyServer)
          reachabilityRow("SSH Developer Mode (9922)", check.ssh9922)
          reachabilityRow("Root SSH (22)", check.ssh22)
        }
      } footer: {
        Text("Checks which services respond at this address.")
      }

      if !isNew {
        Section {
          Button(didForgetHostKey ? "TV Identity Forgotten" : "Forget TV Identity") {
            store.forgetHostKey(of: device)
            didForgetHostKey = true
          }
          .disabled(didForgetHostKey)
        } footer: {
          Text("Use this only if you reset the TV and the app reports that its identity has changed.")
        }
      }

    }
    .scrollDismissesKeyboard(.interactively)
    .alert(isNew ? "Couldn't Add the TV" : "Couldn't Save the TV", isPresented: isShowingError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "")
    }
    .navigationTitle(isNew ? "New TV" : device.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        if isSaving {
          ProgressView()
        } else {
          Button("Save", role: .confirm) { save() }
            .disabled(!canSave)
        }
      }
    }
    .onAppear { portText = String(device.port) }
    .fileImporter(isPresented: $isImportingKey, allowedContentTypes: [.data, .text]) { result in
      importKey(result)
    }
  }

  @ViewBuilder
  private var credentialFields: some View {
    switch device.authentication {
    case .devModeKey:
      LabeledContent("Passphrase") {
        // Plain text: it's already on the TV's screen, and a secure field prompts to save a password.
        TextField("Passphrase", text: secretBinding(\.passphrase), prompt: Text("Shown on the TV"))
          .textInputAutocapitalization(.characters)
          .autocorrectionDisabled()
          .multilineTextAlignment(.trailing)
      }
      if !isNew {
        Button("Update Key from TV", systemImage: "arrow.down.circle") {
          shouldUpdateKey = true
          save()
        }
        .disabled(!canSave || isSaving)
      }
    case .importedKey:
      Button(
        keyFileName ?? (secrets.privateKey == nil ? "Choose Key File…" : "Replace Key…"),
        systemImage: "key"
      ) { isImportingKey = true }
      LabeledContent("Passphrase") {
        SecureField("Passphrase", text: secretBinding(\.passphrase), prompt: Text("If any"))
          .autocorrectionDisabled()
          .multilineTextAlignment(.trailing)
      }
    case .password:
      LabeledContent("Password") {
        SecureField("Password", text: secretBinding(\.password), prompt: Text("Required"))
          .multilineTextAlignment(.trailing)
      }
    case .certificate:
      certificatePicker
    }
  }

  @ViewBuilder
  private var certificatePicker: some View {
    if certificates.certificates.isEmpty {
      Text("No certificates yet. Create one in Certificates, in the top-left menu.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    } else {
      Picker("Certificate", selection: $device.certificateID) {
        Text("Choose…").tag(UUID?.none)
        ForEach(certificates.certificates) { certificate in
          Text(certificate.name).tag(Optional(certificate.id))
        }
      }
    }
  }

  private func reachabilityRow(_ title: LocalizedStringKey, _ isReachable: Bool) -> some View {
    LabeledContent(title) {
      Label(
        isReachable ? "Reachable" : "Not Reachable",
        systemImage: isReachable ? "checkmark.circle.fill" : "xmark.circle"
      )
      .foregroundStyle(isReachable ? Color.green : Color.secondary)
      .labelStyle(.titleAndIcon)
      .font(.subheadline)
    }
  }

  private var isShowingError: Binding<Bool> {
    Binding { errorMessage != nil } set: { if !$0 { errorMessage = nil } }
  }

  private func secretBinding(_ keyPath: WritableKeyPath<DeviceSecrets, String?>) -> Binding<String> {
    Binding {
      secrets[keyPath: keyPath] ?? ""
    } set: {
      secrets[keyPath: keyPath] = $0.isEmpty ? nil : $0
    }
  }

  private func checkConnection() {
    isChecking = true
    let host = device.host.trimmed
    Task {
      check = await DeviceSetupClient().checkConnection(host: host)
      isChecking = false
    }
  }

  private func importKey(_ result: Result<URL, Error>) {
    guard case .success(let url) = result else { return }
    let didAccess = url.startAccessingSecurityScopedResource()
    defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
      errorMessage = DeviceError.unsupportedKey.errorDescription
      return
    }
    secrets.privateKey = text
    keyFileName = url.lastPathComponent
    errorMessage = nil
  }

  /// Fetches the key if needed and proves the login works before saving anything. A change that
  /// doesn't affect the connection, such as a new name, works without reaching the TV.
  private func save() {
    isSaving = true
    errorMessage = nil
    let stored = store.devices.first { $0.id == device.id }
    let storedSecrets = isNew ? DeviceSecrets() : store.secrets(for: device)
    let updateKey = shouldUpdateKey
    shouldUpdateKey = false
    var candidate = device
    candidate.name = device.name.trimmed
    candidate.host = device.host.trimmed
    candidate.username = device.username.trimmed
    candidate.port = Int(portText) ?? device.port
    var candidateSecrets = secrets
    Task {
      do {
        if let stored, !updateKey, candidateSecrets == storedSecrets,
          candidate.hasSameConnection(as: stored)
        {
          try store.save(candidate, secrets: storedSecrets)
          if let dismissAddFlow { dismissAddFlow() } else { dismiss() }
          isSaving = false
          return
        }
        switch candidate.authentication {
        case .devModeKey:
          let passphrase = (candidateSecrets.passphrase ?? "").trimmed
          candidateSecrets.passphrase = passphrase
          if updateKey || candidateSecrets.privateKey == nil || passphrase != storedSecrets.passphrase {
            candidateSecrets.privateKey = try await DeviceSetupClient().fetchDevModeKey(
              host: candidate.host, passphrase: passphrase)
          }
          candidateSecrets.password = nil
        case .importedKey:
          try SSHKeyLoader.validate(
            key: candidateSecrets.privateKey ?? "", passphrase: candidateSecrets.passphrase)
          candidateSecrets.password = nil
        case .password:
          candidateSecrets.privateKey = nil
          candidateSecrets.passphrase = nil
        case .certificate:
          candidateSecrets = DeviceSecrets()
        }
        // A new address can legitimately come with a new host key. It replaces the saved one only
        // if the sign-in works, so that a mistyped address can't cut off a working TV.
        let trial = stored?.host == candidate.host ? nil : HostKeyTrial()
        let session = DeviceSession(
          device: candidate, secrets: candidateSecrets, hostKeyTrial: trial)
        do {
          try await session.run("true")
          await session.disconnect()
          trial?.commit(for: candidate.id)
        } catch {
          await session.disconnect()
          throw error
        }
        try store.save(candidate, secrets: candidateSecrets)
        if isNew { store.selectedID = candidate.id }
        if let dismissAddFlow { dismissAddFlow() } else { dismiss() }
      } catch {
        errorMessage = DeviceError.message(for: error)
      }
      isSaving = false
    }
  }
}

extension Device {
  fileprivate func hasSameConnection(as other: Device) -> Bool {
    var copy = self
    copy.name = other.name
    copy.notes = other.notes
    return copy == other
  }
}

extension String {
  fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
