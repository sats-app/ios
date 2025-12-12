import SwiftUI
import LocalAuthentication

struct SeedPhraseView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep: Step = .warning
    @State private var hasAcknowledgedWarning = false
    @State private var seedPhrase: String?
    @State private var showCopyConfirmation = false
    @State private var authError: String?
    @State private var timeRemaining: Int = 60

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private enum Step {
        case warning
        case authenticating
        case display
    }

    var body: some View {
        NavigationStack {
            Group {
                switch currentStep {
                case .warning:
                    warningView
                case .authenticating:
                    authenticatingView
                case .display:
                    seedPhraseDisplayView
                }
            }
            .navigationTitle("Seed Phrase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.orange)
                    }
                }
            }
        }
    }

    // MARK: - Warning View

    private var warningView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Backup Your Wallet")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 16) {
                WarningRow(
                    icon: "key.fill",
                    text: "Your seed phrase is the master key to your wallet"
                )
                WarningRow(
                    icon: "eye.slash.fill",
                    text: "Never share it with anyone, including support"
                )
                WarningRow(
                    icon: "doc.text.fill",
                    text: "Write it down on paper and store securely"
                )
                WarningRow(
                    icon: "xmark.shield.fill",
                    text: "Anyone with these words can steal your funds"
                )
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 16) {
                Button {
                    hasAcknowledgedWarning.toggle()
                } label: {
                    HStack {
                        Image(systemName: hasAcknowledgedWarning ? "checkmark.square.fill" : "square")
                            .foregroundColor(hasAcknowledgedWarning ? .orange : .secondary)
                        Text("I understand the risks")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                Button("Continue") {
                    currentStep = .authenticating
                    authenticateUser()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!hasAcknowledgedWarning)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }

    // MARK: - Authenticating View

    private var authenticatingView: some View {
        VStack(spacing: 24) {
            Spacer()

            if let error = authError {
                Image(systemName: "faceid")
                    .font(.system(size: 60))
                    .foregroundColor(.red)

                Text("Authentication Failed")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    Button("Try Again") {
                        authError = nil
                        authenticateUser()
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            } else {
                ProgressView()
                    .scaleEffect(1.5)

                Text("Authenticating...")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Spacer()
            }
        }
    }

    // MARK: - Seed Phrase Display View

    private var seedPhraseDisplayView: some View {
        VStack(spacing: 16) {
            // Timer warning
            HStack {
                Image(systemName: "timer")
                    .foregroundColor(.orange)
                Text("Auto-hide in \(timeRemaining)s")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top)

            if let phrase = seedPhrase {
                let words = phrase.split(separator: " ").map(String.init)

                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                            WordCell(index: index + 1, word: word)
                        }
                    }
                    .padding()
                }
                .privacySensitive()

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = phrase
                        showCopyConfirmation = true

                        // Clear clipboard after 60 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                            if UIPasteboard.general.string == phrase {
                                UIPasteboard.general.string = ""
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: showCopyConfirmation ? "checkmark" : "doc.on.doc")
                            Text(showCopyConfirmation ? "Copied!" : "Copy to Clipboard")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button("Done") {
                        seedPhrase = nil
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            } else {
                Spacer()
                Text("Failed to load seed phrase")
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .onReceive(timer) { _ in
            if currentStep == .display {
                if timeRemaining > 0 {
                    timeRemaining -= 1
                } else {
                    seedPhrase = nil
                    dismiss()
                }
            }
        }
    }

    // MARK: - Authentication

    private func authenticateUser() {
        let context = LAContext()
        var error: NSError?

        // Check if biometric authentication is available
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            AppLogger.auth.warning("Authentication not available: \(error?.localizedDescription ?? "unknown")")
            authError = "Authentication is not available on this device."
            return
        }

        Task {
            do {
                let success = try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Authenticate to view your seed phrase"
                )

                await MainActor.run {
                    if success {
                        loadSeedPhrase()
                    } else {
                        authError = "Authentication was not successful."
                    }
                }
            } catch {
                await MainActor.run {
                    AppLogger.auth.error("Authentication failed: \(error.localizedDescription)")
                    authError = error.localizedDescription
                }
            }
        }
    }

    private func loadSeedPhrase() {
        do {
            seedPhrase = try StorageManager.shared.loadMnemonic()
            currentStep = .display
            AppLogger.settings.info("Seed phrase loaded for display")
        } catch {
            AppLogger.settings.error("Failed to load seed phrase: \(error.localizedDescription)")
            authError = "Failed to load seed phrase: \(error.localizedDescription)"
        }
    }
}

// MARK: - Supporting Views

private struct WarningRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.orange)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()
        }
    }
}

private struct WordCell: View {
    let index: Int
    let word: String

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .trailing)

            Text(word)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.theme.surface)
        .cornerRadius(8)
    }
}

#Preview {
    SeedPhraseView()
}
