import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI


struct DepositSheetView: View {
    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.dismiss) private var dismiss
    @State private var amount: String = ""
    @State private var isLoading = false
    @State private var depositRequest: String?
    @State private var mintQuoteStatus: String?
    @State private var quoteId: String?
    @State private var isPolling = false
    @State private var isMinting = false
    @State private var mintedAmount: UInt64?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var pollTimer: Timer?

    private enum ViewState {
        case amountInput
        case depositRequest
        case minting
        case completed
    }

    private var currentState: ViewState {
        if mintedAmount != nil {
            return .completed
        } else if isMinting {
            return .minting
        } else if depositRequest != nil {
            return .depositRequest
        } else {
            return .amountInput
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch currentState {
            case .amountInput:
                amountInputView
            case .depositRequest:
                depositRequestView
            case .minting:
                mintingView
            case .completed:
                completedView
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private var amountInputView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                Text("Generate Deposit")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                TextField("Amount", text: $amount)
                    .keyboardType(.numberPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.title3)
                    .multilineTextAlignment(.center)
            }

            Button(action: generateDeposit) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    Text(isLoading ? "Generating..." : "Generate Deposit Request")
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(isValidAmount ? Color.orange : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
            .font(.headline)
            .disabled(!isValidAmount || isLoading)
        }
        .padding(20)
    }

    private var depositRequestView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                Text("Deposit Request")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                if let request = depositRequest {
                    VStack(spacing: 16) {
                        // QR Code
                        QRCodeView(text: request)
                            .frame(width: 200, height: 200)

                        // Request string with copy button
                        VStack(spacing: 8) {
                            Text("Payment Request")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            HStack {
                                Text(truncatedRequest(request))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                    .lineLimit(1)

                                Button(action: {
                                    copyToClipboard(request)
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .foregroundColor(.orange)
                                }
                            }
                        }

                        // Status
                        VStack(spacing: 8) {
                            if let status = mintQuoteStatus {
                                HStack {
                                    Circle()
                                        .fill(status == "Paid" ? Color.green : (status == "Pending" ? Color.orange : Color.red))
                                        .frame(width: 8, height: 8)
                                    Text("Status: \(status)")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                }
                            }
                            
                            if isPolling {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Checking payment status...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Button("Cancel") {
                stopPolling()
                dismiss()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
            .font(.headline)
        }
        .padding(20)
        .onAppear {
            if depositRequest != nil && quoteId != nil {
                startPolling()
            }
        }
        .onDisappear {
            stopPolling()
        }
    }

    private var mintingView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                Text("Minting Tokens")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                ProgressView()
                    .scaleEffect(1.5)
                    .padding()

                Text("Processing your payment...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
    }

    private var completedView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 60))

                Text("Tokens Minted Successfully!")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                if let minted = mintedAmount {
                    Text("Minted: \(minted) sats")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                }
            }

            Button("Done") {
                dismiss()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.orange)
            .foregroundColor(.white)
            .cornerRadius(12)
            .font(.headline)
        }
        .padding(20)
    }

    private var isValidAmount: Bool {
        guard let amountValue = Int(amount), amountValue > 0 else {
            return false
        }
        return true
    }

    private func generateDeposit() {
        guard let amountValue = UInt64(amount) else {
            showError("Invalid amount")
            return
        }

        isLoading = true

        Task {
            do {
                let (request, status, id) = try await walletManager.generateMintQuote(
                    amount: amountValue)

                await MainActor.run {
                    self.depositRequest = request
                    self.mintQuoteStatus = status
                    self.quoteId = id
                    self.isLoading = false
                    
                    // Start polling for payment status
                    startPolling()
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    showError("Failed to generate deposit request: \(error.localizedDescription)")
                }
            }
        }
    }

    private func truncatedRequest(_ request: String) -> String {
        let maxLength = 40
        if request.count <= maxLength {
            return request
        }

        let prefixLength = 15
        let suffixLength = 15
        let prefix = String(request.prefix(prefixLength))
        let suffix = String(request.suffix(suffixLength))
        return "\(prefix)...\(suffix)"
    }

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
    }

    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
    
    private func startPolling() {
        guard !isPolling, let quoteId = quoteId else { return }
        
        isPolling = true
        
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task {
                await checkQuoteStatus(quoteId: quoteId)
            }
        }
        
        // Check immediately
        Task {
            await checkQuoteStatus(quoteId: quoteId)
        }
    }
    
    private func stopPolling() {
        isPolling = false
        pollTimer?.invalidate()
        pollTimer = nil
    }
    
    private func checkQuoteStatus(quoteId: String) async {
        do {
            let status = try await walletManager.checkMintQuoteStatus(quoteId: quoteId)
            
            await MainActor.run {
                self.mintQuoteStatus = status
                
                if status == "Paid" {
                    stopPolling()
                    performMinting(quoteId: quoteId)
                }
            }
        } catch {
            await MainActor.run {
                AppLogger.network.error("Failed to check quote status: \(error.localizedDescription)")
            }
        }
    }
    
    private func performMinting(quoteId: String) {
        guard !isMinting else { return }
        
        isMinting = true
        
        Task {
            do {
                let mintedAmount = try await walletManager.mintTokens(quoteId: quoteId)
                
                await MainActor.run {
                    self.mintedAmount = mintedAmount
                    self.isMinting = false
                }
                
                // Refresh the balance in WalletManager
                walletManager.refreshBalance()
            } catch {
                await MainActor.run {
                    self.isMinting = false
                    showError("Failed to mint tokens: \(error.localizedDescription)")
                }
            }
        }
    }
}

struct QRCodeView: View {
    let text: String

    var body: some View {
        if let qrImage = generateQRCode(from: text) {
            Image(uiImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Text("QR Code Error")
                        .foregroundColor(.secondary)
                )
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        filter.message = Data(string.utf8)

        if let outputImage = filter.outputImage {
            let scaleX = 200 / outputImage.extent.size.width
            let scaleY = 200 / outputImage.extent.size.height
            let transformedImage = outputImage.transformed(
                by: CGAffineTransform(scaleX: scaleX, y: scaleY))

            if let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent)
            {
                return UIImage(cgImage: cgImage)
            }
        }

        return nil
    }
}

#Preview {
    DepositSheetView()
        .environmentObject(WalletManager())
}
