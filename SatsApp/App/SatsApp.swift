import SwiftUI

@main
struct SatsApp: App {
    @StateObject private var walletManager = WalletManager()
    @State private var pendingToken: String?
    @State private var showReceiveSheet = false
    @State private var receiveAmount: UInt64 = 0
    @State private var receiveError: String?
    @State private var isReceiving = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(walletManager)
                .task {
                    await walletManager.initializeWallet()
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .sheet(isPresented: $showReceiveSheet) {
                    URLReceiveSheet(
                        walletManager: walletManager,
                        token: pendingToken ?? "",
                        amount: receiveAmount,
                        error: receiveError,
                        isReceiving: isReceiving
                    )
                }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "cashu" else { return }

        AppLogger.network.info("Received URL: \(url.absoluteString)")

        if url.host == "receive",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let tokenItem = components.queryItems?.first(where: { $0.name == "token" }),
           let token = tokenItem.value?.removingPercentEncoding {
            pendingToken = token
            receiveToken(token)
        }
    }

    private func receiveToken(_ token: String) {
        isReceiving = true
        receiveError = nil
        showReceiveSheet = true

        Task {
            do {
                let amount = try await walletManager.receive(tokenString: token)
                await MainActor.run {
                    receiveAmount = amount
                    isReceiving = false
                    walletManager.refreshBalance()
                }
            } catch {
                await MainActor.run {
                    receiveError = error.localizedDescription
                    isReceiving = false
                }
            }
        }
    }
}

// MARK: - URL Receive Sheet

struct URLReceiveSheet: View {
    let walletManager: WalletManager
    let token: String
    let amount: UInt64
    let error: String?
    let isReceiving: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            if isReceiving {
                receivingView
            } else if let error = error {
                errorView(error)
            } else {
                successView
            }
        }
        .padding()
    }

    private var receivingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Receiving...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 40)
    }

    private var successView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
            }

            Text("Received!")
                .font(.title2)
                .fontWeight(.semibold)

            Text(WalletManager.formatAmount(amount))
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 20)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                dismiss()
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
            }

            Text("Failed to Receive")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Dismiss") {
                dismiss()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.gray.opacity(0.1))
            .foregroundColor(.primary)
            .cornerRadius(12)
            .font(.headline)
        }
        .padding(.vertical, 20)
    }
}
