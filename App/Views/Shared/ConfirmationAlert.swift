import SwiftUI

extension View {
  /// A confirmation with Cancel and one action. It's a system alert, except while iPhone Duo is
  /// partially folded: system alerts then go to the leading or bottom half, so an alert of the
  /// app's own shows it on the trailing or top half instead, as the progress panel does.
  func confirmationAlert<Item>(
    _ title: @escaping (Item) -> LocalizedStringResource, presenting item: Binding<Item?>,
    message: @escaping (Item) -> LocalizedStringResource? = { _ in nil }, actionTitle: LocalizedStringResource,
    role: ButtonRole? = nil, action: @escaping (Item) -> Void
  ) -> some View {
    modifier(
      ConfirmationAlertModifier(
        item: item, title: title, message: message, actionTitle: actionTitle, role: role,
        action: action))
  }

  func confirmationAlert(
    _ title: LocalizedStringResource, isPresented: Binding<Bool>, message: LocalizedStringResource? = nil, actionTitle: LocalizedStringResource,
    role: ButtonRole? = nil, action: @escaping () -> Void
  ) -> some View {
    let item = Binding<Bool?> { isPresented.wrappedValue ? true : nil } set: {
      isPresented.wrappedValue = $0 != nil
    }
    return confirmationAlert(
      { _ in title }, presenting: item, message: { _ in message }, actionTitle: actionTitle,
      role: role
    ) { _ in action() }
  }

  /// A message with only OK, placed like `confirmationAlert` on iPhone Duo.
  func noticeAlert<Item>(
    _ title: @escaping (Item) -> LocalizedStringResource, presenting item: Binding<Item?>,
    message: @escaping (Item) -> LocalizedStringResource
  ) -> some View {
    modifier(
      ConfirmationAlertModifier(
        item: item, title: title, message: message, actionTitle: nil, role: nil
      ) { _ in })
  }
}

private struct ConfirmationAlertModifier<Item>: ViewModifier {
  @Binding var item: Item?
  var title: (Item) -> LocalizedStringResource
  var message: (Item) -> LocalizedStringResource?
  /// Without one, the alert only has OK.
  var actionTitle: LocalizedStringResource?
  var role: ButtonRole?
  var action: (Item) -> Void

  @Environment(\.isPartiallyFolded) private var isPartiallyFolded
  @Environment(AppSettings.self) private var settings
  /// What the alert shows while it closes, after `item` is cleared.
  @State private var shown: Item?
  @State private var window = OverlayWindowPresenter(level: .alert)

  func body(content: Content) -> some View {
    content
      .alert(
        Text(shown.map(title) ?? ""), isPresented: isShowingSystemAlert, presenting: shown
      ) { shown in
        if let actionTitle {
          Button(role: role) { action(shown) } label: { Text(actionTitle) }
          Button("Cancel", role: .cancel) {}
        } else {
          Button("OK", role: .cancel) {}
        }
      } message: { shown in
        if let message = message(shown) { Text(message) }
      }
      .onChange(of: item != nil, initial: true) { _, isPresented in
        if isPresented { shown = item }
        updateWindow()
      }
      .onChange(of: isPartiallyFolded) { updateWindow() }
      .onDisappear { window.hide() }
  }

  private var isShowingSystemAlert: Binding<Bool> {
    Binding { item != nil && !isPartiallyFolded } set: { if !$0 { item = nil } }
  }

  private func updateWindow() {
    guard let item, isPartiallyFolded else { return window.hide() }
    window.show(
      FoldAwareAlert(
        title: title(item), message: message(item), actionTitle: actionTitle, role: role
      ) { confirmed in
        window.hide()
        self.item = nil
        if confirmed { action(item) }
      }
      .tint(settings.accent))
  }
}

private struct FoldAwareAlert: View {
  var title: LocalizedStringResource
  var message: LocalizedStringResource?
  var actionTitle: LocalizedStringResource?
  var role: ButtonRole?
  var onFinish: (_ confirmed: Bool) -> Void

  var body: some View {
    ZStack {
      Color.black.opacity(0.2)
        .ignoresSafeArea()
        .accessibilityHidden(true)
      GeometryReader { proxy in
        panel
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(.offFold(in: proxy))
          .animation(.smooth, value: EdgeInsets.offFold(in: proxy))
      }
      .ignoresSafeArea()
    }
  }

  private var panel: some View {
    VStack(spacing: 20) {
      VStack(spacing: 6) {
        Text(title)
          .font(.headline)
        if let message {
          Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isHeader)
      // Side by side when both labels fit, stacked with the action first otherwise, as in an alert.
      if let actionTitle {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 12) {
            cancelButton
            actionButton(actionTitle)
          }
          VStack(spacing: 12) {
            actionButton(actionTitle)
            cancelButton
          }
        }
      } else {
        alertButton("OK", style: AnyShapeStyle(.tint)) { onFinish(false) }
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(maxWidth: 300)
    .glassEffect(.regular, in: .rect(cornerRadius: 32))
    .padding()
  }

  private var cancelButton: some View {
    alertButton("Cancel", style: AnyShapeStyle(.tint)) { onFinish(false) }
      .keyboardShortcut(.cancelAction)
  }

  private func actionButton(_ title: LocalizedStringResource) -> some View {
    let style = role == .destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.tint)
    return alertButton(title, style: style) { onFinish(true) }
      .keyboardShortcut(.defaultAction)
  }

  /// A neutral platter with the label in the button's color, like a system alert's buttons.
  private func alertButton(_ label: LocalizedStringResource, style: AnyShapeStyle, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Text(label)
        .font(.body.weight(.medium))
        .foregroundStyle(style)
        .lineLimit(1)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(.fill.tertiary, in: .capsule)
    }
    .buttonStyle(.plain)
  }
}
