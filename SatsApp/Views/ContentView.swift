import SwiftUI

struct ContentView: View {
    @EnvironmentObject var walletManager: WalletManager
    
    var body: some View {
        if walletManager.isInitialized {
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
        } else {
            WalletLoadingView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WalletManager())
}

