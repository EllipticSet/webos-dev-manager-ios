import SwiftUI

/// Progress dots and a number pad for entering a passcode.
struct PasscodePad: View {
  @Binding var entered: String
  var isDisabled = false
  var onComplete: (String) -> Void

  private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

  var body: some View {
    VStack(spacing: 28) {
      HStack(spacing: 16) {
        ForEach(0..<PasscodeRecord.length, id: \.self) { index in
          Circle()
            .fill(index < entered.count ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
            .frame(width: 14, height: 14)
        }
      }
      .accessibilityElement()
      .accessibilityLabel("\(entered.count) of \(PasscodeRecord.length) digits entered")

      VStack(spacing: 14) {
        ForEach(rows, id: \.self) { row in
          HStack(spacing: 22) {
            ForEach(row, id: \.self) { digit in key(digit) }
          }
        }
        HStack(spacing: 22) {
          Color.clear.frame(width: 76, height: 76)
          key("0")
          Button("Delete", systemImage: "delete.left") {
            if !entered.isEmpty { entered.removeLast() }
          }
          .labelStyle(.iconOnly)
          .font(.title2)
          .frame(width: 76, height: 76)
          .contentShape(.circle)
          .disabled(entered.isEmpty)
        }
      }
      .disabled(isDisabled)
      .opacity(isDisabled ? 0.4 : 1)
    }
  }

  private func key(_ digit: String) -> some View {
    Button {
      guard entered.count < PasscodeRecord.length else { return }
      entered.append(digit)
      if entered.count == PasscodeRecord.length { onComplete(entered) }
    } label: {
      Text(digit)
        .font(.title.weight(.medium))
        .foregroundStyle(.primary)
        .frame(width: 76, height: 76)
        .background(.quaternary, in: .circle)
    }
    .buttonStyle(.plain)
  }
}
