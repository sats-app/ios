import SwiftUI

struct AnimatedBalanceText: View {
    let balance: String
    @State private var animateBalance = false
    @State private var previousBalance = ""

    var body: some View {
        Text(balance)
            .font(.headline)
            .fontWeight(.medium)
            .foregroundColor(Color.orange)
            .scaleEffect(animateBalance ? 1.1 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: animateBalance)
            .onChange(of: balance) { newBalance in
                if previousBalance != newBalance && !previousBalance.isEmpty {
                    // Animate when balance changes
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        animateBalance = true
                    }

                    // Reset animation after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                            animateBalance = false
                        }
                    }
                }
                previousBalance = newBalance
            }
    }
}

struct BalanceToolbarModifier: ViewModifier {
    @EnvironmentObject var walletManager: WalletManager
    @State private var showingMintsDrawer = false
    @State private var showingDepositSheet = false
    
    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showingMintsDrawer = true
                    }) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.orange)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    HStack {
                        AnimatedBalanceText(balance: walletManager.formattedBalance)
                        
                        Button(action: {
                            showingDepositSheet = true
                        }) {
                            Image(systemName: "plus.circle")
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Settings action
                    }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.orange)
                    }
                }
            }
            .sheet(isPresented: $showingMintsDrawer) {
                MintsDrawerView()
            }
            .adaptiveSheet(isPresent: $showingDepositSheet) {
                DepositSheetView()
            }
    }
}

extension View {
    func adaptiveSheet<Content: View>(
        isPresent: Binding<Bool>, 
        @ViewBuilder sheetContent: () -> Content
    ) -> some View {
        modifier(AdaptiveSheetModifier(isPresented: isPresent, sheetContent: sheetContent()))
    }
}

struct AdaptiveSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @State private var subHeight: CGFloat = 400
    var sheetContent: SheetContent

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                sheetContent
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    subHeight = proxy.size.height
                                }
                                .onChange(of: proxy.size.height) { newHeight in
                                    subHeight = newHeight
                                }
                        }
                    )
                    .presentationDetents([.height(subHeight)])
                    .presentationDragIndicator(.visible)
            }
    }
}

struct MintsDrawerView: View {
    @EnvironmentObject var walletManager: WalletManager
    @State private var mints: [UIMintInfo] = []
    @State private var isLoading = true
    @State private var showingAddMint = false
    @State private var newMintUrl = ""
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView()
                } else if mints.isEmpty {
                    Text("No mints configured")
                        .foregroundColor(.gray)
                } else {
                    List {
                        ForEach(mints, id: \.url) { mint in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mint.name)
                                        .font(.headline)
                                        .fontWeight(.medium)
                                        .foregroundColor(Color.orange)

                                    Text(mint.url)
                                        .font(.caption)
                                        .foregroundColor(Color.orange.opacity(0.7))
                                }

                                Spacer()

                                Text(mint.balance)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(Color.orange)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: deleteMint)
                    }
                }
            }
            .navigationTitle("Mints")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddMint = true
                    }) {
                        Image(systemName: "plus")
                            .foregroundColor(.orange)
                    }
                }
            }
            .sheet(isPresented: $showingAddMint) {
                AddMintView(onAdd: { url in
                    Task {
                        await addMint(url: url)
                    }
                })
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
        .task {
            await loadMints()
        }
    }

    private func loadMints() async {
        isLoading = true

        do {
            let mintUrls = await walletManager.getMints()
            let balances = try await walletManager.getMintBalances()

            await MainActor.run {
                mints = mintUrls.map { url in
                    let balance = balances[url] ?? 0
                    let formatter = NumberFormatter()
                    formatter.numberStyle = .decimal
                    formatter.groupingSeparator = ","
                    formatter.usesGroupingSeparator = true
                    let balanceString = (formatter.string(from: NSNumber(value: balance)) ?? "0") + " sat"

                    return UIMintInfo(
                        name: URL(string: url)?.host ?? "Unknown Mint",
                        url: url,
                        balance: balanceString
                    )
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load mints: \(error.localizedDescription)"
                showingError = true
                isLoading = false
            }
        }
    }

    private func addMint(url: String) async {
        do {
            try await walletManager.addMint(mintUrl: url)
            await loadMints()
            await MainActor.run {
                showingAddMint = false
                newMintUrl = ""
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to add mint: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    private func deleteMint(at offsets: IndexSet) {
        guard let index = offsets.first else { return }
        let mintUrl = mints[index].url

        Task {
            do {
                try await walletManager.removeMint(mintUrl: mintUrl)
                await loadMints()
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to remove mint: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }
}

struct AddMintView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mintUrl: String = ""
    let onAdd: (String) -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("Mint URL", text: $mintUrl)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                    .padding(.horizontal)

                Button("Add Mint") {
                    onAdd(mintUrl)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(isValidUrl ? Color.orange : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
                .font(.headline)
                .disabled(!isValidUrl)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Add Mint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var isValidUrl: Bool {
        guard let url = URL(string: mintUrl) else { return false }
        return url.scheme == "https" || url.scheme == "http"
    }
}

struct UIMintInfo: Identifiable {
    let id = UUID()
    let name: String
    let url: String
    let balance: String
}

extension View {
    func balanceToolbar() -> some View {
        modifier(BalanceToolbarModifier())
    }
}
