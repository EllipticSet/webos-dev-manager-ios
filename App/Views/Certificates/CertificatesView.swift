import SwiftUI

struct CertificatesView: View {
  /// False in the sidebar, where there's nothing to dismiss.
  var isPresentedAsSheet = true
  @Environment(CertificateStore.self) private var certificates
  @Environment(\.dismiss) private var dismiss
  @State private var isCreating = false
  @State private var certificateToDelete: SSHCertificate?

  var body: some View {
    NavigationStack {
      List(certificates.certificates) { certificate in
        // Pushed with a value, so that it doesn't stay in place when another sidebar row is chosen.
        NavigationLink(value: certificate.id) {
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
          Button("Delete", systemImage: "trash") { certificateToDelete = certificate }
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
      .navigationDestination(for: SSHCertificate.ID.self) { CertificateDetailView(certificateID: $0) }
      .sheet(isPresented: $isCreating) { NewCertificateView() }
      .certificateDeletion($certificateToDelete)
    }
  }
}
