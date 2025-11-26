import SwiftUI

struct MintSelectionView: View {
    @EnvironmentObject var walletManager: WalletManager
    @State private var customMintUrl = ""
    @State private var isAddingMint = false
    @State private var addedMints: [String] = []
    @State private var errorMessage: String?
    @State private var showingError = false

    // Popular mints for quick selection
    private let popularMints = [
        ("Minibits", "https://mint.minibits.cash/Bitcoin"),
        ("eNuts", "https://mint.enuts.cash"),
        ("Coinos", "https://cashu.coinos.io"),
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)

                    Text("Select a Mint")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Choose at least one Cashu mint to get started. You can add more later.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 32)

                // iCloud status indicator
                if walletManager.isUsingICloud {
                    HStack {
                        Image(systemName: "icloud.fill")
                            .foregroundColor(.blue)
                        Text("Wallet synced with iCloud")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                } else {
                    HStack {
                        Image(systemName: "iphone")
                            .foregroundColor(.secondary)
                        Text("Wallet stored locally")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }

                // Popular mints
                VStack(alignment: .leading, spacing: 12) {
                    Text("Popular Mints")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(popularMints, id: \.1) { name, url in
                        Button(action: {
                            Task {
                                await addMint(url: url)
                            }
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(url)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if addedMints.contains(url) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                } else if isAddingMint {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(.orange)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .disabled(isAddingMint || addedMints.contains(url))
                        .padding(.horizontal)
                    }
                }

                // Custom mint URL
                VStack(alignment: .leading, spacing: 8) {
                    Text("Or add a custom mint")
                        .font(.headline)
                        .padding(.horizontal)

                    HStack {
                        TextField("https://mint.example.com", text: $customMintUrl)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                            .disabled(isAddingMint)

                        Button(action: {
                            Task {
                                await addMint(url: customMintUrl)
                                customMintUrl = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(isValidCustomUrl ? .orange : .gray)
                        }
                        .disabled(!isValidCustomUrl || isAddingMint)
                    }
                    .padding(.horizontal)
                }

                Spacer()

                // Added mints summary
                if !addedMints.isEmpty {
                    VStack(spacing: 8) {
                        Text("\(addedMints.count) mint\(addedMints.count == 1 ? "" : "s") added")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Button(action: {
                            walletManager.completeMintSelection()
                        }) {
                            Text("Continue")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.bottom, 32)
            .navigationBarHidden(true)
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
        }
    }

    private var isValidCustomUrl: Bool {
        guard let url = URL(string: customMintUrl) else { return false }
        return url.scheme == "https" || url.scheme == "http"
    }

    private func addMint(url: String) async {
        isAddingMint = true

        do {
            try await walletManager.addMint(mintUrl: url)
            await MainActor.run {
                addedMints.append(url)
                isAddingMint = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to add mint: \(error.localizedDescription)"
                showingError = true
                isAddingMint = false
            }
        }
    }
}

#Preview {
    MintSelectionView()
        .environmentObject(WalletManager())
}
