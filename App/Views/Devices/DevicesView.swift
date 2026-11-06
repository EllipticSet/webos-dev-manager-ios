import SwiftUI

struct DevicesView: View {
  /// False in the sidebar, where there's nothing to dismiss.
  var isPresentedAsSheet = true
  @Environment(DeviceStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var isAdding = false
  @State private var deviceToEdit: Device?
  @State private var deviceToRemove: Device?

  var body: some View {
    NavigationStack {
      List {
        ForEach(store.devices) { device in
          row(for: device)
            .swipeActions(edge: .trailing) {
              Button("Remove", systemImage: "trash", role: .destructive) { deviceToRemove = device }
                .tint(.red)
            }
        }
      }
      .overlay {
        if store.devices.isEmpty {
          ContentUnavailableView {
            Label("No TVs", systemImage: "tv")
          } actions: {
            Button("Add TV", systemImage: "plus") { isAdding = true }
              .buttonStyle(.borderedProminent)
          }
        }
      }
      .navigationTitle("Manage TVs")
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(item: $deviceToEdit) { device in
        DeviceEditorView(device: device, secrets: store.secrets(for: device), isNew: false)
      }
      .toolbar {
        if isPresentedAsSheet {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done", role: .confirm) { dismiss() }
          }
        }
        ToolbarItem(placement: .primaryAction) {
          Button("Add TV", systemImage: "plus") { isAdding = true }
        }
      }
      .sheet(isPresented: $isAdding) { AddDeviceFlow() }
      .confirmationDialog(
        "Remove This TV?", isPresented: isConfirmingRemoval, titleVisibility: .visible,
        presenting: deviceToRemove
      ) { device in
        Button("Remove \(device.name)", role: .destructive) { store.remove(device) }
      } message: { _ in
        Text("The credentials saved on this iPhone will be deleted. The TV won't be changed.")
      }
    }
  }

  /// Tapping a row selects the TV, and the info button edits it, as in Wi-Fi settings.
  private func row(for device: Device) -> some View {
    let isSelected = store.selectedID == device.id
    return HStack {
      Button {
        store.selectedID = device.id
      } label: {
        HStack(spacing: 12) {
          Image(systemName: "checkmark")
            .foregroundStyle(.tint)
            .opacity(isSelected ? 1 : 0)
            .accessibilityHidden(true)
          VStack(alignment: .leading) {
            Text(device.name)
              .foregroundStyle(.primary)
            Text("\(device.username)@\(device.host):\(String(device.port))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(isSelected ? .isSelected : [])
      Button("Edit \(device.name)", systemImage: "info.circle") { deviceToEdit = device }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }
  }

  private var isConfirmingRemoval: Binding<Bool> {
    Binding { deviceToRemove != nil } set: { if !$0 { deviceToRemove = nil } }
  }
}
