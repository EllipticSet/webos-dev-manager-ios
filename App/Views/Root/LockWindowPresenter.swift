import SwiftUI
import UIKit

/// Shows the lock in its own window, because anything in the main window sits below open sheets.
@MainActor
final class LockWindowPresenter {
  private var window: UIWindow?

  func show(_ content: some View) {
    let controller = UIHostingController(rootView: content)
    // Keeps VoiceOver from reading the app behind the lock.
    controller.view.accessibilityViewIsModal = true
    // The lock can replace what's already showing, such as the cover for the app switcher.
    if let window {
      window.rootViewController = controller
      return
    }
    guard let scene = activeScene else { return }
    let window = UIWindow(windowScene: scene)
    window.windowLevel = .alert + 1
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
