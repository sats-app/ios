import SwiftUI
import URKit
import URUI

enum AnimationSpeed: Double, CaseIterable {
    case fast = 0.15
    case medium = 0.25
    case slow = 0.5

    var label: String {
        switch self {
        case .fast: return "Fast"
        case .medium: return "Medium"
        case .slow: return "Slow"
        }
    }

    var framesPerSecond: Double {
        1.0 / rawValue
    }
}

/// NUT-16 compliant animated QR code view using BC-UR (Blockchain Commons Uniform Resources)
/// Uses fountain codes for robust multi-part QR code transmission
struct AnimatedQRCodeView: View {
    let content: String

    @StateObject private var urDisplayState: URDisplayState
    @State private var speed: AnimationSpeed = .medium

    init(content: String) {
        self.content = content

        // Create UR from content
        let ur: UR
        do {
            guard let data = content.data(using: .utf8) else {
                ur = Self.dummyUR
                _urDisplayState = StateObject(wrappedValue: URDisplayState(ur: ur, maxFragmentLen: 200))
                return
            }
            ur = try UR(type: "bytes", cbor: data.cbor)
        } catch {
            ur = Self.dummyUR
        }
        _urDisplayState = StateObject(wrappedValue: URDisplayState(ur: ur, maxFragmentLen: 200))
    }

    private static var dummyUR: UR {
        try! UR(type: "bytes", cbor: Data(repeating: 0, count: 100).cbor)
    }

    var body: some View {
        VStack(spacing: 16) {
            // QR Code display
            ZStack {
                Color.white
                URQRCode(data: .constant(urDisplayState.part ?? Data()), foregroundColor: .black, backgroundColor: .white)
                    .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Part indicator (only show for multi-part URs)
            if !urDisplayState.isSinglePart {
                // seqNum is an ever-increasing fountain code counter, so we cycle it for display
                let displayIndex = ((Int(urDisplayState.seqNum) - 1) % Int(urDisplayState.seqLen)) + 1
                Text("Part \(displayIndex) of \(urDisplayState.seqLen)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Speed controls (only show for multi-part URs)
            if !urDisplayState.isSinglePart {
                HStack(spacing: 12) {
                    ForEach(AnimationSpeed.allCases, id: \.self) { speedOption in
                        Button(speedOption.label) {
                            speed = speedOption
                            urDisplayState.framesPerSecond = speedOption.framesPerSecond
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(speed == speedOption ? Color.orange : Color.gray.opacity(0.2))
                        .foregroundColor(speed == speedOption ? .white : .primary)
                        .cornerRadius(8)
                        .font(.caption)
                    }
                }
            }
        }
        .onAppear {
            urDisplayState.framesPerSecond = speed.framesPerSecond
            urDisplayState.run()
        }
        .onDisappear {
            urDisplayState.stop()
        }
    }
}

#Preview {
    AnimatedQRCodeView(
        content: "cashuAeyJ0b2tlbiI6W3sibWludCI6Imh0dHBzOi8vdGVzdG1pbnQuY2FzaHUuc3BhY2UiLCJwcm9vZnMiOlt7ImlkIjoiMDA5YTFmMjkzMjUzZTQxZSIsImFtb3VudCI6MSwic2VjcmV0IjoiNDA0MTdkNTBjNyIsIkMiOiIwMjM0NTY3ODkwYWJjZGVmIn1dfV19"
    )
    .frame(width: 200, height: 280)
}
