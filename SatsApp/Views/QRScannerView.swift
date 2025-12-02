import SwiftUI
@preconcurrency import AVFoundation
import URKit
import URUI
import Combine
import CashuDevKit

// MARK: - Scanner State

enum ScannerState: Equatable {
    case scanning
    case urProgress(Double)
    case processingBolt11(String)
    case processingToken(String)
    case confirmPayment(PaymentDetails)
    case untrustedMint(TokenDetails)
    case success(SuccessType)
    case error(String)

    static func == (lhs: ScannerState, rhs: ScannerState) -> Bool {
        switch (lhs, rhs) {
        case (.scanning, .scanning):
            return true
        case (.urProgress(let l), .urProgress(let r)):
            return l == r
        case (.processingBolt11(let l), .processingBolt11(let r)):
            return l == r
        case (.processingToken(let l), .processingToken(let r)):
            return l == r
        case (.confirmPayment(let l), .confirmPayment(let r)):
            return l.invoice == r.invoice
        case (.untrustedMint(let l), .untrustedMint(let r)):
            return l.mintUrl == r.mintUrl
        case (.success(let l), .success(let r)):
            return l == r
        case (.error(let l), .error(let r)):
            return l == r
        default:
            return false
        }
    }
}

enum SuccessType: Equatable {
    case paymentSent(amount: UInt64)
    case tokenReceived(amount: UInt64)
}

struct PaymentDetails {
    let invoice: String
    let amount: UInt64
    let feeReserve: UInt64
    let quoteId: String
    let availableMints: [String]
    var selectedMint: String
}

struct TokenDetails {
    let tokenString: String
    let mintUrl: String
    let amount: UInt64
}

// MARK: - Camera Scanner Controller

class CameraScannerController: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var isSupported = true

    let codesPublisher = URCodesPublisher()
    @MainActor lazy var scanState = URScanState(codesPublisher: codesPublisher)

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let queue = DispatchQueue(label: "qr-scanner", qos: .userInteractive)
    private var lastCodes: Set<String> = []
    private var metadataDelegate: MetadataDelegate?

    override init() {
        super.init()
        setupCaptureSession()
    }

    private func setupCaptureSession() {
        #if targetEnvironment(simulator)
        DispatchQueue.main.async {
            self.isSupported = false
        }
        return
        #else

        guard let device = AVCaptureDevice.default(for: .video) else {
            DispatchQueue.main.async {
                self.isSupported = false
            }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            let session = AVCaptureSession()

            guard session.canAddInput(input) else {
                DispatchQueue.main.async {
                    self.isSupported = false
                }
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                DispatchQueue.main.async {
                    self.isSupported = false
                }
                return
            }
            session.addOutput(output)
            output.metadataObjectTypes = [.qr]

            metadataDelegate = MetadataDelegate { [weak self] codes in
                self?.handleCodes(codes)
            }
            output.setMetadataObjectsDelegate(metadataDelegate, queue: queue)

            captureSession = session
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer?.videoGravity = .resizeAspectFill

        } catch {
            DispatchQueue.main.async {
                self.isSupported = false
            }
        }
        #endif
    }

    private func handleCodes(_ codes: Set<String>) {
        if !codes.isEmpty, codes != lastCodes {
            lastCodes = codes
            codesPublisher.send(codes)
        }
    }

    func startRunning() {
        guard let session = captureSession, !session.isRunning else { return }
        queue.async { [weak self] in
            session.startRunning()
            DispatchQueue.main.async {
                self?.isRunning = true
            }
        }
    }

    func stopRunning() {
        guard let session = captureSession, session.isRunning else { return }
        queue.async { [weak self] in
            session.stopRunning()
            DispatchQueue.main.async {
                self?.isRunning = false
            }
        }
    }

    func resetScanningState() {
        lastCodes = []
    }

    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        return previewLayer
    }

    // Separate delegate class to avoid actor isolation issues
    private class MetadataDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let handler: (Set<String>) -> Void

        init(handler: @escaping (Set<String>) -> Void) {
            self.handler = handler
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            let codes = Set(metadataObjects.compactMap {
                ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue
            })
            handler(codes)
        }
    }
}

// MARK: - Camera Preview UIViewRepresentable

struct CameraPreviewView: UIViewRepresentable {
    let controller: CameraScannerController

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        if let previewLayer = controller.getPreviewLayer() {
            previewLayer.frame = view.bounds
            view.layer.addSublayer(previewLayer)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = controller.getPreviewLayer() {
            previewLayer.frame = uiView.bounds
        }
    }
}

// MARK: - QR Scanner View

struct QRScannerView: View {
    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.dismiss) private var dismiss

    /// Callback when a cashu token is successfully received
    var onTokenReceived: ((UInt64) -> Void)?

    // Camera scanner controller - manages AVFoundation and URScanState
    @StateObject private var cameraController = CameraScannerController()

    @State private var state: ScannerState = .scanning
    @State private var showingResultSheet = false
    @State private var showingTrustAlert = false
    @State private var paymentDetails: PaymentDetails?
    @State private var tokenDetails: TokenDetails?
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        ZStack {
            // Camera preview (full screen)
            cameraPreview

            // Overlay content
            VStack {
                topBar

                Spacer()

                // UR progress indicator (during animated QR scan)
                if case .urProgress(let progress) = state {
                    URProgressView(progress: progress)
                        .padding(.horizontal, 40)
                }

                // Scan frame
                scanFrameOverlay

                // Status text
                statusText

                Spacer()

                bottomBar
            }
        }
        .onAppear {
            setupScanResultHandler()
            cameraController.startRunning()
        }
        .onDisappear {
            cameraController.stopRunning()
        }
        .sheet(isPresented: $showingResultSheet) {
            resultSheetContent
        }
        .alert("Trust This Mint?", isPresented: $showingTrustAlert) {
            trustAlertButtons
        } message: {
            trustAlertMessage
        }
        .onChange(of: state) { newState in
            handleStateChange(newState)
        }
    }

    // MARK: - Camera Preview

    @ViewBuilder
    private var cameraPreview: some View {
        if cameraController.isSupported {
            CameraPreviewView(controller: cameraController)
                .ignoresSafeArea()
        } else {
            // Simulator fallback
            Color.black
                .ignoresSafeArea()
                .overlay(
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("Camera not available")
                            .foregroundColor(.gray)
                        Text("Use paste button to test")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.7))
                    }
                )
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }

            Spacer()

            Text("Scan QR Code")
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            // Placeholder for symmetry
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Scan Frame Overlay

    private var scanFrameOverlay: some View {
        ZStack {
            // Outer rounded rectangle stroke
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.orange, lineWidth: 3)
                .frame(width: 280, height: 280)

            // Corner accents
            ScannerCornersView()
                .frame(width: 280, height: 280)
        }
    }

    // MARK: - Status Text

    @ViewBuilder
    private var statusText: some View {
        Group {
            switch state {
            case .scanning:
                Text("Point camera at a QR code")
            case .urProgress(let progress):
                Text("Scanning animated QR: \(Int(progress * 100))%")
            case .processingBolt11:
                Text("Processing invoice...")
            case .processingToken:
                Text("Receiving token...")
            case .error(let message):
                Text(message)
                    .foregroundColor(.red)
            default:
                EmptyView()
            }
        }
        .font(.subheadline)
        .foregroundColor(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.6))
        .cornerRadius(8)
        .padding(.top, 20)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        Button(action: pasteFromClipboard) {
            VStack(spacing: 4) {
                Image(systemName: "doc.on.clipboard")
                    .font(.title2)
                Text("Paste")
                    .font(.caption)
            }
            .foregroundColor(.white)
            .padding(12)
            .background(Color.black.opacity(0.5))
            .cornerRadius(12)
        }
        .padding(.bottom, 40)
    }

    // MARK: - Result Sheet

    @ViewBuilder
    private var resultSheetContent: some View {
        if case .success(.paymentSent(let amount)) = state {
            // Payment success stays in scanner context
            SuccessView(successType: .paymentSent(amount: amount)) {
                dismiss()
            }
        } else if case .confirmPayment(_) = state, let payment = paymentDetails {
            PaymentConfirmationView(
                paymentDetails: payment,
                onPaymentComplete: { amount in
                    state = .success(.paymentSent(amount: amount))
                },
                onCancel: {
                    showingResultSheet = false
                    resetScanner()
                }
            )
        }
    }

    // MARK: - Trust Alert

    @ViewBuilder
    private var trustAlertButtons: some View {
        Button("Cancel", role: .cancel) {
            resetScanner()
        }
        Button("Add Mint") {
            if let details = tokenDetails {
                trustAndReceiveToken(details)
            }
        }
    }

    @ViewBuilder
    private var trustAlertMessage: some View {
        if let details = tokenDetails {
            Text("Adding \(URL(string: details.mintUrl)?.host ?? details.mintUrl) means trusting it to hold your funds. Only add mints you trust.")
        }
    }

    // MARK: - Scan Result Handling

    private func setupScanResultHandler() {
        cameraController.scanState.resultPublisher
            .receive(on: DispatchQueue.main)
            .sink { [self] result in
                handleScanResult(result)
            }
            .store(in: &cancellables)
    }

    private func handleScanResult(_ result: URScanResult) {
        switch result {
        case .ur(let ur):
            // Decode UR payload (bytes type contains the actual content)
            if ur.type == "bytes" {
                do {
                    let cbor = ur.cbor
                    // Extract bytes from CBOR
                    if case CBOR.bytes(let data) = cbor {
                        if let content = String(data: Data(data), encoding: .utf8) {
                            handleScannedContent(content)
                        }
                    }
                } catch {
                    AppLogger.ui.error("Failed to decode UR: \(error.localizedDescription)")
                    state = .error("Failed to decode QR code")
                }
            } else {
                AppLogger.ui.debug("Unsupported UR type: \(ur.type)")
                state = .error("Unsupported QR format")
            }

        case .other(let code):
            // Static QR code (not UR format)
            handleScannedContent(code)

        case .progress(let progress):
            // Multi-part UR in progress
            state = .urProgress(progress.estimatedPercentComplete)

        case .reject:
            // Rejected fragment (wrong UR type mid-scan)
            AppLogger.ui.debug("UR fragment rejected")

        case .failure(let error):
            state = .error("Scan error: \(error.localizedDescription)")
        }
    }

    private func handleScannedContent(_ content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        // Check for Bolt11 Lightning invoice
        if lowercased.hasPrefix("lightning:") {
            let invoice = String(trimmed.dropFirst(10))
            processLightningInvoice(invoice)
        } else if lowercased.hasPrefix("lnbc") || lowercased.hasPrefix("lntb") || lowercased.hasPrefix("lnbcrt") {
            processLightningInvoice(trimmed)
        }
        // Check for Cashu token (v3: cashuA, v4: cashuB)
        else if lowercased.hasPrefix("cashu") {
            processCashuToken(trimmed)
        }
        // Unknown format
        else {
            AppLogger.ui.debug("Unknown QR content: \(trimmed.prefix(50))...")
            state = .error("Unrecognized QR code format")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                resetScanner()
            }
        }
    }

    // MARK: - Lightning Invoice Processing

    private func processLightningInvoice(_ invoice: String) {
        state = .processingBolt11(invoice)
        cameraController.stopRunning()

        Task {
            do {
                let mints = await walletManager.getMints()
                guard let firstMint = mints.first else {
                    await MainActor.run {
                        state = .error("No mints configured")
                    }
                    return
                }

                // Get melt quote to determine amount and fees
                let (quoteId, amount, feeReserve) = try await walletManager.generateMeltQuote(
                    mintUrl: firstMint,
                    invoice: invoice
                )

                await MainActor.run {
                    let details = PaymentDetails(
                        invoice: invoice,
                        amount: amount,
                        feeReserve: feeReserve,
                        quoteId: quoteId,
                        availableMints: mints,
                        selectedMint: firstMint
                    )
                    paymentDetails = details
                    state = .confirmPayment(details)
                    showingResultSheet = true
                }
            } catch {
                await MainActor.run {
                    state = .error("Failed to decode invoice: \(error.localizedDescription)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        resetScanner()
                    }
                }
            }
        }
    }

    // MARK: - Cashu Token Processing

    private func processCashuToken(_ tokenString: String) {
        state = .processingToken(tokenString)
        cameraController.stopRunning()

        Task {
            do {
                // Try to receive with allowUntrusted: false
                let amount = try await walletManager.receive(tokenString: tokenString)

                await MainActor.run {
                    walletManager.refreshBalance()
                    // Call callback and dismiss - TransactView will show the success sheet
                    onTokenReceived?(amount)
                    dismiss()
                }
            } catch {
                // Check if error is due to untrusted mint
                let errorString = error.localizedDescription.lowercased()
                if errorString.contains("untrusted") || errorString.contains("unknown mint") || errorString.contains("not in wallet") {
                    // For untrusted mint, we show a simpler error since we can't easily extract mint info
                    // User can add the mint manually in settings and try again
                    await MainActor.run {
                        state = .error("Token from untrusted mint. Add the mint in settings first.")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            resetScanner()
                        }
                    }
                } else {
                    await MainActor.run {
                        state = .error("Failed to receive: \(error.localizedDescription)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            resetScanner()
                        }
                    }
                }
            }
        }
    }

    private func extractTokenInfo(_ tokenString: String) -> (mintUrl: String, amount: UInt64)? {
        // Parse mint URL from cashu token format
        // cashuA or cashuB tokens contain the mint URL in the encoded data
        // For now, extract from error message or use a default approach

        // Try to extract mint URL from the token string format
        // Cashu tokens typically have the mint URL embedded
        // Format: cashu[A|B]<base64 encoded data>

        // Since the CDK Token API doesn't expose mint directly,
        // we'll extract the mint URL from the error message when receive fails
        // This function returns nil to trigger the simpler error flow
        return nil
    }

    private func trustAndReceiveToken(_ details: TokenDetails) {
        Task {
            do {
                // First add the mint
                try await walletManager.addMint(mintUrl: details.mintUrl)

                // Then receive with allowUntrusted: true (now the mint should be trusted)
                let amount = try await walletManager.receive(tokenString: details.tokenString)

                await MainActor.run {
                    walletManager.refreshBalance()
                    // Call callback and dismiss - TransactView will show the success sheet
                    onTokenReceived?(amount)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    state = .error("Failed to receive: \(error.localizedDescription)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        resetScanner()
                    }
                }
            }
        }
    }

    // MARK: - State Change Handler

    private func handleStateChange(_ newState: ScannerState) {
        // Handle any state-specific logic here
    }

    // MARK: - Clipboard

    private func pasteFromClipboard() {
        // Access clipboard only when button is pressed (triggers iOS permission dialog here)
        guard let content = UIPasteboard.general.string else {
            state = .error("Clipboard is empty")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if case .error = state {
                    state = .scanning
                }
            }
            return
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Check if clipboard contains valid scannable content
        if trimmed.hasPrefix("lnbc") || trimmed.hasPrefix("lntb") || trimmed.hasPrefix("lnbcrt") ||
           trimmed.hasPrefix("lightning:") || trimmed.hasPrefix("cashu") {
            cameraController.stopRunning()
            handleScannedContent(content)
        } else {
            state = .error("No valid invoice or token in clipboard")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if case .error = state {
                    state = .scanning
                }
            }
        }
    }

    // MARK: - Reset Scanner

    private func resetScanner() {
        state = .scanning
        paymentDetails = nil
        tokenDetails = nil
        cameraController.scanState.restart()
        cameraController.resetScanningState()
        cameraController.startRunning()
    }
}

// MARK: - Scanner Corners View

struct ScannerCornersView: View {
    let cornerLength: CGFloat = 30
    let lineWidth: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            // Top-left
            Path { path in
                path.move(to: CGPoint(x: 0, y: cornerLength))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: cornerLength, y: 0))
            }
            .stroke(Color.orange, lineWidth: lineWidth)

            // Top-right
            Path { path in
                path.move(to: CGPoint(x: geo.size.width - cornerLength, y: 0))
                path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                path.addLine(to: CGPoint(x: geo.size.width, y: cornerLength))
            }
            .stroke(Color.orange, lineWidth: lineWidth)

            // Bottom-left
            Path { path in
                path.move(to: CGPoint(x: 0, y: geo.size.height - cornerLength))
                path.addLine(to: CGPoint(x: 0, y: geo.size.height))
                path.addLine(to: CGPoint(x: cornerLength, y: geo.size.height))
            }
            .stroke(Color.orange, lineWidth: lineWidth)

            // Bottom-right
            Path { path in
                path.move(to: CGPoint(x: geo.size.width - cornerLength, y: geo.size.height))
                path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - cornerLength))
            }
            .stroke(Color.orange, lineWidth: lineWidth)
        }
    }
}

// MARK: - UR Progress View

struct URProgressView: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .orange))

            Text("Scanning animated QR code...")
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
    }
}

// MARK: - Success View

struct SuccessView: View {
    let successType: SuccessType
    let onDismiss: () -> Void

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

            switch successType {
            case .paymentSent(let amount):
                Text("Payment Sent!")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(WalletManager.formatAmount(amount))
                    .font(.title3)
                    .foregroundColor(.secondary)

            case .tokenReceived(let amount):
                Text("Received!")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(WalletManager.formatAmount(amount))
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
        .onAppear {
            // Auto-dismiss after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                onDismiss()
            }
        }
    }
}

// MARK: - Payment Confirmation View

struct PaymentConfirmationView: View {
    @EnvironmentObject var walletManager: WalletManager

    let paymentDetails: PaymentDetails
    var onPaymentComplete: ((UInt64) -> Void)?
    var onCancel: (() -> Void)?

    @State private var selectedMint: String
    @State private var isProcessing = false
    @State private var showingError = false
    @State private var errorMessage = ""

    init(paymentDetails: PaymentDetails, onPaymentComplete: ((UInt64) -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        self.paymentDetails = paymentDetails
        self.onPaymentComplete = onPaymentComplete
        self.onCancel = onCancel
        _selectedMint = State(initialValue: paymentDetails.selectedMint)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header with icon
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 60, height: 60)

                    Image(systemName: "bolt.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }

                Text("Pay Lightning Invoice")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
            }
            .padding(.top, 20)

            // Amount display
            Text(WalletManager.formatAmount(paymentDetails.amount))
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.primary)

            // Fee display
            HStack {
                Text("Network Fee")
                    .foregroundColor(.secondary)
                Spacer()
                Text("+ \(WalletManager.formatAmount(paymentDetails.feeReserve))")
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
                Text(WalletManager.formatAmount(paymentDetails.amount + paymentDetails.feeReserve))
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)

            // Mint selector
            HStack {
                Image(systemName: "building.columns")
                    .foregroundColor(.orange)
                    .font(.subheadline)

                Picker("Mint", selection: $selectedMint) {
                    ForEach(paymentDetails.availableMints, id: \.self) { mint in
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

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button(action: executePayment) {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(isProcessing ? "Processing..." : "Confirm Payment")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
                .font(.headline)
                .disabled(isProcessing)

                Button("Cancel") {
                    onCancel?()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.gray.opacity(0.1))
                .foregroundColor(.primary)
                .cornerRadius(12)
                .font(.headline)
                .disabled(isProcessing)
            }
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 20)
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func executePayment() {
        isProcessing = true

        Task {
            do {
                let (amount, _) = try await walletManager.meltTokens(
                    mintUrl: selectedMint,
                    invoice: paymentDetails.invoice
                )

                await MainActor.run {
                    walletManager.refreshBalance()
                    onPaymentComplete?(amount)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isProcessing = false
                }
            }
        }
    }
}

// MARK: - WalletManager Extension

extension WalletManager {
    static func formatAmount(_ sats: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return "\u{20BF}" + (formatter.string(from: NSNumber(value: sats)) ?? "0")
    }
}
