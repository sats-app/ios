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
        case .request: return "Request created!"
        }
    }
}

/// Unified data model for sheet presentation - ensures content is evaluated with fresh data
enum TransactSheetData: Identifiable {
    case manual(mode: TransactMode, amount: String)
    case lightning(invoice: LightningInvoiceData)
    case paymentRequest(data: ScannedPaymentRequestData)

    var id: String {
        switch self {
        case .manual(let mode, let amount):
            return "manual-\(mode)-\(amount)"
        case .lightning(let invoice):
            return "lightning-\(invoice.invoice)"
        case .paymentRequest(let data):
            return "payment-\(data.encodedRequest)"
        }
    }

    var mode: TransactMode {
        switch self {
        case .manual(let mode, _): return mode
        case .lightning, .paymentRequest: return .pay
        }
    }
}

struct TransactView: View {
    @EnvironmentObject var walletManager: WalletManager
    @State private var amount: String = "0"
    @State private var showingScanner = false
    @State private var scanSuccessAmount: UInt64?
    @State private var showingScanSuccess = false

    /// Single state variable for sheet presentation - replaces multiple pending states
    @State private var presentedSheetData: TransactSheetData?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()

                Text("\u{20BF}\(amount)")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(Color.orange)
                    .padding(.horizontal)

                Spacer()

                NumberPadView(amount: $amount)

                HStack(spacing: 16) {
                    Button("Request") {
                        presentedSheetData = .manual(mode: .request, amount: amount)
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
                        presentedSheetData = .manual(mode: .pay, amount: amount)
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
            .adaptiveSheet(item: $presentedSheetData) { data in
                TransactSheetView(sheetData: data)
                    .onDisappear {
                        amount = "0"
                    }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                QRScannerView(
                    onTokenReceived: { amount in
                        scanSuccessAmount = amount
                        showingScanSuccess = true
                    },
                    onLightningInvoiceScanned: { data in
                        // Set data directly - sheet opens when scanner dismisses
                        presentedSheetData = .lightning(invoice: data)
                    },
                    onPaymentRequestScanned: { data in
                        // Set data directly - sheet opens when scanner dismisses
                        presentedSheetData = .paymentRequest(data: data)
                    }
                )
            }
            .onChange(of: showingScanner) { isShowing in
                if !isShowing && presentedSheetData != nil {
                    // Scanner just dismissed with pending data
                    // Small delay to let fullScreenCover animation complete
                    let dataToPresent = presentedSheetData
                    presentedSheetData = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        presentedSheetData = dataToPresent
                    }
                }
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
        ["", "0", "\u{232B}"]
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
        case "\u{232B}":
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
    let sheetData: TransactSheetData

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
    @State private var paymentSuccess = false
    @State private var paidAmount: UInt64 = 0
    @Environment(\.presentationMode) var presentationMode

    /// Returns true if we're confirming a scanned payment (not entering amount)
    private var isPrefilledPayment: Bool {
        switch sheetData {
        case .manual: return false
        case .lightning, .paymentRequest: return true
        }
    }

    /// Display amount based on sheet data type
    private var displayAmount: String {
        switch sheetData {
        case .manual(_, let amount):
            return amount
        case .lightning(let invoice):
            return String(invoice.amount)
        case .paymentRequest(let data):
            return String(data.amount ?? 0)
        }
    }

    /// Mode derived from sheet data
    private var mode: TransactMode {
        sheetData.mode
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if paymentSuccess {
                    paymentSuccessView
                } else if isSpent {
                    successView
                } else if showQRResult {
                    qrResultView
                } else if isPrefilledPayment {
                    paymentConfirmationView
                } else {
                    inputFormView
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .animation(.easeInOut(duration: 0.25), value: showQRResult)
            .animation(.easeInOut(duration: 0.3), value: isSpent)
            .animation(.easeInOut(duration: 0.3), value: paymentSuccess)
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

            Text("\u{20BF}\(displayAmount)")
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

    private var paymentSuccessView: some View {
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

            Text("Payment Sent!")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Text(WalletManager.formatAmount(paidAmount))
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

    private var paymentConfirmationView: some View {
        VStack(spacing: 20) {
            // Header with icon
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 60, height: 60)

                    Image(systemName: lightningInvoice != nil ? "bolt.fill" : "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }

                Text(lightningInvoice != nil ? "Pay Lightning Invoice" : "Payment Request")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
            }
            .padding(.top, 20)

            // Amount display
            if let invoice = lightningInvoice {
                Text(WalletManager.formatAmount(invoice.amount))
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(.primary)

                // Fee display
                HStack {
                    Text("Network Fee")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("+ \(WalletManager.formatAmount(invoice.feeReserve))")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)

                // Total
                HStack {
                    Text("Total")
                        .fontWeight(.medium)
                    Spacer()
                    Text(WalletManager.formatAmount(invoice.amount + invoice.feeReserve))
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            } else if let request = paymentRequestData {
                if let amount = request.amount {
                    Text(WalletManager.formatAmount(amount))
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.primary)
                } else {
                    Text("Amount not specified")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }

                // Description (if present)
                if let description = request.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }

            // Mint selector
            if isLoadingMints {
                ProgressView()
                    .padding(.vertical, 10)
            } else if availableMints.isEmpty {
                Text("No mints available")
                    .foregroundColor(.gray)
                    .padding(.vertical, 10)
            } else {
                HStack {
                    Image(systemName: "building.columns")
                        .foregroundColor(.orange)
                        .font(.subheadline)

                    Picker("Pay from", selection: $selectedMintUrl) {
                        ForEach(availableMints, id: \.self) { mint in
                            Text(walletManager.getMintDisplayName(for: mint))
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

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button(action: executePrefilledPayment) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(isLoading ? "Processing..." : "Confirm Payment")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
                .font(.headline)
                .disabled(isLoading || availableMints.isEmpty || (paymentRequestData?.amount == nil && lightningInvoice == nil))

                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.gray.opacity(0.1))
                .foregroundColor(.primary)
                .cornerRadius(12)
                .font(.headline)
                .disabled(isLoading)
            }
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 20)
    }

    /// Extract lightning invoice from sheet data if present
    private var lightningInvoice: LightningInvoiceData? {
        if case .lightning(let invoice) = sheetData {
            return invoice
        }
        return nil
    }

    /// Extract payment request data from sheet data if present
    private var paymentRequestData: ScannedPaymentRequestData? {
        if case .paymentRequest(let data) = sheetData {
            return data
        }
        return nil
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

                Text("\(mode == .pay ? "Pay" : "Request") \u{20BF}\(displayAmount)")
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

                Text("\(mode == .pay ? "Pay" : "Request") \u{20BF}\(displayAmount)")
                    .font(.title2)
                    .bold()
                    .foregroundColor(Color.orange)
            }
            .padding(.top, 20)

            // Mint selector (only for pay mode)
            if mode == .pay {
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
                                Text(walletManager.getMintDisplayName(for: mint))
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

                    guard let amountValue = UInt64(displayAmount), amountValue > 0 else {
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
                    // Generate NUT-18 Payment Request
                    guard let amountValue = UInt64(displayAmount), amountValue > 0 else {
                        await MainActor.run {
                            showError("Invalid amount")
                            isLoading = false
                        }
                        return
                    }

                    let paymentRequest = try await walletManager.createPaymentRequest(
                        amount: amountValue,
                        description: memo.isEmpty ? nil : memo
                    )

                    await MainActor.run {
                        generatedContent = paymentRequest
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

    private func executePrefilledPayment() {
        isLoading = true

        Task {
            do {
                if let invoice = lightningInvoice {
                    // Pay Lightning invoice via meltTokens
                    let (amount, _) = try await walletManager.meltTokens(
                        mintUrl: selectedMintUrl,
                        invoice: invoice.invoice
                    )

                    await MainActor.run {
                        walletManager.refreshBalance()
                        paidAmount = amount
                        paymentSuccess = true
                        isLoading = false
                    }
                } else if let request = paymentRequestData {
                    guard let paymentAmount = request.amount, paymentAmount > 0 else {
                        await MainActor.run {
                            showError("Payment request has no amount specified")
                            isLoading = false
                        }
                        return
                    }

                    if request.hasActiveTransport {
                        // HTTP/Nostr transport - payRequest() handles delivery automatically
                        try await walletManager.payPaymentRequest(
                            paymentRequest: request.paymentRequest,
                            mintUrl: selectedMintUrl,
                            amount: paymentAmount
                        )

                        await MainActor.run {
                            walletManager.refreshBalance()
                            paidAmount = paymentAmount
                            paymentSuccess = true
                            isLoading = false
                        }
                    } else {
                        // "none" transport - generate token and show QR code for manual delivery
                        let token = try await walletManager.send(
                            mintUrl: selectedMintUrl,
                            amount: paymentAmount,
                            memo: request.description
                        )

                        await MainActor.run {
                            walletManager.refreshBalance()
                            generatedContent = token
                            isLoading = false
                            showQRResult = true
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    showError("Payment failed: \(error.localizedDescription)")
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
