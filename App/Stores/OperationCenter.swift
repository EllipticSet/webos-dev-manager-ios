import Foundation
import Observation
import UIKit

/// Tracks the one long operation that can run at a time, and shows its progress and failures.
@MainActor
@Observable
final class OperationCenter {
  struct Activity: Identifiable {
    var id = UUID()
    var title: String
    var status: String = ""
    var fraction: Double?
  }

  struct Failure: Identifiable {
    var id = UUID()
    var title: String
    var message: String
  }

  var activity: Activity?
  var failure: Failure?
  private var task: Task<Void, Never>?
  private var didRunOutOfBackgroundTime = false

  typealias Progress = @Sendable (Double?, String) -> Void

  func run(_ title: String, operation: @escaping (@escaping Progress) async throws -> Void) {
    guard activity == nil else { return }
    activity = Activity(title: title)
    let id = activity?.id
    let background = BackgroundTime()
    // iOS only grants a short time, so an operation it can't finish fails with a clear reason.
    background.begin { [weak self] in
      self?.didRunOutOfBackgroundTime = true
      self?.cancel()
    }
    didRunOutOfBackgroundTime = false
    task = Task {
      defer { background.end() }
      let progress: Progress = { fraction, status in
        Task { @MainActor in
          guard self.activity?.id == id else { return }
          self.activity?.fraction = fraction
          self.activity?.status = status
        }
      }
      do {
        try await operation(progress)
      } catch {
        if didRunOutOfBackgroundTime {
          failure = Failure(
            title: title,
            message: "iOS stopped the operation because the app was in the background. Keep the app open until it finishes.")
        } else if !(error is CancellationError), !Task.isCancelled {
          failure = Failure(title: title, message: DeviceError.message(for: error))
        }
      }
      activity = nil
    }
  }

  func cancel() {
    task?.cancel()
  }
}

/// The extra time iOS grants to finish work after the app leaves the screen.
@MainActor
private final class BackgroundTime {
  private var identifier = UIBackgroundTaskIdentifier.invalid

  func begin(onExpiration: @escaping @MainActor () -> Void) {
    identifier = UIApplication.shared.beginBackgroundTask(withName: "Device operation") { [weak self] in
      MainActor.assumeIsolated {
        onExpiration()
        self?.end()
      }
    }
  }

  func end() {
    guard identifier != .invalid else { return }
    UIApplication.shared.endBackgroundTask(identifier)
    identifier = .invalid
  }
}
