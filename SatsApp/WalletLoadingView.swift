import SwiftUI

struct WalletLoadingView: View {
    @EnvironmentObject var walletManager: WalletManager
    
    var body: some View {
        VStack(spacing: 20) {
            if walletManager.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                    
                    Text("Initializing Wallet...")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Connecting to \(walletManager.defaultMintURL)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let error = walletManager.initializationError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    
                    Text("Failed to Initialize Wallet")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Retry") {
                        walletManager.retryInitialization()
                    }
                    .frame(width: 120, height: 44)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .font(.headline)
                }
            }
        }
        .padding()
    }
}

#Preview {
    WalletLoadingView()
        .environmentObject(WalletManager())
}