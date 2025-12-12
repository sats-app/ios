import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var walletManager: WalletManager
    @StateObject private var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var mints: [String] = []
    @State private var isLoadingMints = true
    @State private var showingSeedPhrase = false

    var body: some View {
        NavigationStack {
            List {
                walletSection
                displaySection
                securitySection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
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
        .task {
            await loadMints()
        }
        .sheet(isPresented: $showingSeedPhrase) {
            SeedPhraseView()
        }
    }

    // MARK: - Wallet Section

    private var walletSection: some View {
        Section {
            // Default Mint Picker
            if isLoadingMints {
                HStack {
                    Text("Default Mint")
                    Spacer()
                    ProgressView()
                }
            } else if mints.isEmpty {
                HStack {
                    Text("Default Mint")
                    Spacer()
                    Text("No mints")
                        .foregroundColor(.secondary)
                }
            } else {
                Picker("Default Mint", selection: defaultMintBinding) {
                    Text("None")
                        .tag(String?.none)

                    ForEach(mints, id: \.self) { mintUrl in
                        Text(walletManager.getMintDisplayName(for: mintUrl))
                            .tag(String?.some(mintUrl))
                    }
                }
                .tint(.orange)
            }
        } header: {
            Text("Wallet")
        }
    }

    private var defaultMintBinding: Binding<String?> {
        Binding(
            get: {
                // Only return the stored value if it's still valid
                if let stored = settings.defaultMintUrl, mints.contains(stored) {
                    return stored
                }
                return nil
            },
            set: { newValue in
                settings.defaultMintUrl = newValue
                AppLogger.settings.info("Default mint set to: \(newValue ?? "none")")
            }
        )
    }

    // MARK: - Security Section

    private var securitySection: some View {
        Section {
            Button {
                showingSeedPhrase = true
            } label: {
                HStack {
                    Text("View Seed Phrase")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Security")
        } footer: {
            Text("Your seed phrase is the only way to recover your wallet. Keep it safe and never share it.")
        }
    }

    // MARK: - Display Section

    private var displaySection: some View {
        Section {
            Toggle("Hide Balance", isOn: $settings.hideBalance)
                .tint(.orange)
        } header: {
            Text("Display")
        } footer: {
            Text("When enabled, your balance will be hidden from the main screen.")
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Build")
                Spacer()
                Text(buildNumber)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Helpers

    private func loadMints() async {
        isLoadingMints = true
        mints = await walletManager.getMints()

        // Validate the current default mint
        settings.validateDefaultMint(against: mints)

        isLoadingMints = false
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
}

#Preview {
    SettingsView()
        .environmentObject(WalletManager())
}
