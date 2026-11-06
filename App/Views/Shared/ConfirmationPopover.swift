import SwiftUI

extension View {
  /// A confirmation shown in a popover pointing at this view from `arrowEdge`, which a
  /// `confirmationDialog` can't choose. Tapping outside cancels.
  func confirmationPopover(
    _ title: String, isPresented: Binding<Bool>, arrowEdge: Edge, message: String,
    actionTitle: String, role: ButtonRole? = nil, action: @escaping () -> Void
  ) -> some View {
    popover(isPresented: isPresented, arrowEdge: arrowEdge) {
      ConfirmationPopoverContent(
        title: title, message: message, actionTitle: actionTitle, role: role
      ) {
        isPresented.wrappedValue = false
        action()
      }
      .presentationCompactAdaptation(.popover)
    }
  }
}

private struct ConfirmationPopoverContent: View {
  var title: String
  var message: String
  var actionTitle: String
  var role: ButtonRole?
  var action: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.headline)
        Text(message)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      // A neutral platter, like a confirmation dialog's, with the label in the action's color.
      Button(role: role, action: action) {
        Text(actionTitle)
          .font(.body.weight(.medium))
          .foregroundStyle(role == .destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
          .padding(.vertical, 14)
          .frame(maxWidth: .infinity)
          .background(.fill.tertiary, in: .capsule)
      }
      .buttonStyle(.plain)
    }
    .padding(20)
    .frame(width: 280)
  }
}
