import SwiftUI

struct ContentView: View {
    @EnvironmentObject var walletManager: WalletManager

    var body: some View {
        Group {
            if !walletManager.isInitialized {
                WalletLoadingView()
            } else if walletManager.needsMintSelection {
                MintSelectionView()
            } else {
                TabView {
                    TransactView()
                        .tabItem {
                            Image(systemName: "arrow.left.arrow.right")
                            Text("Transact")
                        }

                    ActivityView()
                        .tabItem {
                            Image(systemName: "list.bullet")
                            Text("Activity")
                        }
                }
                .accentColor(.orange)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WalletManager())
}
