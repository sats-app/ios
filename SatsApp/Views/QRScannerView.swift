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
    case processingPaymentRequest(String)
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
        case (.processingPaymentRequest(let l), .processingPaymentRequest(let r)):
            return l == r
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

struct TokenDetails {
    let tokenString: String
    let mintUrl: String
    let amount: UInt64
}

// MARK: - Callback Data Types

/// Data passed when a Lightning invoice is scanned
struct LightningInvoiceData {
    let invoice: String
    let amount: UInt64
    let feeReserve: UInt64
    let quoteId: String
    let mintUrl: String
}

/// Data passed when a NUT-18 payment request is scanned
struct ScannedPaymentRequestData {
    let paymentRequest: PaymentRequest
    let encodedRequest: String
    let amount: UInt64?
    let description: String?
    /// True if request has HTTP or Nostr transport for automatic delivery
    let hasActiveTransport: Bool
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

    /// Callback when a Lightning invoice is scanned (for payment)
    var onLightningInvoiceScanned: ((LightningInvoiceData) -> Void)?

    /// Callback when a NUT-18 payment request is scanned (for payment)
    var onPaymentRequestScanned: ((ScannedPaymentRequestData) -> Void)?

    // Camera scanner controller - manages AVFoundation and URScanState
    @StateObject private var cameraController = CameraScannerController()

    @State private var state: ScannerState = .scanning
    @State private var showingResultSheet = false
    @State private var showingTrustAlert = false
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
        ScannerCornersView()
            .frame(width: 260, height: 260)
    }

    // MARK: - Status Text

    @ViewBuilder
    private var statusText: some View {
        Group {
            switch state {
            case .scanning:
                EmptyView()
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
            // Payment success (legacy - new flow uses TransactView)
            SuccessView(successType: .paymentSent(amount: amount)) {
                dismiss()
            }
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
                let cbor = ur.cbor
                // Extract bytes from CBOR
                if case CBOR.bytes(let data) = cbor {
                    if let content = String(data: Data(data), encoding: .utf8) {
                        handleScannedContent(content)
                    }
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
        // Check for NUT-18 Payment Request (creqA prefix)
        else if lowercased.hasPrefix("creq") {
            processPaymentRequest(trimmed)
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
                    let data = LightningInvoiceData(
                        invoice: invoice,
                        amount: amount,
                        feeReserve: feeReserve,
                        quoteId: quoteId,
                        mintUrl: firstMint
                    )
                    onLightningInvoiceScanned?(data)
                    dismiss()
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

    // MARK: - Payment Request Processing

    private func processPaymentRequest(_ encoded: String) {
        state = .processingPaymentRequest(encoded)
        cameraController.stopRunning()

        Task {
            do {
                // Decode the payment request
                let paymentRequest = try PaymentRequest.fromString(encoded: encoded)

                // Extract amount - Amount is a struct with a value property
                let amountObj = paymentRequest.amount()
                let amount: UInt64? = amountObj?.value
                AppLogger.ui.info("Payment request amount object: \(String(describing: amountObj)), value: \(String(describing: amount))")

                let description = paymentRequest.description()

                // Check for active transports (HTTP or Nostr)
                let transports = paymentRequest.transports()
                let hasActiveTransport = transports.contains { transport in
                    transport.transportType == .httpPost || transport.transportType == .nostr
                }
                AppLogger.ui.info("Payment request transports: \(transports.count), hasActiveTransport: \(hasActiveTransport)")

                await MainActor.run {
                    let data = ScannedPaymentRequestData(
                        paymentRequest: paymentRequest,
                        encodedRequest: encoded,
                        amount: amount,
                        description: description,
                        hasActiveTransport: hasActiveTransport
                    )
                    onPaymentRequestScanned?(data)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    state = .error("Invalid payment request: \(error.localizedDescription)")
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
           trimmed.hasPrefix("lightning:") || trimmed.hasPrefix("cashu") || trimmed.hasPrefix("creq") {
            cameraController.stopRunning()
            handleScannedContent(content)
        } else {
            state = .error("No valid invoice, token, or request in clipboard")
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
        tokenDetails = nil
        cameraController.scanState.restart()
        cameraController.resetScanningState()
        cameraController.startRunning()
    }
}

// MARK: - Scanner Corners View

struct ScannerCornersView: View {
    let cornerLength: CGFloat = 25
    let lineWidth: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let offset = lineWidth / 2

            // Top-left
            Path { path in
                path.move(to: CGPoint(x: offset, y: cornerLength))
                path.addLine(to: CGPoint(x: offset, y: offset))
                path.addLine(to: CGPoint(x: cornerLength, y: offset))
            }
            .stroke(Color.orange, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            // Top-right
            Path { path in
                path.move(to: CGPoint(x: geo.size.width - cornerLength, y: offset))
                path.addLine(to: CGPoint(x: geo.size.width - offset, y: offset))
                path.addLine(to: CGPoint(x: geo.size.width - offset, y: cornerLength))
            }
            .stroke(Color.orange, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            // Bottom-left
            Path { path in
                path.move(to: CGPoint(x: offset, y: geo.size.height - cornerLength))
                path.addLine(to: CGPoint(x: offset, y: geo.size.height - offset))
                path.addLine(to: CGPoint(x: cornerLength, y: geo.size.height - offset))
            }
            .stroke(Color.orange, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            // Bottom-right
            Path { path in
                path.move(to: CGPoint(x: geo.size.width - cornerLength, y: geo.size.height - offset))
                path.addLine(to: CGPoint(x: geo.size.width - offset, y: geo.size.height - offset))
                path.addLine(to: CGPoint(x: geo.size.width - offset, y: geo.size.height - cornerLength))
            }
            .stroke(Color.orange, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
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
