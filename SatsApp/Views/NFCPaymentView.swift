import SwiftUI
import CashuDevKit

/// View for handling NFC tap-to-pay flow with Numo terminals
struct NFCPaymentView: View {
    @EnvironmentObject var walletManager: WalletManager
    @StateObject private var nfcService = NFCPaymentService()
    @Environment(\.dismiss) private var dismiss

    // Payment state
    @State private var paymentRequest: NFCPaymentRequestData?
    @State private var selectedMintUrl: String = ""
    @State private var availableMints: [String] = []
    @State private var mintBalances: [String: UInt64] = [:]
    @State private var preparedSend: PreparedSend?
    @State private var fee: UInt64 = 0
    @State private var isPreparingPayment = false
    @State private var paymentResult: NFCPaymentResult?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let result = paymentResult {
                    resultView(result)
                } else if let request = paymentRequest {
                    confirmationView(request)
                } else if nfcService.isScanning {
                    scanningView
                } else {
                    startView
                }
            }
            .navigationTitle("NFC Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        nfcService.cancelSession()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            startNFCScan()
        }
        .task {
            await loadMints()
        }
    }

    // MARK: - Views

    private var startView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.orange)

            Text("Ready to Pay")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tap 'Start' to begin scanning for payment terminal")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Start NFC Scan") {
                startNFCScan()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.orange)
            .foregroundColor(.white)
            .cornerRadius(12)
            .font(.headline)
            .padding(.horizontal, 40)
        }
        .padding()
    }

    private var scanningView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.orange.opacity(0.3), lineWidth: 4)
                    .frame(width: 120, height: 120)

                Image(systemName: "wave.3.right")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
            }

            Text("Scanning...")
                .font(.title2)
                .fontWeight(.semibold)

            Text(nfcService.scanStatus)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Hold your iPhone near the payment terminal")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding()
    }

    private func confirmationView(_ request: NFCPaymentRequestData) -> some View {
        VStack(spacing: 20) {
            // Amount display
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 60, height: 60)

                    Image(systemName: "wave.3.right")
                        .font(.title)
                        .foregroundColor(.white)
                }

                Text(WalletManager.formatAmount(request.amount + fee))
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(.primary)

                if fee > 0 {
                    Text("\(WalletManager.formatAmount(request.amount)) + \(WalletManager.formatAmount(fee)) fee")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let desc = request.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // Mint selector
            if !availableMints.isEmpty {
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

            // Status text
            if nfcService.isProcessing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Completing payment...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Keep your phone near the terminal")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Confirm button
            Button(action: confirmPayment) {
                HStack {
                    if isPreparingPayment || nfcService.isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    Text(isPreparingPayment ? "Preparing..." :
                         nfcService.isProcessing ? "Processing..." : "Confirm Payment")
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(hasInsufficientBalance ? Color.gray : Color.orange)
            .foregroundColor(.white)
            .cornerRadius(12)
            .font(.headline)
            .disabled(isPreparingPayment || nfcService.isProcessing || hasInsufficientBalance)

            if hasInsufficientBalance {
                Text("Insufficient balance")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .onChange(of: selectedMintUrl) { newMint in
            Task {
                await preparePayment(mintUrl: newMint, amount: request.amount)
            }
        }
        .task {
            // Auto-prepare when mint is selected
            if !selectedMintUrl.isEmpty {
                await preparePayment(mintUrl: selectedMintUrl, amount: request.amount)
            }
        }
    }

    private func resultView(_ result: NFCPaymentResult) -> some View {
        VStack(spacing: 20) {
            Spacer()

            switch result {
            case .success(let amount, _):
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 100, height: 100)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                }

                Text("Payment Complete!")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(WalletManager.formatAmount(amount))
                    .font(.title3)
                    .foregroundColor(.secondary)

            case .cancelled:
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 100, height: 100)

                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                }

                Text("Payment Cancelled")
                    .font(.title2)
                    .fontWeight(.semibold)

            case .error(let error):
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 100, height: 100)

                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                }

                Text("Payment Failed")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(error.localizedDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

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
        .padding()
    }

    // MARK: - Computed Properties

    private var hasInsufficientBalance: Bool {
        guard !selectedMintUrl.isEmpty, let request = paymentRequest else { return false }
        let balance = mintBalances[selectedMintUrl] ?? 0
        return balance < (request.amount + fee)
    }

    // MARK: - Methods

    private func startNFCScan() {
        nfcService.startPaymentScan(
            onPaymentRequestRead: { request in
                self.paymentRequest = request
                // Auto-select first mint with sufficient balance
                if let mint = availableMints.first(where: { (mintBalances[$0] ?? 0) >= request.amount }) {
                    selectedMintUrl = mint
                } else if let firstMint = availableMints.first {
                    selectedMintUrl = firstMint
                }
            },
            onComplete: { result in
                self.paymentResult = result
                if case .success = result {
                    walletManager.refreshBalance()
                }
            }
        )
    }

    private func loadMints() async {
        let mints = await walletManager.getMints()
        let balances = (try? await walletManager.getMintBalances()) ?? [:]

        await MainActor.run {
            self.availableMints = mints
            self.mintBalances = balances
            if selectedMintUrl.isEmpty, let firstMint = mints.first {
                selectedMintUrl = firstMint
            }
        }
    }

    private func preparePayment(mintUrl: String, amount: UInt64) async {
        guard !mintUrl.isEmpty else { return }

        await MainActor.run {
            isPreparingPayment = true
        }

        do {
            let (prepared, calculatedFee) = try await walletManager.prepareSendWithFee(
                mintUrl: mintUrl,
                amount: amount
            )
            await MainActor.run {
                self.preparedSend = prepared
                self.fee = calculatedFee
                self.isPreparingPayment = false
            }
        } catch {
            await MainActor.run {
                self.isPreparingPayment = false
                AppLogger.network.error("Failed to prepare NFC payment: \(error.localizedDescription)")
            }
        }
    }

    private func confirmPayment() {
        guard let request = paymentRequest else { return }

        Task {
            do {
                let token: String
                if let prepared = preparedSend {
                    token = try await walletManager.confirmPreparedSend(prepared, memo: request.description)
                } else {
                    token = try await walletManager.send(
                        mintUrl: selectedMintUrl,
                        amount: request.amount,
                        memo: request.description
                    )
                }

                await MainActor.run {
                    nfcService.confirmPayment(token: token, amount: request.amount, fee: fee)
                }
            } catch {
                await MainActor.run {
                    paymentResult = .error(.writeFailure(error.localizedDescription))
                }
            }
        }
    }
}
