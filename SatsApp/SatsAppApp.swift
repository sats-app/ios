import SwiftUI

@main
struct SatsAppApp: App {
    @StateObject private var walletManager = WalletManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(walletManager)
        }
    }
}