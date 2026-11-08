import SwiftUI

extension View {
  /// Asks before deleting the certificate set in `request`, or, while a TV signs in with it,
  /// explains that it can't be deleted: that TV would no longer be able to connect.
  func certificateDeletion(
    _ request: Binding<SSHCertificate?>, onDelete: @escaping () -> Void = {}
  ) -> some View {
    modifier(CertificateDeletion(request: request, onDelete: onDelete))
  }
}

private struct CertificateDeletion: ViewModifier {
  @Binding var request: SSHCertificate?
  var onDelete: () -> Void

  @Environment(CertificateStore.self) private var certificates
  @Environment(DeviceStore.self) private var devices
  @State private var certificateToDelete: SSHCertificate?
  @State private var blockedMessage: String?

  func body(content: Content) -> some View {
    content
      .onChange(of: request) {
        guard let request else { return }
        self.request = nil
        evaluate(request)
      }
      .confirmationAlert(
        { "Delete “\($0.name)”?" }, presenting: $certificateToDelete,
        message: { _ in "The private key will be deleted from this iPhone. Public keys already sent to TVs stay there." },
        actionTitle: "Delete", role: .destructive
      ) {
        certificates.remove($0)
        onDelete()
      }
      .noticeAlert({ _ in "Certificate in Use" }, presenting: $blockedMessage) { "\($0)" }
  }

  private func evaluate(_ certificate: SSHCertificate) {
    let users = devices.devices.filter {
      $0.authentication == .certificate && $0.certificateID == certificate.id
    }
    guard !users.isEmpty else {
      certificateToDelete = certificate
      return
    }
    let names = users.map(\.name).formatted(.list(type: .and))
    blockedMessage = users.count == 1
      ? String(localized: "\(names) signs in with this certificate and couldn't connect without it. Choose another sign-in method in Manage TVs first.")
      : String(localized: "\(names) sign in with this certificate and couldn't connect without it. Choose another sign-in method in Manage TVs first.")
  }
}
