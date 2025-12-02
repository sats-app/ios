import SwiftUI
import URKit
import URUI

enum AnimationSpeed: Int, CaseIterable {
    case slow = 0
    case medium = 1
    case fast = 2

    var interval: Double {
        switch self {
        case .fast: return 0.15
        case .medium: return 0.25
        case .slow: return 0.5
        }
    }

    var label: String {
        switch self {
        case .fast: return "F"
        case .medium: return "M"
        case .slow: return "S"
        }
    }

    var framesPerSecond: Double {
        1.0 / interval
    }

    func next() -> AnimationSpeed {
        AnimationSpeed(rawValue: (rawValue + 1) % 3) ?? .slow
    }
}

enum FragmentSize: Int, CaseIterable {
    case small = 0
    case medium = 1
    case large = 2

    var maxFragmentLen: Int {
        switch self {
        case .small: return 50
        case .medium: return 100
        case .large: return 150
        }
    }

    var label: String {
        switch self {
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        }
    }

    func next() -> FragmentSize {
        FragmentSize(rawValue: (rawValue + 1) % 3) ?? .small
    }
}

/// NUT-16 compliant animated QR code view using BC-UR (Blockchain Commons Uniform Resources)
/// Uses fountain codes for robust multi-part QR code transmission
struct AnimatedQRCodeView: View {
    let content: String

    @State private var speed: AnimationSpeed = .medium
    @State private var fragmentSize: FragmentSize = .medium

    var body: some View {
        VStack(spacing: 12) {
            // Inner view that gets recreated when fragmentSize changes
            AnimatedQRCodeInnerView(
                content: content,
                speed: $speed,
                maxFragmentLen: fragmentSize.maxFragmentLen
            )
            .id(fragmentSize.rawValue) // Force recreation when size changes

            // Stepper controls (shown below QR)
            stepperControls
        }
    }

    @ViewBuilder
    private var stepperControls: some View {
        HStack(spacing: 16) {
            // Speed toggle button
            Button(action: { speed = speed.next() }) {
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                    Text(speed.label)
                }
                .font(.caption.weight(.medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(6)
            }

            // Size toggle button
            Button(action: { fragmentSize = fragmentSize.next() }) {
                HStack(spacing: 4) {
                    Image(systemName: "qrcode")
                    Text(fragmentSize.label)
                }
                .font(.caption.weight(.medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(6)
            }
        }
    }
}

/// Inner view that handles URDisplayState lifecycle
private struct AnimatedQRCodeInnerView: View {
    let content: String
    @Binding var speed: AnimationSpeed
    let maxFragmentLen: Int

    @StateObject private var urDisplayState: URDisplayState

    init(content: String, speed: Binding<AnimationSpeed>, maxFragmentLen: Int) {
        self.content = content
        self._speed = speed
        self.maxFragmentLen = maxFragmentLen

        // Create UR from content
        let ur: UR
        do {
            guard let data = content.data(using: .utf8) else {
                ur = Self.dummyUR
                _urDisplayState = StateObject(wrappedValue: URDisplayState(ur: ur, maxFragmentLen: maxFragmentLen))
                return
            }
            ur = try UR(type: "bytes", cbor: data.cbor)
        } catch {
            ur = Self.dummyUR
        }
        _urDisplayState = StateObject(wrappedValue: URDisplayState(ur: ur, maxFragmentLen: maxFragmentLen))
    }

    private static var dummyUR: UR {
        try! UR(type: "bytes", cbor: Data(repeating: 0, count: 100).cbor)
    }

    var body: some View {
        VStack(spacing: 8) {
            // QR Code display
            ZStack {
                Color.white
                URQRCode(data: .constant(urDisplayState.part ?? Data()), foregroundColor: .black, backgroundColor: .white)
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Part indicator (only show for multi-part URs)
            if !urDisplayState.isSinglePart {
                let displayIndex = ((Int(urDisplayState.seqNum) - 1) % Int(urDisplayState.seqLen)) + 1
                Text("Part \(displayIndex) of \(urDisplayState.seqLen)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            urDisplayState.framesPerSecond = speed.framesPerSecond
            urDisplayState.run()
        }
        .onDisappear {
            urDisplayState.stop()
        }
        .onChange(of: speed) { newSpeed in
            urDisplayState.framesPerSecond = newSpeed.framesPerSecond
        }
    }
}

#Preview {
    AnimatedQRCodeView(
        content: "cashuAeyJ0b2tlbiI6W3sibWludCI6Imh0dHBzOi8vdGVzdG1pbnQuY2FzaHUuc3BhY2UiLCJwcm9vZnMiOlt7ImlkIjoiMDA5YTFmMjkzMjUzZTQxZSIsImFtb3VudCI6MSwic2VjcmV0IjoiNDA0MTdkNTBjNyIsIkMiOiIwMjM0NTY3ODkwYWJjZGVmIn1dfV19cashuAeyJ0b2tlbiI6W3sibWludCI6Imh0dHBzOi8vdGVzdG1pbnQuY2FzaHUuc3BhY2UiLCJwcm9vZnMiOlt7ImlkIjoiMDA5YTFmMjkzMjUzZTQxZSIsImFtb3VudCI6MSwic2VjcmV0IjoiNDA0MTdkNTBjNyIsIkMiOiIwMjM0NTY3ODkwYWJjZGVmIn1dfV19"
    )
    .frame(width: 280)
    .padding()
}
