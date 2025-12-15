import SwiftUI
import CashuDevKit
import CoreNFC

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

/// Holds prepared send data for fee confirmation
struct PreparedSendData {
    let preparedSend: PreparedSend
    let amount: UInt64
    let fee: UInt64
    let mintUrl: String

    var total: UInt64 { amount + fee }
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
                    .disabled(amount == "0")
                    .opacity(amount == "0" ? 0.5 : 1.0)

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
                    .disabled(amount == "0")
                    .opacity(amount == "0" ? 0.5 : 1.0)
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
    @State private var mintBalances: [String: UInt64] = [:]
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
    @State private var isWritingNFC = false
    @StateObject private var nfcService = NFCPaymentService()
    @State private var pollingTask: Task<Void, Never>?
    @State private var paymentSuccess = false
    @State private var paidAmount: UInt64 = 0
    @State private var preparedSendData: PreparedSendData?
    @State private var isPreparing: Bool = false
    @State private var sentTotalAmount: UInt64 = 0  // Total amount sent including fee
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

    /// Returns true if the selected mint has insufficient balance for the payment
    private var hasInsufficientBalance: Bool {
        guard !selectedMintUrl.isEmpty else { return false }

        let selectedBalance = mintBalances[selectedMintUrl] ?? 0
        let requiredAmount: UInt64

        if let invoice = lightningInvoice {
            requiredAmount = invoice.amount + invoice.feeReserve
        } else if let request = paymentRequestData, let amount = request.amount {
            // For payment requests without transport, include prepared fee if available
            if let prepared = preparedSendData {
                requiredAmount = prepared.total
            } else {
                requiredAmount = amount
            }
        } else if let amountValue = UInt64(displayAmount), amountValue > 0 {
            // For manual sends, include prepared fee if available
            if let prepared = preparedSendData {
                requiredAmount = prepared.total
            } else {
                requiredAmount = amountValue
            }
        } else {
            return false
        }

        return selectedBalance < requiredAmount
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
            // Cancel any prepared send when sheet is dismissed
            if let prepared = preparedSendData {
                Task {
                    await walletManager.cancelPreparedSend(prepared.preparedSend)
                }
            }
        }
        .onChange(of: selectedMintUrl) { newMint in
            guard !newMint.isEmpty else { return }
            // Re-prepare when mint changes (for Cashu sends and payment requests without transport)
            let shouldReprepare = (mode == .pay && !isPrefilledPayment) ||
                                  (paymentRequestData?.hasActiveTransport == false)
            if shouldReprepare {
                reprepareWithMint(newMint)
            }
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
            // Header with icon and amount
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 60, height: 60)

                    Image(systemName: lightningInvoice != nil ? "bolt.fill" : "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }

                // Lightning invoice
                if let invoice = lightningInvoice {
                    // Show total amount
                    Text(WalletManager.formatAmount(invoice.amount + invoice.feeReserve))
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.primary)

                    // Fee breakdown (only if fee > 0)
                    if invoice.feeReserve > 0 {
                        Text("\(WalletManager.formatAmount(invoice.amount)) + \(WalletManager.formatAmount(invoice.feeReserve)) Fee")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                // Payment request
                else if let request = paymentRequestData {
                    if let amount = request.amount {
                        // Show total if prepared with fee, otherwise show amount
                        if !request.hasActiveTransport, let prepared = preparedSendData {
                            Text(WalletManager.formatAmount(prepared.total))
                                .font(.system(size: 48, weight: .light))
                                .foregroundColor(.primary)

                            // Fee breakdown (only if fee > 0)
                            if prepared.fee > 0 {
                                Text("\(WalletManager.formatAmount(prepared.amount)) + \(WalletManager.formatAmount(prepared.fee)) Fee")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        } else if !request.hasActiveTransport && isPreparing {
                            Text(WalletManager.formatAmount(amount))
                                .font(.system(size: 48, weight: .light))
                                .foregroundColor(.primary)

                            HStack(spacing: 4) {
                                Text("Calculating fee")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                ProgressView()
                                    .scaleEffect(0.6)
                            }
                        } else {
                            Text(WalletManager.formatAmount(amount))
                                .font(.system(size: 48, weight: .light))
                                .foregroundColor(.primary)
                        }
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
                    }
                }
            }
            .padding(.top, 20)

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
                            Text("\(walletManager.getMintDisplayName(for: mint)) (\(WalletManager.formatAmount(mintBalances[mint] ?? 0)))")
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
                .disabled(isLoading || availableMints.isEmpty || hasInsufficientBalance || (paymentRequestData?.amount == nil && lightningInvoice == nil))

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

                // Show total amount for pay mode, input amount for request mode
                if mode == .pay && sentTotalAmount > 0 {
                    Text("Pay \(WalletManager.formatAmount(sentTotalAmount))")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.orange)
                } else {
                    Text("\(mode == .pay ? "Pay" : "Request") \u{20BF}\(displayAmount)")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.orange)
                }
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
                    writeContentViaNFC()
                }) {
                    Image(systemName: isWritingNFC ? "wave.3.right.circle.fill" : "wave.3.right.circle")
                        .font(.title3)
                        .foregroundColor(NFCPaymentService.isAvailable ? Color.orange : Color.gray)
                        .frame(width: 44, height: 44)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }
                .disabled(!NFCPaymentService.isAvailable || isWritingNFC)
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

    private func writeContentViaNFC() {
        isWritingNFC = true
        nfcService.writeContent(generatedContent) { result in
            DispatchQueue.main.async {
                isWritingNFC = false
                switch result {
                case .success:
                    AppLogger.network.info("Content written to NFC tag successfully")
                case .failure(let error):
                    AppLogger.network.error("NFC write failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private var inputFormView: some View {
        VStack(spacing: 20) {
            // Header section
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 60, height: 60)

                    Image(systemName: mode.iconName)
                        .font(.title)
                        .foregroundColor(Color.white)
                }
                .padding(.bottom, 8)

                // Show total if prepared, otherwise show amount
                if mode == .pay, let prepared = preparedSendData {
                    Text("Pay \(WalletManager.formatAmount(prepared.total))")
                        .font(.title2)
                        .bold()
                        .foregroundColor(Color.orange)

                    // Sub-header showing breakdown (only if fee > 0)
                    if prepared.fee > 0 {
                        Text("\(WalletManager.formatAmount(prepared.amount)) + \(WalletManager.formatAmount(prepared.fee)) Fee")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if mode == .pay && isPreparing {
                    Text("Pay \u{20BF}\(displayAmount)")
                        .font(.title2)
                        .bold()
                        .foregroundColor(Color.orange)

                    // Loading indicator for fee
                    HStack(spacing: 4) {
                        Text("Calculating fee")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                } else {
                    Text("\(mode == .pay ? "Pay" : "Request") \u{20BF}\(displayAmount)")
                        .font(.title2)
                        .bold()
                        .foregroundColor(Color.orange)
                }
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
                                Text("\(walletManager.getMintDisplayName(for: mint)) (\(WalletManager.formatAmount(mintBalances[mint] ?? 0)))")
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
            .disabled(isLoading || (mode == .pay && hasInsufficientBalance))
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

        // Load balances for each mint
        var balances: [String: UInt64] = [:]
        if let fetchedBalances = try? await walletManager.getMintBalances() {
            balances = fetchedBalances
        }

        // Determine required amount for payment (if applicable)
        let requiredAmount: UInt64? = {
            if let invoice = lightningInvoice {
                return invoice.amount + invoice.feeReserve
            } else if let request = paymentRequestData, let amount = request.amount {
                return amount
            }
            return nil
        }()

        await MainActor.run {
            self.availableMints = mints
            self.mintBalances = balances

            // Auto-select a mint with sufficient balance if possible
            if !mints.isEmpty && selectedMintUrl.isEmpty {
                if let required = requiredAmount {
                    // Find first mint with sufficient balance
                    if let mintWithFunds = mints.first(where: { (balances[$0] ?? 0) >= required }) {
                        self.selectedMintUrl = mintWithFunds
                    } else {
                        // No mint has sufficient funds, select first anyway
                        self.selectedMintUrl = mints[0]
                    }
                } else {
                    self.selectedMintUrl = mints[0]
                }
            }
            self.isLoadingMints = false
        }

        // Auto-prepare for Cashu sends after mints are loaded
        if mode == .pay && !isPrefilledPayment {
            if let firstMint = mints.first {
                await prepareSend(mintUrl: firstMint)
            }
        }

        // Auto-prepare for payment requests (no transport)
        if let request = paymentRequestData, !request.hasActiveTransport {
            if let firstMint = mints.first, let amount = request.amount {
                await prepareSendForPaymentRequest(mintUrl: firstMint, amount: amount)
            }
        }
    }

    /// Prepares a send operation to calculate fees
    private func prepareSend(mintUrl: String) async {
        guard let amountValue = UInt64(displayAmount), amountValue > 0 else { return }

        await MainActor.run {
            isPreparing = true
        }

        do {
            let (prepared, fee) = try await walletManager.prepareSendWithFee(mintUrl: mintUrl, amount: amountValue)
            await MainActor.run {
                self.preparedSendData = PreparedSendData(
                    preparedSend: prepared,
                    amount: amountValue,
                    fee: fee,
                    mintUrl: mintUrl
                )
                self.isPreparing = false
            }
        } catch {
            await MainActor.run {
                self.isPreparing = false
                AppLogger.network.error("Failed to prepare send: \(error.localizedDescription)")
            }
        }
    }

    /// Prepares a send for payment request with specific amount
    private func prepareSendForPaymentRequest(mintUrl: String, amount: UInt64) async {
        await MainActor.run {
            isPreparing = true
        }

        do {
            let (prepared, fee) = try await walletManager.prepareSendWithFee(mintUrl: mintUrl, amount: amount)
            await MainActor.run {
                self.preparedSendData = PreparedSendData(
                    preparedSend: prepared,
                    amount: amount,
                    fee: fee,
                    mintUrl: mintUrl
                )
                self.isPreparing = false
            }
        } catch {
            await MainActor.run {
                self.isPreparing = false
                AppLogger.network.error("Failed to prepare send for payment request: \(error.localizedDescription)")
            }
        }
    }

    /// Cancels current prepared send and prepares a new one with the given mint
    private func reprepareWithMint(_ mintUrl: String) {
        // Cancel existing prepared send
        if let existing = preparedSendData {
            Task {
                await walletManager.cancelPreparedSend(existing.preparedSend)
            }
            preparedSendData = nil
        }

        // Prepare new send
        Task {
            if let request = paymentRequestData, !request.hasActiveTransport, let amount = request.amount {
                await prepareSendForPaymentRequest(mintUrl: mintUrl, amount: amount)
            } else if mode == .pay && !isPrefilledPayment {
                await prepareSend(mintUrl: mintUrl)
            }
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

                    let token: String
                    let totalAmount: UInt64
                    if let prepared = preparedSendData, prepared.mintUrl == selectedMintUrl {
                        // Use prepared send
                        token = try await walletManager.confirmPreparedSend(
                            prepared.preparedSend,
                            memo: memo.isEmpty ? nil : memo
                        )
                        totalAmount = prepared.total
                        await MainActor.run {
                            self.preparedSendData = nil
                        }
                    } else {
                        // Fallback to direct send if not prepared
                        token = try await walletManager.send(
                            mintUrl: selectedMintUrl,
                            amount: amountValue,
                            memo: memo.isEmpty ? nil : memo
                        )
                        totalAmount = amountValue
                    }

                    await MainActor.run {
                        generatedContent = token
                        sentTotalAmount = totalAmount
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
                        let token: String
                        let totalAmount: UInt64
                        if let prepared = preparedSendData, prepared.mintUrl == selectedMintUrl {
                            // Use prepared send
                            token = try await walletManager.confirmPreparedSend(
                                prepared.preparedSend,
                                memo: request.description
                            )
                            totalAmount = prepared.total
                            await MainActor.run {
                                self.preparedSendData = nil
                            }
                        } else {
                            // Fallback to direct send if not prepared
                            token = try await walletManager.send(
                                mintUrl: selectedMintUrl,
                                amount: paymentAmount,
                                memo: request.description
                            )
                            totalAmount = paymentAmount
                        }

                        await MainActor.run {
                            walletManager.refreshBalance()
                            generatedContent = token
                            sentTotalAmount = totalAmount
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
