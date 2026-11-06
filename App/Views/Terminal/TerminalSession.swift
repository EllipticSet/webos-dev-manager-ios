import Citadel
import Foundation
import NIOCore
import NIOSSH
import Observation
import SwiftTerm
import UIKit

/// One remote shell and the terminal view that shows it, kept alive across tab switches.
@MainActor
@Observable
final class TerminalSession: Identifiable {
  enum Status: Equatable {
    case connecting
    case connected
    case closed(String?)
  }

  let id = UUID()
  let title: String
  private(set) var status = Status.connecting
  private(set) var isDumb = false

  @ObservationIgnored let view: TerminalView
  @ObservationIgnored private let bridge = TerminalBridge()
  @ObservationIgnored private let service: DeviceService
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var writer: TTYStdinWriter?
  @ObservationIgnored private var client: SSHClient?

  init(title: String, service: DeviceService) {
    self.title = title
    self.service = service
    view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 500))
    view.terminalDelegate = bridge
    bridge.session = self
    start()
  }

  func start() {
    task?.cancel()
    status = .connecting
    isDumb = false
    task = Task { await run() }
  }

  func close() {
    task?.cancel()
    let client = client
    Task { try? await client?.close() }
  }

  private func run() async {
    do {
      let client = try await service.session.makeClient()
      self.client = client
      let terminal = view.getTerminal()
      let request = SSHChannelRequestEvent.PseudoTerminalRequest(
        wantReply: true, term: "xterm-256color", terminalCharacterWidth: terminal.cols,
        terminalRowHeight: terminal.rows, terminalPixelWidth: 0, terminalPixelHeight: 0,
        terminalModes: SSHTerminalModes([:]))
      var receivedOutput = false
      do {
        try await client.withPTY(request) { inbound, outbound in
          self.writer = outbound
          self.status = .connected
          for try await chunk in inbound {
            receivedOutput = true
            self.feed(chunk)
          }
        }
      } catch ChannelError.alreadyClosed {
        // The shell exited by itself, so there was nothing left for Citadel to close.
      } catch {
        // Developer Mode shells on some firmware refuse a PTY; use a plain shell like the desktop app.
        guard !receivedOutput, !Task.isCancelled else { throw error }
        isDumb = true
        feedLine("Basic terminal: this TV doesn't offer a full terminal.")
        do {
          try await client.withTTY { inbound, outbound in
            self.writer = outbound
            self.status = .connected
            for try await chunk in inbound { self.feed(chunk) }
          }
        } catch ChannelError.alreadyClosed {
        }
      }
      status = .closed(nil)
      try? await client.close()
    } catch is CancellationError {
      status = .closed(nil)
    } catch {
      status = .closed(DeviceError.message(for: error))
    }
    writer = nil
    client = nil
  }

  private func feed(_ chunk: ExecCommandOutput) {
    let data: ByteBuffer
    switch chunk {
    case .stdout(let buffer), .stderr(let buffer): data = buffer
    }
    var bytes = Array(data.data)
    if isDumb {
      bytes = bytes.flatMap { $0 == 0x0A ? [UInt8(0x0D), 0x0A] : [$0] }
    }
    view.feed(byteArray: bytes[...])
  }

  private func feedLine(_ text: String) {
    view.feed(text: text + "\r\n")
  }

  fileprivate func send(_ bytes: ArraySlice<UInt8>) {
    guard let writer else { return }
    var outgoing = Array(bytes)
    if isDumb {
      // A plain shell has no line discipline, so echo locally and send newlines.
      outgoing = outgoing.map { $0 == 0x0D ? 0x0A : $0 }
      view.feed(byteArray: outgoing.flatMap { $0 == 0x0A ? [UInt8(0x0D), 0x0A] : [$0] }[...])
    }
    Task { try? await writer.write(ByteBuffer(bytes: outgoing)) }
  }

  fileprivate func resize(cols: Int, rows: Int) {
    guard let writer, !isDumb else { return }
    Task { try? await writer.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0) }
  }
}

private final class TerminalBridge: TerminalViewDelegate {
  weak var session: TerminalSession?

  func send(source: TerminalView, data: ArraySlice<UInt8>) {
    MainActor.assumeIsolated { session?.send(data) }
  }

  func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
    MainActor.assumeIsolated { session?.resize(cols: newCols, rows: newRows) }
  }

  func setTerminalTitle(source: TerminalView, title: String) {}
  func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
  func scrolled(source: TerminalView, position: Double) {}
  func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
  func bell(source: TerminalView) {}
  func clipboardCopy(source: TerminalView, content: Data) {
    UIPasteboard.general.string = String(data: content, encoding: .utf8)
  }
  func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
  func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
