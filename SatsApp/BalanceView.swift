import SwiftUI

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
    let balance: String
    @State private var showingMintsDrawer = false
    
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
                        Text(balance)
                            .font(.headline)
                            .fontWeight(.medium)
                            .foregroundColor(Color.orange)
                        
                        Button(action: {
                            // Add mint action
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
    func balanceToolbar(_ balance: String) -> some View {
        modifier(BalanceToolbarModifier(balance: balance))
    }
}
