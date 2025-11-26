import SwiftUI

@main
struct SatsApp: App {
    @StateObject private var walletManager = WalletManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(walletManager)
                .task {
                    await walletManager.initializeWallet()
                }
        }
    }
}
