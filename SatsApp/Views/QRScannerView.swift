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
    @Published var isReady = false
    @Published var permissionStatus: AVAuthorizationStatus = .notDetermined

    let codesPublisher = URCodesPublisher()
    @MainActor lazy var scanState = URScanState(codesPublisher: codesPublisher)

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let queue = DispatchQueue(label: "qr-scanner", qos: .userInteractive)
    private var lastCodes: Set<String> = []
    private var metadataDelegate: MetadataDelegate?

    override init() {
        super.init()
        // Don't setup capture session here - wait for permission check
    }

    func checkAndRequestPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        await MainActor.run {
            self.permissionStatus = status
        }

        switch status {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run {
                self.permissionStatus = granted ? .authorized : .denied
                if granted {
                    self.setupCaptureSession()
                } else {
                    self.isSupported = false
                }
            }
        case .authorized:
            await MainActor.run {
                self.setupCaptureSession()
            }
        case .denied, .restricted:
            await MainActor.run {
                self.isSupported = false
            }
        @unknown default:
            break
        }
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

            DispatchQueue.main.async {
                self.isReady = true
            }

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

class CameraPreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let controller: CameraScannerController

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black

        if let previewLayer = controller.getPreviewLayer() {
            view.previewLayer = previewLayer
            view.layer.addSublayer(previewLayer)
        }

        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Preview layer frame is updated in layoutSubviews
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
    @State private var defaultMintName: String = ""
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
            Task {
                await cameraController.checkAndRequestPermission()
                cameraController.startRunning()
            }
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
        if cameraController.isSupported && cameraController.isReady {
            CameraPreviewView(controller: cameraController)
                .ignoresSafeArea()
        } else if cameraController.permissionStatus == .denied || cameraController.permissionStatus == .restricted {
            // Permission denied - show Settings button
            Color.black
                .ignoresSafeArea()
                .overlay(
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("Camera Access Required")
                            .foregroundColor(.white)
                            .font(.headline)
                        Text("Please enable camera access in Settings to scan QR codes")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Button("Open Settings") {
                            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsURL)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding(.top, 8)
                        Text("Use paste button to test")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.7))
                    }
                )
        } else {
            // Simulator fallback or permission not yet determined
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
        Button("Trust Mint") {
            if let details = tokenDetails {
                receiveWithTrust(details, trustMint: true)
            }
        }
        if !defaultMintName.isEmpty {
            Button("Transfer to \(defaultMintName)") {
                if let details = tokenDetails {
                    receiveWithTrust(details, trustMint: false)
                }
            }
        }
    }

    @ViewBuilder
    private var trustAlertMessage: some View {
        if let details = tokenDetails {
            let mintHost = URL(string: details.mintUrl)?.host ?? details.mintUrl
            let amount = WalletManager.formatAmount(details.amount)
            Text("This token (\(amount)) is from \(mintHost). Trust this mint to receive directly, or transfer to your default mint.")
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
        let tokenPrefix = String(tokenString.prefix(20))
        AppLogger.ui.info("Processing cashu token: \(tokenPrefix)...")

        state = .processingToken(tokenString)
        cameraController.stopRunning()

        Task {
            do {
                // Step 1: Parse the token to get mint URL and amount
                AppLogger.ui.debug("Step 1: Parsing token...")
                let (mintUrl, amount) = try await walletManager.parseToken(tokenString: tokenString)
                AppLogger.ui.debug("Token parsed: mint=\(mintUrl), amount=\(amount)")

                // Step 2: Check if the mint is already trusted
                AppLogger.ui.debug("Step 2: Checking if mint is trusted...")
                let isTrusted = await walletManager.isMintTrusted(mintUrl: mintUrl)
                AppLogger.ui.info("Mint trust check: \(mintUrl) -> trusted=\(isTrusted)")

                if isTrusted {
                    // Mint is trusted, proceed with normal receive
                    AppLogger.ui.debug("Step 3: Mint trusted, receiving directly...")
                    let receivedAmount = try await walletManager.receive(tokenString: tokenString)
                    AppLogger.ui.info("Token received successfully: \(receivedAmount) sats")
                    await MainActor.run {
                        walletManager.refreshBalance()
                        onTokenReceived?(receivedAmount)
                        dismiss()
                    }
                } else {
                    // Mint is not trusted, show trust alert
                    AppLogger.ui.info("Mint not trusted, showing trust alert for: \(mintUrl)")
                    let defaultMint = await walletManager.getDefaultMint()
                    let mintName = defaultMint.map { walletManager.getMintDisplayName(for: $0) } ?? ""
                    AppLogger.ui.debug("Default mint for transfer option: \(defaultMint ?? "none") (\(mintName))")

                    await MainActor.run {
                        tokenDetails = TokenDetails(tokenString: tokenString, mintUrl: mintUrl, amount: amount)
                        defaultMintName = mintName
                        state = .untrustedMint(TokenDetails(tokenString: tokenString, mintUrl: mintUrl, amount: amount))
                        showingTrustAlert = true
                    }
                }
            } catch {
                AppLogger.ui.error("processCashuToken failed - Type: \(String(describing: type(of: error))), Description: \(error.localizedDescription), Details: \(String(describing: error))")
                await MainActor.run {
                    state = .error("Failed to process token: \(error.localizedDescription)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        resetScanner()
                    }
                }
            }
        }
    }

    /// Handle the user's trust decision for an untrusted mint token
    /// - Parameters:
    ///   - details: The token details including token string, mint URL, and amount
    ///   - trustMint: If true, trust the mint and receive directly. If false, transfer to default mint.
    private func receiveWithTrust(_ details: TokenDetails, trustMint: Bool) {
        AppLogger.ui.info("User trust decision: trustMint=\(trustMint) for mint=\(details.mintUrl)")
        state = .processingToken(details.tokenString)

        Task {
            do {
                AppLogger.ui.debug("Calling walletManager.receiveToken(trustMint: \(trustMint))...")
                let amount = try await walletManager.receiveToken(
                    tokenString: details.tokenString,
                    trustMint: trustMint
                )

                AppLogger.ui.info("receiveWithTrust completed successfully: \(amount) sats")
                await MainActor.run {
                    walletManager.refreshBalance()
                    onTokenReceived?(amount)
                    dismiss()
                }
            } catch {
                AppLogger.ui.error("receiveWithTrust failed - Type: \(String(describing: type(of: error))), Description: \(error.localizedDescription), Details: \(String(describing: error))")
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
