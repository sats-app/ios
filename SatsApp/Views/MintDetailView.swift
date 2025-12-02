import SwiftUI

struct MintDetailView: View {
    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.dismiss) private var dismiss

    let mint: MintListItem
    let isAlreadyAdded: Bool
    var onMintAdded: ((String) -> Void)?

    @State private var mintInfo: MintInfoResponse?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showingAddConfirmation = false
    @State private var isAddingMint = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                if isLoading {
                    loadingView
                } else if let error = loadError {
                    errorView(error)
                } else if let info = mintInfo {
                    infoSections(info)
                }
            }
            .padding()
        }
        .navigationTitle("Mint Info")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMintInfo()
        }
        .alert("Trust This Mint?", isPresented: $showingAddConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Add Mint") {
                Task { await addMint() }
            }
        } message: {
            Text("Adding \(mint.displayName) means trusting it to hold your funds. Only add mints you trust.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Icon
            AsyncImage(url: mintInfo?.iconUrl.flatMap { URL(string: $0) } ?? mint.iconURL) { phase in
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
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            // Name
            Text(mintInfo?.name ?? mint.displayName)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            // URL
            Text(mint.url)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            // Add button
            if !isAlreadyAdded {
                Button(action: { showingAddConfirmation = true }) {
                    HStack {
                        if isAddingMint {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                        Text(isAddingMint ? "Adding..." : "Add Mint")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(12)
                }
                .disabled(isAddingMint)
                .padding(.top, 8)
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Already Added")
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Loading & Error

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading mint info...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text(error)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadMintInfo() }
            }
            .foregroundColor(.orange)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Info Sections

    @ViewBuilder
    private func infoSections(_ info: MintInfoResponse) -> some View {
        VStack(spacing: 20) {
            // Description
            if let description = info.description ?? info.descriptionLong {
                infoSection(title: "Description") {
                    Text(description)
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }

            // Long description (if different from short)
            if let descLong = info.descriptionLong, info.description != nil, descLong != info.description {
                infoSection(title: "About") {
                    Text(descLong)
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }

            // Message of the Day
            if let motd = info.motd, !motd.isEmpty {
                infoSection(title: "Message of the Day") {
                    Text(motd)
                        .font(.body)
                        .foregroundColor(.primary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                }
            }

            // Version
            if let version = info.version {
                infoSection(title: "Version") {
                    Text(version)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            // Public Key
            if let pubkey = info.pubkey {
                infoSection(title: "Public Key") {
                    HStack {
                        Text(truncatedPubkey(pubkey))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: { copyToClipboard(pubkey) }) {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(.orange)
                        }
                    }
                }
            }

            // Contact
            let contacts = info.formattedContacts
            if !contacts.isEmpty {
                infoSection(title: "Contact") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(contacts, id: \.method) { contact in
                            HStack {
                                contactIcon(for: contact.method)
                                    .foregroundColor(.orange)
                                    .frame(width: 24)
                                Text(contact.info)
                                    .font(.body)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }

            // Terms of Service
            if let tosUrl = info.tosUrl, let url = URL(string: tosUrl) {
                infoSection(title: "Terms of Service") {
                    Link(destination: url) {
                        HStack {
                            Text("View Terms")
                                .foregroundColor(.orange)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.orange)
                        }
                    }
                }
            }

            // Supported NUTs
            let nuts = info.supportedNuts
            if !nuts.isEmpty {
                infoSection(title: "Supported Features (NUTs)") {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 60))
                    ], spacing: 8) {
                        ForEach(nuts, id: \.self) { nut in
                            Text("NUT-\(String(format: "%02d", nut))")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
    }

    private func infoSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var mintPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.2))
            Image(systemName: "bolt.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)
        }
    }

    private func truncatedPubkey(_ pubkey: String) -> String {
        guard pubkey.count > 16 else { return pubkey }
        let prefix = pubkey.prefix(8)
        let suffix = pubkey.suffix(8)
        return "\(prefix)...\(suffix)"
    }

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
    }

    private func contactIcon(for method: String) -> Image {
        switch method.lowercased() {
        case "email":
            return Image(systemName: "envelope.fill")
        case "twitter", "x":
            return Image(systemName: "at")
        case "nostr":
            return Image(systemName: "bubble.left.fill")
        case "telegram":
            return Image(systemName: "paperplane.fill")
        default:
            return Image(systemName: "link")
        }
    }

    // MARK: - Actions

    private func loadMintInfo() async {
        await MainActor.run {
            isLoading = true
            loadError = nil
        }

        do {
            let info = try await MintInfoService.shared.fetchMintInfo(mintUrl: mint.url)
            await MainActor.run {
                mintInfo = info
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func addMint() async {
        await MainActor.run {
            isAddingMint = true
        }

        do {
            try await walletManager.addMint(mintUrl: mint.url)
            await MainActor.run {
                isAddingMint = false
                onMintAdded?(mint.url)
                dismiss()
            }
        } catch {
            await MainActor.run {
                isAddingMint = false
                loadError = "Failed to add mint: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    NavigationStack {
        MintDetailView(
            mint: MintListItem(
                id: 1,
                url: "https://mint.example.com",
                name: "Example Mint",
                state: "OK"
            ),
            isAlreadyAdded: false
        )
        .environmentObject(WalletManager())
    }
}
