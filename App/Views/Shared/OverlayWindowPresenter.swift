import SwiftUI
import UIKit

/// Shows content in its own window, such as the lock or a confirmation, because anything in the
/// main window sits below open sheets.
@MainActor
final class OverlayWindowPresenter {
  private let level: UIWindow.Level
  private var window: UIWindow?

  init(level: UIWindow.Level = .alert + 1) {
    self.level = level
  }

  func show(_ content: some View) {
    let controller = UIHostingController(rootView: content)
    controller.view.backgroundColor = .clear
    // Keeps VoiceOver from reading the app behind the content.
    controller.view.accessibilityViewIsModal = true
    // The content can replace what's already showing, such as the lock replacing the cover for
    // the app switcher.
    if let window {
      window.rootViewController = controller
      return
    }
    guard let scene = activeScene else { return }
    let window = UIWindow(windowScene: scene)
    window.windowLevel = level
    window.backgroundColor = .clear
    window.rootViewController = controller
    window.makeKeyAndVisible()
    self.window = window
  }

  func hide() {
    guard let window else { return }
    window.isHidden = true
    self.window = nil
    window.windowScene?.windows.first { $0 !== window }?.makeKey()
  }

  private var activeScene: UIWindowScene? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
  }
}
