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

struct BalanceView: View {
    let balance: String
    
    var body: some View {
        NavigationView {
            EmptyView()
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(balance)
                            .font(.headline)
                            .fontWeight(.medium)
                            .foregroundColor(Color.orange)
                    }
                }
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
    @State private var mints: [String] = []
    
    var body: some View {
        NavigationView {
            List(mints, id: \.self) { mintUrl in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(URL(string: mintUrl)?.host ?? "Unknown Mint")
                            .font(.headline)
                            .fontWeight(.medium)
                            .foregroundColor(Color.orange)
                        
                        Text(mintUrl)
                            .font(.caption)
                            .foregroundColor(Color.orange.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    Text("Connected")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(Color.orange)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Mints")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await loadMints()
        }
    }
    
    private func loadMints() async {
        // For now, just show the default mint since wallet doesn't expose mint list directly
        await MainActor.run {
            mints = ["https://fake.thesimplekid.dev"]
        }
    }
}

struct MintInfo {
    let name: String
    let url: String
    let balance: String
}

extension View {
    func balanceToolbar() -> some View {
        modifier(BalanceToolbarModifier())
    }
}
