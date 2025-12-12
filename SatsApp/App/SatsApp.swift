import SwiftUI

@main
struct SatsApp: App {
    @StateObject private var walletManager = WalletManager()
    @State private var pendingToken: String?
    @State private var showReceiveSheet = false
    @State private var receiveAmount: UInt64 = 0
    @State private var receiveError: String?
    @State private var isReceiving = false

    // Trust alert state for untrusted mint tokens
    @State private var showingTrustAlert = false
    @State private var pendingTokenDetails: TokenDetails?
    @State private var defaultMintName: String = ""

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
                .alert("Trust This Mint?", isPresented: $showingTrustAlert) {
                    Button("Cancel", role: .cancel) {
                        pendingTokenDetails = nil
                    }
                    Button("Trust Mint") {
                        if let details = pendingTokenDetails {
                            receiveWithTrust(details, trustMint: true)
                        }
                    }
                    if !defaultMintName.isEmpty {
                        Button("Transfer to \(defaultMintName)") {
                            if let details = pendingTokenDetails {
                                receiveWithTrust(details, trustMint: false)
                            }
                        }
                    }
                } message: {
                    if let details = pendingTokenDetails {
                        let mintHost = URL(string: details.mintUrl)?.host ?? details.mintUrl
                        let amount = WalletManager.formatAmount(details.amount)
                        Text("This token (\(amount)) is from \(mintHost). Trust this mint to receive directly, or transfer to your default mint.")
                    }
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
        Task {
            do {
                // Parse the token to get mint URL and amount
                let (mintUrl, amount) = try await walletManager.parseToken(tokenString: token)

                // Check if the mint is already trusted
                let isTrusted = await walletManager.isMintTrusted(mintUrl: mintUrl)

                if isTrusted {
                    // Mint is trusted, proceed with normal receive
                    await MainActor.run {
                        isReceiving = true
                        receiveError = nil
                        showReceiveSheet = true
                    }

                    let receivedAmount = try await walletManager.receive(tokenString: token)
                    await MainActor.run {
                        receiveAmount = receivedAmount
                        isReceiving = false
                        walletManager.refreshBalance()
                    }
                } else {
                    // Mint is not trusted, show trust alert
                    let defaultMint = await walletManager.getDefaultMint()
                    let mintName = defaultMint.map { walletManager.getMintDisplayName(for: $0) } ?? ""

                    await MainActor.run {
                        pendingTokenDetails = TokenDetails(tokenString: token, mintUrl: mintUrl, amount: amount)
                        defaultMintName = mintName
                        showingTrustAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    receiveError = error.localizedDescription
                    isReceiving = false
                    showReceiveSheet = true
                }
            }
        }
    }

    private func receiveWithTrust(_ details: TokenDetails, trustMint: Bool) {
        isReceiving = true
        receiveError = nil
        showReceiveSheet = true
        pendingToken = details.tokenString
        pendingTokenDetails = nil

        Task {
            do {
                let amount = try await walletManager.receiveToken(
                    tokenString: details.tokenString,
                    trustMint: trustMint
                )
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
