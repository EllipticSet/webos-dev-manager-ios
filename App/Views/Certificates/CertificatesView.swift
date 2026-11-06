import SwiftUI

struct CertificatesView: View {
  /// False in the sidebar, where there's nothing to dismiss.
  var isPresentedAsSheet = true
  @Environment(CertificateStore.self) private var certificates
  @Environment(DeviceStore.self) private var devices
  @Environment(\.dismiss) private var dismiss
  @State private var isCreating = false
  @State private var certificateToDelete: SSHCertificate?
  @State private var blockedMessage: String?

  var body: some View {
    NavigationStack {
      List(certificates.certificates) { certificate in
        NavigationLink {
          CertificateDetailView(certificateID: certificate.id)
        } label: {
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text(certificate.name)
              Text(certificate.typeName)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "key.fill")
          }
        }
        .swipeActions {
          Button("Delete", systemImage: "trash", role: .destructive) { requestDelete(certificate) }
            .tint(.red)
        }
      }
      .overlay {
        if certificates.certificates.isEmpty {
          ContentUnavailableView {
            Label("No Certificates", systemImage: "key")
          } description: {
            Text("Create a certificate to sign in to rooted TVs without a password.")
          } actions: {
            Button("New Certificate", systemImage: "plus") { isCreating = true }
              .buttonStyle(.borderedProminent)
          }
        }
      }
      .navigationTitle("Certificates")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if isPresentedAsSheet {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done", role: .confirm) { dismiss() }
          }
        }
        ToolbarItem(placement: .primaryAction) {
          Button("New Certificate", systemImage: "plus") { isCreating = true }
        }
      }
      .sheet(isPresented: $isCreating) { NewCertificateView() }
      .confirmationDialog(
        "Delete \(certificateToDelete?.name ?? "Certificate")?", isPresented: isConfirmingDelete,
        titleVisibility: .visible, presenting: certificateToDelete
      ) { certificate in
        Button("Delete", role: .destructive) { certificates.remove(certificate) }
      } message: { _ in
        Text("The private key will be deleted from this iPhone. Public keys already sent to TVs stay there.")
      }
      .alert("Certificate in Use", isPresented: isShowingBlocked) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(blockedMessage ?? "")
      }
    }
  }

  private var isConfirmingDelete: Binding<Bool> {
    Binding { certificateToDelete != nil } set: { if !$0 { certificateToDelete = nil } }
  }

  private var isShowingBlocked: Binding<Bool> {
    Binding { blockedMessage != nil } set: { if !$0 { blockedMessage = nil } }
  }

  /// A TV signing in with this certificate would be locked out if it were deleted.
  private func requestDelete(_ certificate: SSHCertificate) {
    let users = devices.devices.filter {
      $0.authentication == .certificate && $0.certificateID == certificate.id
    }
    if users.isEmpty {
      certificateToDelete = certificate
    } else {
      let names = users.map(\.name).formatted(.list(type: .and))
      blockedMessage = "\(names) signs in with this certificate. Change its sign-in method first."
    }
  }
}
