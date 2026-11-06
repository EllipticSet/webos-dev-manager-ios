import SwiftUI

/// A certificate's details, and sending its public key to a saved TV.
struct CertificateDetailView: View {
  var certificateID: UUID

  @Environment(CertificateStore.self) private var certificates
  @Environment(DeviceStore.self) private var devices
  @State private var progress: SendProgress?
  @State private var result: SendResult?
  @State private var didCopy = false

  private var certificate: SSHCertificate? {
    certificates.certificates.first { $0.id == certificateID }
  }

  var body: some View {
    if let certificate {
      Form {
        Section {
          LabeledContent("Name") {
            TextField("Name", text: nameBinding(for: certificate))
              .multilineTextAlignment(.trailing)
          }
          DetailRow(title: "Type", value: certificate.typeName)
          DetailRow(
            title: "Created",
            value: certificate.created.formatted(date: .abbreviated, time: .shortened))
          VStack(alignment: .leading, spacing: 4) {
            Text("Fingerprint")
            Text(certificate.fingerprint)
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }

        Section("Send to TV") {
          if devices.devices.isEmpty {
            Text("No saved TVs yet. Add one in Manage TVs.")
              .foregroundStyle(.secondary)
          }
          ForEach(devices.devices) { device in
            sendRow(for: device, certificate: certificate)
          }
        }

        Section {
          Button(didCopy ? "Copied" : "Copy Public Key", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = certificate.publicKey
            didCopy = true
          }
          ShareLink("Share Public Key", item: certificate.publicKey)
        } header: {
          Text("Public Key")
        } footer: {
          Text("Only the public key leaves this iPhone. Sending it to a TV also makes that TV sign in with this certificate, if the TV accepts it.")
        }
      }
      .navigationTitle(certificate.name)
      .navigationBarTitleDisplayMode(.inline)
      .scrollDismissesKeyboard(.interactively)
      .overlay {
        if let progress {
          SendProgressCard(progress: progress)
        }
      }
      .interactiveDismissDisabled(progress != nil)
      .navigationBarBackButtonHidden(progress != nil)
      .alert(
        result?.title ?? "", isPresented: isShowingResult, presenting: result
      ) { _ in
        Button("OK", role: .cancel) {}
      } message: { result in
        Text(result.message)
      }
    }
  }

  private var isShowingResult: Binding<Bool> {
    Binding { result != nil } set: { if !$0 { result = nil } }
  }

  private func nameBinding(for certificate: SSHCertificate) -> Binding<String> {
    Binding {
      certificate.name
    } set: {
      certificates.rename(certificate.id, to: $0)
    }
  }

  private func sendRow(for device: Device, certificate: SSHCertificate) -> some View {
    let isInUse = device.authentication == .certificate && device.certificateID == certificate.id
    return Button {
      send(certificate, to: device)
    } label: {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(device.name)
            .foregroundStyle(.primary)
          Text("\(device.username)@\(device.host)")
            .font(.caption)
            .foregroundStyle(.secondary)
          if isInUse {
            Text("Signs in with this certificate")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        if certificate.sentToDeviceIDs.contains(device.id) {
          Label("Sent", systemImage: "checkmark.circle.fill")
            .labelStyle(.iconOnly)
            .foregroundStyle(.green)
        } else {
          Image(systemName: "paperplane")
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
        }
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityHint("Sends the public key to this TV and signs in with it")
  }

  private func send(_ certificate: SSHCertificate, to device: Device) {
    progress = SendProgress(deviceName: device.name, fraction: 0.1, status: "Connecting to the TV…")
    let service = devices.service(for: device)
    let command = certificate.installCommand
    Task {
      defer { progress = nil }
      do {
        // Without a limit, a TV that stops responding would leave the progress on screen forever.
        _ = try await withTimeout(seconds: 30) { try await service.session.run("true") }
        await update(0.4, "Sending the public key…")
        _ = try await withTimeout(seconds: 30) { try await service.session.run(command) }
        certificates.markSent(certificate.id, to: device.id)
        await update(0.7, "Testing sign-in with the certificate…")
      } catch {
        result = SendResult(
          title: "Couldn't Send the Certificate", message: DeviceError.message(for: error))
        return
      }

      // Only switch once the TV has accepted the key, so a refusal can't lock anyone out.
      var candidate = device
      candidate.authentication = .certificate
      candidate.certificateID = certificate.id
      let test = DeviceSession(device: candidate, secrets: DeviceSecrets())
      do {
        _ = try await withTimeout(seconds: 30) { try await test.run("true") }
        await test.disconnect()
        await update(1, "Updating the TV's sign-in method…")
        // The previous credentials stay saved, so the method can be switched back.
        try devices.save(candidate, secrets: devices.secrets(for: device))
        result = SendResult(
          title: "Certificate Sent",
          message: "\(device.name) now signs in with “\(certificate.name)”.")
      } catch {
        await test.disconnect()
        result = SendResult(
          title: "Sent, but Sign-In Wasn't Changed",
          message: "The key reached \(device.name), but the TV didn't accept it for signing in, so the sign-in method stays the same. Developer Mode TVs only accept their own key, and older SSH servers may not support Ed25519.")
      }
    }
  }

  /// Holds each step on screen briefly, because on a fast network they'd pass unseen.
  private func update(_ fraction: Double, _ status: String) async {
    withAnimation(.smooth) {
      progress?.fraction = fraction
      progress?.status = status
    }
    try? await Task.sleep(for: .milliseconds(350))
  }
}

private struct SendProgress {
  var deviceName: String
  var fraction: Double
  var status: String
}

private struct SendResult: Identifiable {
  var id = UUID()
  var title: String
  var message: String
}

private struct SendProgressCard: View {
  var progress: SendProgress

  var body: some View {
    ZStack {
      Color.black.opacity(0.3)
        .ignoresSafeArea()
      VStack(spacing: 16) {
        Text("Sending to \(progress.deviceName)")
          .font(.headline)
          .multilineTextAlignment(.center)
        ProgressView(value: progress.fraction)
        Text(progress.status)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .padding(24)
      .frame(maxWidth: 340)
      .background(.regularMaterial, in: .rect(cornerRadius: 24))
      .padding()
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isModal)
    }
  }
}
