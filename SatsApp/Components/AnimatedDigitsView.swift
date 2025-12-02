import SwiftUI

/// Displays a number with individual digit roll animations (odometer effect)
struct AnimatedDigitsView: View {
    let value: String
    let font: Font
    let color: Color

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(value.enumerated()), id: \.offset) { index, char in
                if char.isNumber {
                    SingleDigitView(
                        digit: Int(String(char)) ?? 0,
                        font: font,
                        color: color
                    )
                } else {
                    // Non-digit characters (commas, Bitcoin symbol, etc.) don't animate
                    Text(String(char))
                        .font(font)
                        .foregroundColor(color)
                }
            }
        }
    }
}

/// A single digit that animates with a rolling effect when the value changes
private struct SingleDigitView: View {
    let digit: Int
    let font: Font
    let color: Color

    @State private var digitHeight: CGFloat = 0

    var body: some View {
        Text("0")
            .font(font)
            .foregroundColor(.clear)
            .overlay(
                Group {
                    if digitHeight > 0 {
                        // Only show animated stack once we have a valid height
                        VStack(spacing: 0) {
                            ForEach(0..<10, id: \.self) { num in
                                Text("\(num)")
                                    .font(font)
                                    .foregroundColor(color)
                                    .frame(height: digitHeight)
                            }
                        }
                        .offset(y: -CGFloat(digit) * digitHeight)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: digit)
                    } else {
                        // Show static digit until height is measured
                        Text("\(digit)")
                            .font(font)
                            .foregroundColor(color)
                    }
                }
            )
            .clipped()
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear {
                        digitHeight = geo.size.height
                    }
                }
            )
    }
}

#Preview {
    VStack(spacing: 20) {
        AnimatedDigitsView(
            value: "\u{20BF}1,234",
            font: .system(size: 48, weight: .light),
            color: .orange
        )

        AnimatedDigitsView(
            value: "\u{20BF}99,999",
            font: .system(size: 48, weight: .light),
            color: .orange
        )
    }
    .padding()
}
