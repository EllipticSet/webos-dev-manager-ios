import SwiftUI
import UniformTypeIdentifiers

/// Generates a new key pair or imports an existing private key.
struct NewCertificateView: View {
  private enum Source: String, CaseIterable, Identifiable {
    case generate = "Generate"
    case importFile = "Import"
    var id: Self { self }
  }

  @Environment(CertificateStore.self) private var certificates
  @Environment(\.dismiss) private var dismiss

  @State private var source = Source.generate
  @State private var name = ""
  @State private var kind = CertificateKind.rsa2048
  @State private var importedKey: String?
  @State private var importedFileName: String?
  @State private var passphrase = ""
  @State private var isImporting = false
  @State private var isWorking = false
  @State private var errorMessage: String?

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var canSave: Bool {
    !trimmedName.isEmpty && (source == .generate || importedKey != nil) && !isWorking
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Source", selection: $source) {
            ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())
        }
        Section {
          LabeledContent("Name") {
            TextField("Name", text: $name, prompt: Text("Living Room Root"))
              .multilineTextAlignment(.trailing)
          }
          switch source {
          case .generate:
            Picker("Type", selection: $kind) {
              ForEach(CertificateKind.allCases) { Text($0.title).tag($0) }
            }
          case .importFile:
            Button(importedFileName ?? "Choose Key File…", systemImage: "doc") { isImporting = true }
            LabeledContent("Passphrase") {
              SecureField("Passphrase", text: $passphrase, prompt: Text("If any"))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .multilineTextAlignment(.trailing)
            }
          }
        } footer: {
          if source == .generate {
            Text("RSA works with every TV. Ed25519 is smaller and faster, but older SSH servers don't support it.")
          }
        }
      }
      .navigationTitle("New Certificate")
      .navigationBarTitleDisplayMode(.inline)
      .scrollDismissesKeyboard(.interactively)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          if isWorking {
            ProgressView()
          } else {
            Button("Save", role: .confirm) { save() }
              .disabled(!canSave)
          }
        }
      }
      .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item]) { importKey($0) }
      .alert("Couldn't Save the Certificate", isPresented: isShowingError) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage ?? "")
      }
    }
    .interactiveDismissDisabled(isWorking)
  }

  private var isShowingError: Binding<Bool> {
    Binding { errorMessage != nil } set: { if !$0 { errorMessage = nil } }
  }

  private func importKey(_ result: Result<URL, Error>) {
    guard case .success(let url) = result else { return }
    let didAccess = url.startAccessingSecurityScopedResource()
    defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
      errorMessage = DeviceError.unsupportedKey.errorDescription
      return
    }
    importedKey = text
    importedFileName = url.lastPathComponent
    if trimmedName.isEmpty { name = url.deletingPathExtension().lastPathComponent }
  }

  private func save() {
    isWorking = true
    let name = trimmedName
    let source = source
    let kind = kind
    let importedKey = importedKey
    let passphrase = passphrase.isEmpty ? nil : passphrase
    Task {
      do {
        switch source {
        case .generate:
          // RSA key generation can take seconds, so keep it off the main actor.
          let key = try await Task.detached {
            try SSHKeyGenerator.generate(kind, comment: name)
          }.value
          try certificates.add(name: name, typeName: kind.title, privateKey: key, passphrase: nil)
        case .importFile:
          let key = importedKey ?? ""
          let line = try SSHKeyLoader.publicKeyLine(fromPrivateKey: key, passphrase: passphrase)
          let typeName = String(line.prefix { $0 != " " })
          try certificates.add(
            name: name, typeName: typeName, privateKey: key, passphrase: passphrase)
        }
        dismiss()
      } catch {
        errorMessage = DeviceError.message(for: error)
      }
      isWorking = false
    }
  }
}
