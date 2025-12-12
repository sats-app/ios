import SwiftUI

/// Compact number pad for entering amounts in the iMessage extension
struct MessageNumberPad: View {
    @Binding var amount: String

    private let buttons = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "\u{232B}"]
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(buttons, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { button in
                        Button(action: {
                            handleButtonPress(button)
                        }) {
                            Text(button)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(Color.clear)
                        }
                        .disabled(button.isEmpty)
                    }
                }
            }
        }
    }

    private func handleButtonPress(_ button: String) {
        switch button {
        case "\u{232B}":
            // Backspace
            if !amount.isEmpty && amount != "0" {
                amount = String(amount.dropLast())
                if amount.isEmpty {
                    amount = "0"
                }
            }
        case "0":
            // Don't add leading zeros
            if amount != "0" {
                amount += button
            }
        default:
            // Add digit
            if amount == "0" {
                amount = button
            } else {
                // Limit to reasonable amount (10 digits)
                if amount.count < 10 {
                    amount += button
                }
            }
        }
    }
}
