import SwiftUI
import Messages
import UIKit

/// Confirmation view for sending Cashu tokens via iMessage
struct MessageSendView: View {
    @ObservedObject var walletManager: WalletManager
    let amount: UInt64
    let sendMessage: (MSMessage) -> Void
    let onCancel: () -> Void

    @State private var selectedMintUrl: String = ""
    @State private var memo: String = ""
    @State private var availableMints: [String] = []
    @State private var mintBalances: [String: UInt64] = [:]
    @State private var isLoadingMints = true
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var selectedBalance: UInt64 {
        mintBalances[selectedMintUrl] ?? 0
    }

    private var hasInsufficientBalance: Bool {
        amount > selectedBalance
    }

    private var canSend: Bool {
        amount > 0 && !selectedMintUrl.isEmpty && !hasInsufficientBalance && !isLoading
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Amount header
                Text("Pay \(WalletManager.formatAmount(amount))")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                    .padding(.top, 8)

                // Mint selector
                if isLoadingMints {
                    ProgressView("Loading mints...")
                        .padding()
                } else if availableMints.isEmpty {
                    Text("No mints with balance")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("From")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Menu {
                            ForEach(availableMints, id: \.self) { mint in
                                Button(action: { selectedMintUrl = mint }) {
                                    HStack {
                                        Text(walletManager.getMintDisplayName(for: mint))
                                        Spacer()
                                        Text(WalletManager.formatAmount(mintBalances[mint] ?? 0))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "building.columns")
                                    .foregroundColor(.orange)
                                Text(walletManager.getMintDisplayName(for: selectedMintUrl))
                                    .foregroundColor(.primary)
                                Text("(\(WalletManager.formatAmount(selectedBalance)))")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                }

                // Insufficient balance warning
                if hasInsufficientBalance && !isLoadingMints {
                    Text("Insufficient balance")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                // Memo field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Note")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack {
                        Image(systemName: "text.bubble")
                            .foregroundColor(.gray)
                        TextField("Add a note...", text: $memo)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(8)
                }
                .padding(.horizontal)

                Spacer()

                // Send button
                Button(action: sendToken) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(isLoading ? "Sending..." : "Send \(WalletManager.formatAmount(amount))")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(canSend ? Color.orange : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(!canSend)
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .task {
            await loadMints()
        }
    }

    private func loadMints() async {
        isLoadingMints = true

        let mints = await walletManager.getMints()
        var balances: [String: UInt64] = [:]

        if let fetchedBalances = try? await walletManager.getMintBalances() {
            balances = fetchedBalances
        }

        // Filter to mints with balance >= amount
        let mintsWithBalance = mints.filter { (balances[$0] ?? 0) >= amount }

        await MainActor.run {
            self.availableMints = mintsWithBalance
            self.mintBalances = balances

            // Auto-select first mint with sufficient balance
            if !mintsWithBalance.isEmpty && selectedMintUrl.isEmpty {
                self.selectedMintUrl = mintsWithBalance[0]
            }

            self.isLoadingMints = false
        }
    }

    private func sendToken() {
        guard canSend else { return }

        isLoading = true

        Task {
            do {
                let token = try await walletManager.send(
                    mintUrl: selectedMintUrl,
                    amount: amount,
                    memo: memo.isEmpty ? nil : memo
                )

                let message = createTokenMessage(
                    token: token,
                    amount: amount,
                    memo: memo.isEmpty ? nil : memo
                )

                await MainActor.run {
                    isLoading = false
                    walletManager.refreshBalance()
                    sendMessage(message)
                }

            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func createTokenMessage(token: String, amount: UInt64, memo: String?) -> MSMessage {
        let message = MSMessage()
        let layout = MSMessageTemplateLayout()

        layout.caption = "Sent \(WalletManager.formatAmount(amount))"
        if let memo = memo, !memo.isEmpty {
            layout.subcaption = memo
        }

        // Generate dynamic image with amount
        layout.image = MessageBubbleImageGenerator.generateImage(amount: amount, type: .send)

        message.layout = layout
        message.url = URL(string: "data:cashu,\(token)")

        return message
    }
}
