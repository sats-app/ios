import SwiftUI

struct AnimatedBalanceText: View {
    let balance: String
    @StateObject private var settings = SettingsManager.shared
    @State private var animateBalance = false
    @State private var previousBalance = ""

    private var displayBalance: String {
        settings.hideBalance ? "***" : balance
    }

    var body: some View {
        Text(displayBalance)
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundColor(Color.orange)
            .scaleEffect(animateBalance ? 1.1 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: animateBalance)
            .onChange(of: balance) { newBalance in
                if previousBalance != newBalance && !previousBalance.isEmpty {
                    withAnimation {
                        animateBalance = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation {
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
    @State private var showingSettings = false

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
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingSettings = true
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
            .sheet(isPresented: $showingSettings) {
                SettingsView()
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

    /// Item-based adaptive sheet that evaluates content when item becomes non-nil
    func adaptiveSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder sheetContent: @escaping (Item) -> Content
    ) -> some View {
        modifier(AdaptiveSheetItemModifier(item: item, sheetContent: sheetContent))
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
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        subHeight = newHeight
                                    }
                                }
                        }
                    )
                    .presentationDetents([.height(subHeight)])
                    .presentationDragIndicator(.visible)
            }
    }
}

struct AdaptiveSheetItemModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    @State private var subHeight: CGFloat = 400
    var sheetContent: (Item) -> SheetContent

    func body(content: Content) -> some View {
        content
            .sheet(item: $item) { presentedItem in
                sheetContent(presentedItem)
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    subHeight = proxy.size.height
                                }
                                .onChange(of: proxy.size.height) { newHeight in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        subHeight = newHeight
                                    }
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
    @Environment(\.dismiss) private var dismiss
    @State private var mints: [UIMintInfo] = []
    @State private var isLoading = true
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var refreshTrigger = false

    var body: some View {
        NavigationStack {
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.orange)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        MintBrowserView(mode: .addMint, onMintAdded: { _ in
                            refreshTrigger.toggle()
                        })
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.orange)
                    }
                }
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
        .onChange(of: refreshTrigger) { _ in
            Task { await loadMints() }
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
                    let balanceString = "₿" + (formatter.string(from: NSNumber(value: balance)) ?? "0")

                    return UIMintInfo(
                        name: walletManager.getMintDisplayName(for: url),
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
