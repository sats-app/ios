import SwiftUI
import CashuDevKit

enum TransactMode {
    case pay
    case request
    
    var buttonTitle: String {
        switch self {
        case .pay: return "Pay Bitcoin"
        case .request: return "Request Bitcoin"
        }
    }
    
    var iconName: String {
        switch self {
        case .pay: return "arrow.up.circle.fill"
        case .request: return "arrow.down.circle.fill"
        }
    }
    
    var successMessage: String {
        switch self {
        case .pay: return "Payment sent!"
        case .request: return "Invoice created!"
        }
    }
}

struct TransactView: View {
    @EnvironmentObject var walletManager: WalletManager
    @State private var amount: String = "0"
    @State private var showingTransactSheet = false
    @State private var showingScanner = false
    @State private var transactMode: TransactMode = .pay
    @State private var scanSuccessAmount: UInt64?
    @State private var showingScanSuccess = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()
                
                Text("₿\(amount)")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(Color.orange)
                    .padding(.horizontal)
                
                Spacer()
                
                NumberPadView(amount: $amount)
                
                HStack(spacing: 16) {
                    Button("Request") {
                        transactMode = .request
                        showingTransactSheet = true
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .font(.headline)
                    
                    Button(action: {
                        showingScanner = true
                    }) {
                        Image(systemName: "qrcode")
                            .font(.title2)
                            .foregroundColor(Color.orange)
                    }
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    
                    Button("Pay") {
                        transactMode = .pay
                        showingTransactSheet = true
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .font(.headline)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .balanceToolbar()
            .adaptiveSheet(isPresent: $showingTransactSheet) {
                TransactSheetView(amount: amount, mode: transactMode)
                    .onDisappear { amount = "0" }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                QRScannerView(onTokenReceived: { amount in
                    scanSuccessAmount = amount
                    showingScanSuccess = true
                })
            }
            .adaptiveSheet(isPresent: $showingScanSuccess) {
                ScanSuccessView(amount: scanSuccessAmount ?? 0)
            }
        }
        .onAppear {
            walletManager.refreshBalance()
        }
    }
    
}

struct NumberPadView: View {
    @Binding var amount: String
    
    let buttons = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "⌫"]
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(buttons, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { button in
                        Button(action: {
                            handleButtonPress(button)
                        }) {
                            Text(button)
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(Color.orange)
                                .frame(maxWidth: .infinity, minHeight: 60)
                                .background(Color.clear)
                                .cornerRadius(8)
                        }
                        .disabled(button.isEmpty)
                    }
                }
            }
        }
        .padding(.horizontal)
    }
    
    private func handleButtonPress(_ button: String) {
        switch button {
        case "⌫":
            if !amount.isEmpty && amount != "0" {
                amount = String(amount.dropLast())
                if amount.isEmpty {
                    amount = "0"
                }
            }
        case "0":
            if amount != "0" {
                amount += button
            }
        default:
            if amount == "0" {
                amount = button
            } else {
                amount += button
            }
        }
    }
}

struct TransactSheetView: View {
    let amount: String
    let mode: TransactMode
    @EnvironmentObject var walletManager: WalletManager
    @State private var selectedMintUrl: String = ""
    @State private var availableMints: [String] = []
    @State private var isLoadingMints = true
    @State private var memo: String = ""
    @State private var isViewableByRecipient: Bool = false
    @State private var isLoading: Bool = false
    @State private var showQRResult: Bool = false
    @State private var generatedContent: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var hasCopied = false
    @State private var isSpent = false
    @State private var pollingTask: Task<Void, Never>?
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isSpent {
                    successView
                } else if showQRResult {
                    qrResultView
                } else {
                    inputFormView
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .animation(.easeInOut(duration: 0.25), value: showQRResult)
            .animation(.easeInOut(duration: 0.3), value: isSpent)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .task {
            await loadMints()
        }
        .onDisappear {
            pollingTask?.cancel()
        }
    }

    private var successView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
            }

            Text(mode == .pay ? "Tokens claimed!" : "Payment received!")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Text("₿\(amount)")
                .font(.title3)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
        .onAppear {
            // Auto-dismiss after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                presentationMode.wrappedValue.dismiss()
            }
        }
    }

    private var qrResultView: some View {
        VStack(spacing: 16) {
            // Header with icon above amount (matches input form style)
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 44, height: 44)

                    Image(systemName: mode.iconName)
                        .font(.title3)
                        .foregroundColor(Color.white)
                }

                Text("\(mode == .pay ? "Pay" : "Request") ₿\(amount)")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(Color.orange)
            }
            .padding(.top, 16)

            // QR Code - animated for long tokens (NUT-16), static for short ones
            // Larger size to take up more space
            if generatedContent.count > 600 {
                AnimatedQRCodeView(content: generatedContent)
                    .frame(maxWidth: 300)
                    .frame(height: 380)
            } else {
                QRCodeView(text: generatedContent)
                    .frame(width: 280, height: 280)
            }

            // Truncated content text - tappable to copy
            Button(action: {
                UIPasteboard.general.string = generatedContent
                hasCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    hasCopied = false
                }
            }) {
                Text(truncatedContent(generatedContent))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(hasCopied ? .green : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }

            // Action buttons
            HStack(spacing: 20) {
                ShareLink(item: generatedContent) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                        .foregroundColor(Color.orange)
                        .frame(width: 44, height: 44)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }

                Button(action: {
                    // NFC placeholder - not implemented
                }) {
                    Image(systemName: "wave.3.right.circle")
                        .font(.title3)
                        .foregroundColor(Color.orange)
                        .frame(width: 44, height: 44)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }
                .disabled(true)
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
        .onAppear {
            // Start polling for spent status (pay mode only)
            if mode == .pay {
                startPollingForSpent()
            }
        }
    }

    private func startPollingForSpent() {
        pollingTask = Task {
            while !Task.isCancelled && !isSpent {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

                guard !Task.isCancelled else { break }

                do {
                    let spent = try await walletManager.checkTokenSpent(tokenString: generatedContent)
                    if spent {
                        await MainActor.run {
                            isSpent = true
                            walletManager.refreshBalance()
                        }
                        break
                    }
                } catch {
                    // Silently continue polling on error
                    AppLogger.network.debug("Proof check failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private var inputFormView: some View {
        VStack(spacing: 20) {
            // Header section
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 60, height: 60)

                    Image(systemName: mode.iconName)
                        .font(.title)
                        .foregroundColor(Color.white)
                }

                Text("\(mode == .pay ? "Pay" : "Request") ₿\(amount)")
                    .font(.title2)
                    .bold()
                    .foregroundColor(Color.orange)
            }
            .padding(.top, 20)

            // Mint selector
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
            }

            // Memo field
            VStack(alignment: .leading, spacing: 8) {
                Text("Memo")
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(Color.orange)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                        .frame(height: 80)

                    if memo.isEmpty {
                        Text("Add a note...")
                            .foregroundColor(.gray)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }

                    TextField("", text: $memo)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .frame(height: 80, alignment: .topLeading)
                }
            }

            // Viewable by recipient checkbox
            HStack {
                Button(action: {
                    isViewableByRecipient.toggle()
                }) {
                    Image(systemName: isViewableByRecipient ? "checkmark.square.fill" : "square")
                        .foregroundColor(isViewableByRecipient ? Color.orange : .gray)
                }

                Text("Viewable by Recipient")
                    .font(.subheadline)
                    .foregroundColor(Color.orange)

                Spacer()
            }

            Spacer()

            // Bottom button section
            Button(action: {
                handleTransaction()
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    Text(isLoading ? "Processing..." : mode.buttonTitle)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.orange)
            .foregroundColor(.white)
            .cornerRadius(12)
            .font(.headline)
            .disabled(isLoading)
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 20)
    }

    private func truncatedContent(_ content: String) -> String {
        let maxLength = 30
        if content.count <= maxLength {
            return content
        }
        let prefixLength = 12
        let suffixLength = 12
        let prefix = String(content.prefix(prefixLength))
        let suffix = String(content.suffix(suffixLength))
        return "\(prefix)...\(suffix)"
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

    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }

    private func handleTransaction() {
        isLoading = true

        Task {
            do {
                switch mode {
                case .pay:
                    // Generate real Cashu token
                    guard !selectedMintUrl.isEmpty else {
                        await MainActor.run {
                            showError("Please select a mint")
                            isLoading = false
                        }
                        return
                    }

                    guard let amountValue = UInt64(amount), amountValue > 0 else {
                        await MainActor.run {
                            showError("Invalid amount")
                            isLoading = false
                        }
                        return
                    }

                    let token = try await walletManager.send(
                        mintUrl: selectedMintUrl,
                        amount: amountValue,
                        memo: memo.isEmpty ? nil : memo
                    )

                    await MainActor.run {
                        generatedContent = token
                        isLoading = false
                        showQRResult = true
                    }

                    // Refresh balance after sending
                    walletManager.refreshBalance()

                case .request:
                    // Generate Lightning invoice via mint quote
                    guard !selectedMintUrl.isEmpty else {
                        await MainActor.run {
                            showError("Please select a mint")
                            isLoading = false
                        }
                        return
                    }

                    guard let amountValue = UInt64(amount), amountValue > 0 else {
                        await MainActor.run {
                            showError("Invalid amount")
                            isLoading = false
                        }
                        return
                    }

                    let quote = try await walletManager.generateMintQuote(
                        mintUrl: selectedMintUrl,
                        amount: amountValue
                    )

                    await MainActor.run {
                        generatedContent = quote.request
                        isLoading = false
                        showQRResult = true
                    }
                }
            } catch {
                await MainActor.run {
                    showError("Transaction failed: \(error.localizedDescription)")
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Scan Success View

struct ScanSuccessView: View {
    let amount: UInt64
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
            }

            Text("Received!")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Text(WalletManager.formatAmount(amount))
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
        .onAppear {
            // Auto-dismiss after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                dismiss()
            }
        }
    }
}

#Preview {
    TransactView()
}
