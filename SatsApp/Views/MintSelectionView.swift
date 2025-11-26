import SwiftUI

enum MintBrowserMode {
    case firstLaunch
    case addMint
}

struct MintBrowserView: View {
    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.dismiss) private var dismiss

    let mode: MintBrowserMode
    var onMintAdded: ((String) -> Void)?
    var onComplete: (() -> Void)?

    @State private var mints: [MintListItem] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var customMintUrl = ""
    @State private var isAddingMint = false
    @State private var addedMints: Set<String> = []
    @State private var existingMints: Set<String> = []
    @State private var errorMessage: String?
    @State private var showingError = false

    private var filteredMints: [MintListItem] {
        if searchText.isEmpty {
            return mints
        }
        return mints.filter { mint in
            mint.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if mode == .firstLaunch {
                firstLaunchView
            } else {
                addMintView
            }
        }
        .task {
            await loadExistingMints()
            await loadMints()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
    }

    // MARK: - First Launch View

    private var firstLaunchView: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)

                Text("Select a Mint")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Choose a Cashu mint to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 16)

            // Content
            mintListContent

            // Continue button
            if !addedMints.isEmpty {
                VStack(spacing: 8) {
                    Text("\(addedMints.count) mint\(addedMints.count == 1 ? "" : "s") added")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button(action: {
                        onComplete?()
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
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Add Mint View (pushed within existing navigation)

    private var addMintView: some View {
        mintListContent
            .navigationTitle("Add Mint")
            .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Shared Content

    private var mintListContent: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search mints...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if isLoading {
                Spacer()
                ProgressView("Loading mints...")
                Spacer()
            } else if let error = loadError {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadMints() }
                    }
                    .foregroundColor(.orange)
                }
                .padding()
                Spacer()
            } else {
                List {
                    // Mint list section
                    Section {
                        ForEach(filteredMints) { mint in
                            MintRowView(
                                mint: mint,
                                isAdded: existingMints.contains(mint.url) || addedMints.contains(mint.url),
                                isAdding: isAddingMint,
                                onAdd: {
                                    Task { await addMint(url: mint.url) }
                                }
                            )
                        }
                    }

                    // Custom mint section
                    Section(header: Text("Custom Mint")) {
                        HStack {
                            TextField("https://mint.example.com", text: $customMintUrl)
                                .textFieldStyle(PlainTextFieldStyle())
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
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
        }
    }

    // MARK: - Helpers

    private var isValidCustomUrl: Bool {
        guard let url = URL(string: customMintUrl) else { return false }
        return url.scheme == "https" || url.scheme == "http"
    }

    private func loadExistingMints() async {
        let mints = await walletManager.getMints()
        await MainActor.run {
            existingMints = Set(mints)
        }
    }

    private func loadMints() async {
        await MainActor.run {
            isLoading = true
            loadError = nil
        }

        do {
            let fetchedMints = try await MintDirectoryService.shared.fetchMints()
            await MainActor.run {
                mints = fetchedMints
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func addMint(url: String) async {
        await MainActor.run {
            isAddingMint = true
        }

        do {
            try await walletManager.addMint(mintUrl: url)
            await MainActor.run {
                addedMints.insert(url)
                isAddingMint = false
                onMintAdded?(url)

                // Dismiss immediately in addMint mode
                if mode == .addMint {
                    dismiss()
                }
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

// MARK: - Mint Row View

struct MintRowView: View {
    let mint: MintListItem
    let isAdded: Bool
    let isAdding: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            AsyncImage(url: mint.iconURL) { phase in
                switch phase {
                case .empty:
                    mintPlaceholder
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure:
                    mintPlaceholder
                @unknown default:
                    mintPlaceholder
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Name and description
            VStack(alignment: .leading, spacing: 2) {
                Text(mint.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let description = mint.displayDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Add button or checkmark
            if isAdded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            } else if isAdding {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.orange)
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .opacity(isAdded ? 0.6 : 1.0)
    }

    private var mintPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.2))
            Image(systemName: "bolt.fill")
                .foregroundColor(.orange)
        }
    }
}

// MARK: - Legacy Support (for ContentView compatibility)

struct MintSelectionView: View {
    var body: some View {
        MintBrowserView(mode: .firstLaunch)
    }
}

#Preview("First Launch") {
    MintBrowserView(mode: .firstLaunch)
        .environmentObject(WalletManager())
}

#Preview("Add Mint") {
    MintBrowserView(mode: .addMint)
        .environmentObject(WalletManager())
}
