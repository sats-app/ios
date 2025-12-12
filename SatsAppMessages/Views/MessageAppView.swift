import SwiftUI
import Messages

/// Main container view for the iMessage extension
struct MessageAppView: View {
    @ObservedObject var walletManager: WalletManager
    let isWalletReady: Bool
    let sendMessage: (MSMessage) -> Void
    let requestExpanded: () -> Void
    let requestCompact: () -> Void

    @State private var amount: String = "0"
    @State private var showingSendConfirm = false
    @State private var showingRequestConfirm = false

    private var amountValue: UInt64 {
        UInt64(amount) ?? 0
    }

    private var canProceed: Bool {
        amountValue > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isWalletReady {
                walletNotReadyView
            } else {
                mainView
            }
        }
        .background(Color(UIColor.systemBackground))
        .sheet(isPresented: $showingSendConfirm) {
            MessageSendView(
                walletManager: walletManager,
                amount: amountValue,
                sendMessage: { message in
                    sendMessage(message)
                    showingSendConfirm = false
                    amount = "0"
                    requestCompact()
                },
                onCancel: {
                    showingSendConfirm = false
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingRequestConfirm) {
            MessageRequestView(
                walletManager: walletManager,
                amount: amountValue,
                sendMessage: { message in
                    sendMessage(message)
                    showingRequestConfirm = false
                    amount = "0"
                    requestCompact()
                },
                onCancel: {
                    showingRequestConfirm = false
                }
            )
            .presentationDetents([.medium])
        }
    }

    private var mainView: some View {
        VStack(spacing: 8) {
            // Amount display
            Text("\u{20BF}\(amount)")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.orange)
                .padding(.top, 8)

            // Compact number pad
            MessageNumberPad(amount: $amount)
                .padding(.horizontal, 24)

            // Two action buttons
            HStack(spacing: 12) {
                Button(action: {
                    if canProceed {
                        requestExpanded()
                        showingRequestConfirm = true
                    }
                }) {
                    Text("Request")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(canProceed ? Color.orange : Color.gray.opacity(0.5))
                        .cornerRadius(10)
                }
                .disabled(!canProceed)

                Button(action: {
                    if canProceed {
                        requestExpanded()
                        showingSendConfirm = true
                    }
                }) {
                    Text("Pay")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(canProceed ? Color.orange : Color.gray.opacity(0.5))
                        .cornerRadius(10)
                }
                .disabled(!canProceed)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    private var walletNotReadyView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "wallet.pass")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text("Wallet Not Set Up")
                .font(.headline)
                .foregroundColor(.primary)

            Text("Open SatsApp to set up your wallet first.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }
}
