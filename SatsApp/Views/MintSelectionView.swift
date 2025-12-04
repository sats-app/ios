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
    @State private var isAddingMint = false
    @State private var addedMints: Set<String> = []
    @State private var existingMints: Set<String> = []
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var mintToConfirm: MintListItem?
    @State private var showingTrustConfirmation = false

    // Custom mint lookup state
    @State private var customMint: MintListItem?
    @State private var isLoadingCustomMint = false
    @State private var customMintLookupTask: Task<Void, Never>?

    private var searchIsUrl: Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme,
              (scheme == "https" || scheme == "http"),
              let host = url.host,
              host.contains("."),
              host.count > 4  // minimum like "a.bc"
        else { return false }
        return true
    }

    private var filteredMints: [MintListItem] {
        if searchText.isEmpty {
            return mints
        }
        // When searching by URL, only show custom mint result (handled separately)
        if searchIsUrl {
            return []
        }
        // Text search: match on name, description, or URL
        return mints.filter { mint in
            mint.displayName.localizedCaseInsensitiveContains(searchText) ||
            mint.displayDescription?.localizedCaseInsensitiveContains(searchText) == true ||
            mint.url.localizedCaseInsensitiveContains(searchText)
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
        .onChange(of: searchText) { newValue in
            lookupCustomMint(url: newValue)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .alert("Trust This Mint?", isPresented: $showingTrustConfirmation, presenting: mintToConfirm) { mint in
            Button("Cancel", role: .cancel) {
                mintToConfirm = nil
            }
            Button("Add Mint") {
                Task { await addMint(url: mint.url) }
                mintToConfirm = nil
            }
        } message: { mint in
            Text("Adding \(mint.displayName) means trusting it to hold your funds. Only add mints you trust.")
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
                TextField("Search or enter mint URL...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                    .disableAutocorrection(true)
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
                    Section {
                        // Show custom mint result when searching by URL
                        if searchIsUrl {
                            if isLoadingCustomMint {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            } else if let mint = customMint {
                                let isAdded = existingMints.contains(mint.url) || addedMints.contains(mint.url)
                                MintRowView(
                                    mint: mint,
                                    isAdded: isAdded,
                                    isAdding: isAddingMint,
                                    onTapToAdd: {
                                        mintToConfirm = mint
                                        showingTrustConfirmation = true
                                    },
                                    onMintAdded: { url in
                                        addedMints.insert(url)
                                        onMintAdded?(url)
                                        if mode == .addMint {
                                            dismiss()
                                        }
                                    }
                                )
                            } else {
                                // No mint found at URL
                                HStack {
                                    Spacer()
                                    Text("No mint found at this URL")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                        } else {
                            // Show filtered auditor mints
                            ForEach(filteredMints) { mint in
                                let isAdded = existingMints.contains(mint.url) || addedMints.contains(mint.url)
                                MintRowView(
                                    mint: mint,
                                    isAdded: isAdded,
                                    isAdding: isAddingMint,
                                    onTapToAdd: {
                                        mintToConfirm = mint
                                        showingTrustConfirmation = true
                                    },
                                    onMintAdded: { url in
                                        addedMints.insert(url)
                                        onMintAdded?(url)
                                        if mode == .addMint {
                                            dismiss()
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
        }
    }

    // MARK: - Helpers

    private func lookupCustomMint(url: String) {
        // Cancel any pending lookup
        customMintLookupTask?.cancel()
        customMint = nil

        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only lookup if it looks like a valid URL with a proper domain
        guard let parsedUrl = URL(string: trimmed),
              let scheme = parsedUrl.scheme,
              (scheme == "https" || scheme == "http"),
              let host = parsedUrl.host,
              host.contains("."),
              host.count > 4 else {
            isLoadingCustomMint = false
            return
        }

        isLoadingCustomMint = true

        // Debounce: wait 300ms before making the request
        customMintLookupTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)

            guard !Task.isCancelled else { return }

            do {
                let info = try await MintInfoService.shared.fetchMintInfo(mintUrl: trimmed)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    customMint = MintListItem(url: trimmed, info: info)
                    isLoadingCustomMint = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    customMint = nil
                    isLoadingCustomMint = false
                }
            }
        }
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
    @EnvironmentObject var walletManager: WalletManager

    let mint: MintListItem
    let isAdded: Bool
    let isAdding: Bool
    let onTapToAdd: () -> Void
    var onMintAdded: ((String) -> Void)?

    @State private var showingDetail = false

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

                if let description = mint.displayDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Status indicator or info icon
            if isAdded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            } else if isAdding {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                // Info icon - navigates to detail view
                Button {
                    showingDetail = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundColor(.orange)
                        .font(.title2)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isAdded && !isAdding {
                onTapToAdd()
            }
        }
        .opacity(isAdded ? 0.6 : 1.0)
        .background(
            NavigationLink(destination: MintDetailView(
                mint: mint,
                isAlreadyAdded: isAdded,
                onMintAdded: onMintAdded
            ).environmentObject(walletManager), isActive: $showingDetail) {
                EmptyView()
            }
            .opacity(0)
        )
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
