import SwiftUI
import Amplify
import AWSCognitoAuthPlugin

@main
struct SatsApp: App {
    @StateObject private var walletManager = WalletManager()
    @StateObject private var authManager = AuthManager()

    init() {
        configureAmplify()
    }

    private func configureAmplify() {
        do {
            // Add the Cognito Auth plugin
            try Amplify.add(plugin: AWSCognitoAuthPlugin())

            // Use the simplified configuration approach with amplify_outputs.json
            try Amplify.configure(with: .amplifyOutputs)

            print("Amplify configured successfully with amplify_outputs.json")
        } catch {
            print("Failed to configure Amplify: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                ContentView()
                    .environmentObject(walletManager)
                    .environmentObject(authManager)
                    .onAppear {
                        walletManager.setAuthManager(authManager)
                    }
            } else {
                AuthView()
                    .environmentObject(authManager)
            }
        }
    }
}