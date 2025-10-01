import SwiftUI
import Amplify
import AWSCognitoAuthPlugin

@main
struct SatsApp: App {
    @StateObject private var walletManager = WalletManager()
    @State private var isAuthenticated = false

    init() {
        configureAmplify()
    }

    private func configureAmplify() {
        do {
            // Add the Cognito Auth plugin
            try Amplify.add(plugin: AWSCognitoAuthPlugin())

            // Use the simplified configuration approach with amplify_outputs.json
            try Amplify.configure(with: .amplifyOutputs)

            AppLogger.ui.info("Amplify configured successfully with amplify_outputs.json")
        } catch {
            AppLogger.ui.error("Failed to configure Amplify: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isAuthenticated {
                    ContentView()
                        .environmentObject(walletManager)
                        .onAppear {
                            Task {
                                await walletManager.initializeWallet()
                            }
                        }
                        .onChange(of: walletManager.initializationError) { error in
                            // If wallet fails due to authentication, sign out the user
                            if let errorMessage = error, errorMessage.contains("not authenticated") {
                                Task {
                                    await signOut()
                                }
                            }
                        }
                } else {
                    PasswordlessAuthView()
                }
            }
            .task {
                await checkAuthStatus()

                // Listen for auth state changes
                _ = Amplify.Hub.listen(to: .auth) { payload in
                    switch payload.eventName {
                    case HubPayload.EventName.Auth.signedIn:
                        Task { @MainActor in
                            isAuthenticated = true
                        }
                    case HubPayload.EventName.Auth.signedOut:
                        Task { @MainActor in
                            isAuthenticated = false
                        }
                    default:
                        break
                    }
                }
            }
        }
    }

    @MainActor
    private func checkAuthStatus() async {
        do {
            let session = try await Amplify.Auth.fetchAuthSession()
            isAuthenticated = session.isSignedIn
        } catch {
            isAuthenticated = false
            AppLogger.ui.debug("Not authenticated: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func signOut() async {
        do {
            try await Amplify.Auth.signOut()
            isAuthenticated = false
        } catch {
            AppLogger.ui.error("Sign out failed: \(error.localizedDescription)")
        }
    }
}