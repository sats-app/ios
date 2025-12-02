import CashuDevKit
import SwiftUI


struct DepositSheetView: View {
    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.dismiss) private var dismiss
    @State private var amount: String = ""
    @State private var selectedMintUrl: String = ""
    @State private var availableMints: [String] = []
    @State private var isLoadingMints = true
    @State private var isLoading = false
    @State private var depositRequest: String?
    @State private var mintQuoteStatus: QuoteState?
    @State private var quoteId: String?
    @State private var isPolling = false
    @State private var isMinting = false
    @State private var mintedAmount: UInt64?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var pollTimer: Timer?
    @State private var showCopyConfirmation = false

    private enum ViewState: Equatable {
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
            Group {
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
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .animation(.easeInOut(duration: 0.25), value: currentState)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .task {
            await loadMints()
        }
    }

    private var amountInputView: some View {
        VStack(spacing: 0) {
            // Header with icon and title
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 60, height: 60)

                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }

                Text("Generate Deposit")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Amount input
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("₿")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(.orange)

                TextField("0", text: $amount)
                    .keyboardType(.numberPad)
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.leading)
                    .frame(minWidth: 60)
                    .fixedSize()
            }
            .padding(.bottom, 24)

            // Compact mint selector
            if isLoadingMints {
                ProgressView()
                    .padding(.bottom, 16)
            } else if availableMints.isEmpty {
                Text("No mints available")
                    .foregroundColor(.gray)
                    .padding(.bottom, 16)
            } else {
                HStack {
                    Image(systemName: "building.columns")
                        .foregroundColor(.orange)
                        .font(.subheadline)

                    Picker("Mint", selection: $selectedMintUrl) {
                        ForEach(availableMints, id: \.self) { mint in
                            Text(URL(string: mint)?.host ?? mint)
                                .tag(mint)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .tint(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            // Generate button
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
            .background(canGenerateDeposit ? Color.orange : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
            .font(.headline)
            .disabled(!canGenerateDeposit || isLoading)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var depositRequestView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                Text("Deposit ₿\(amount)")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)

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
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showCopyConfirmation = true
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showCopyConfirmation = false
                                        }
                                    }
                                }) {
                                    Image(systemName: showCopyConfirmation ? "checkmark" : "doc.on.doc")
                                        .foregroundColor(showCopyConfirmation ? .green : .orange)
                                }
                            }
                        }

                        // Status
                        VStack(spacing: 8) {
                            if let status = mintQuoteStatus {
                                HStack {
                                    Circle()
                                        .fill(statusColor(for: status))
                                        .frame(width: 8, height: 8)
                                    Text("Status: \(status.displayString)")
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
                    Text("Minted: ₿\(minted)")
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

    private var canGenerateDeposit: Bool {
        guard let amountValue = Int(amount), amountValue > 0 else {
            return false
        }
        return !selectedMintUrl.isEmpty && !isLoadingMints
    }

    private func loadMints() async {
        isLoadingMints = true

        let mints = await walletManager.getMints()
        await MainActor.run {
            self.availableMints = mints
            if !mints.isEmpty && selectedMintUrl.isEmpty {
                self.selectedMintUrl = mints[0]
            }
            self.isLoadingMints = false
        }
    }

    private func generateDeposit() {
        guard let amountValue = UInt64(amount) else {
            showError("Invalid amount")
            return
        }

        guard !selectedMintUrl.isEmpty else {
            showError("Please select a mint")
            return
        }

        isLoading = true

        Task {
            do {
                let quote = try await walletManager.generateMintQuote(
                    mintUrl: selectedMintUrl,
                    amount: amountValue)

                await MainActor.run {
                    self.depositRequest = quote.request
                    self.mintQuoteStatus = quote.state
                    self.quoteId = quote.id
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
        guard !selectedMintUrl.isEmpty else {
            AppLogger.network.error("No mint URL selected")
            return
        }

        do {
            let state = try await walletManager.checkMintQuoteStatus(mintUrl: selectedMintUrl, quoteId: quoteId)

            await MainActor.run {
                self.mintQuoteStatus = state

                if state == .paid {
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
        guard !selectedMintUrl.isEmpty else {
            showError("No mint URL selected")
            return
        }

        isMinting = true

        Task {
            do {
                let mintedAmount = try await walletManager.mintTokens(mintUrl: selectedMintUrl, quoteId: quoteId)

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

    private func statusColor(for state: QuoteState) -> Color {
        switch state {
        case .paid: return .green
        case .pending, .unpaid: return .orange
        case .issued: return .blue
        }
    }
}

extension QuoteState {
    var displayString: String {
        switch self {
        case .unpaid: return "Unpaid"
        case .paid: return "Paid"
        case .pending: return "Pending"
        case .issued: return "Issued"
        }
    }
}

#Preview {
    DepositSheetView()
        .environmentObject(WalletManager())
}
