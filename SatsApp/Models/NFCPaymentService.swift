import Foundation
import CoreNFC
import CashuDevKit

/// Result type for NFC payment operations
enum NFCPaymentResult {
    case success(amount: UInt64, fee: UInt64)
    case cancelled
    case error(NFCPaymentError)
}

/// Errors specific to NFC payment operations
enum NFCPaymentError: LocalizedError {
    case nfcNotAvailable
    case nfcNotSupported
    case tagConnectionFailed
    case invalidPaymentRequest(String)
    case noPaymentRequestFound
    case writeFailure(String)
    case readFailure(String)
    case insufficientBalance
    case userCancelled
    case sessionTimeout

    var errorDescription: String? {
        switch self {
        case .nfcNotAvailable:
            return "NFC is not available on this device"
        case .nfcNotSupported:
            return "This device does not support NFC payments"
        case .tagConnectionFailed:
            return "Failed to connect to payment terminal"
        case .invalidPaymentRequest(let detail):
            return "Invalid payment request: \(detail)"
        case .noPaymentRequestFound:
            return "No payment request found on terminal"
        case .writeFailure(let detail):
            return "Failed to complete payment: \(detail)"
        case .readFailure(let detail):
            return "Failed to read from terminal: \(detail)"
        case .insufficientBalance:
            return "Insufficient balance for this payment"
        case .userCancelled:
            return "Payment cancelled"
        case .sessionTimeout:
            return "NFC session timed out"
        }
    }
}

/// Data parsed from the terminal's payment request
struct NFCPaymentRequestData {
    let paymentRequest: PaymentRequest
    let encodedRequest: String
    let amount: UInt64
    let unit: String
    let description: String?
    let mintUrls: [String]
}

/// Service for handling NFC payments with Numo terminals
/// Uses NFCTagReaderSession for Type 4 NDEF tag read/write operations
class NFCPaymentService: NSObject, ObservableObject {

    // MARK: - Published State
    @Published var isScanning = false
    @Published var scanStatus: String = ""
    @Published var paymentRequest: NFCPaymentRequestData?
    @Published var isProcessing = false

    // MARK: - Private Properties
    private var session: NFCTagReaderSession?
    private var currentTag: NFCNDEFTag?

    // Callbacks for the payment flow
    private var onPaymentRequestRead: ((NFCPaymentRequestData) -> Void)?
    private var onPaymentComplete: ((NFCPaymentResult) -> Void)?

    // MARK: - Public Interface

    /// Check if NFC is available on this device
    static var isAvailable: Bool {
        return NFCTagReaderSession.readingAvailable
    }

    /// Start scanning for a payment terminal
    /// - Parameters:
    ///   - onPaymentRequestRead: Called when payment request is successfully read
    ///   - onComplete: Called when the entire payment flow completes
    func startPaymentScan(
        onPaymentRequestRead: @escaping (NFCPaymentRequestData) -> Void,
        onComplete: @escaping (NFCPaymentResult) -> Void
    ) {
        guard NFCPaymentService.isAvailable else {
            onComplete(.error(.nfcNotAvailable))
            return
        }

        self.onPaymentRequestRead = onPaymentRequestRead
        self.onPaymentComplete = onComplete

        // Create session for ISO 14443 tags (Type 4 NDEF)
        session = NFCTagReaderSession(
            pollingOption: [.iso14443],
            delegate: self,
            queue: nil
        )
        session?.alertMessage = "Hold your iPhone near the payment terminal"
        session?.begin()

        DispatchQueue.main.async {
            self.isScanning = true
            self.scanStatus = "Looking for payment terminal..."
        }

        AppLogger.network.info("NFC payment scan started")
    }

    /// Confirm and complete the payment by writing token to terminal
    /// - Parameters:
    ///   - token: The Cashu token to write
    ///   - amount: The payment amount
    ///   - fee: The fee amount
    func confirmPayment(token: String, amount: UInt64, fee: UInt64) {
        guard let tag = currentTag, let session = session else {
            onPaymentComplete?(.error(.tagConnectionFailed))
            cleanup()
            return
        }

        DispatchQueue.main.async {
            self.isProcessing = true
            self.scanStatus = "Completing payment..."
        }

        // Write the token as NDEF Text record
        writeTokenToTag(tag: tag, token: token, session: session) { [weak self] result in
            DispatchQueue.main.async {
                self?.isProcessing = false
                switch result {
                case .success:
                    session.alertMessage = "Payment complete!"
                    self?.onPaymentComplete?(.success(amount: amount, fee: fee))
                case .failure(let error):
                    session.alertMessage = "Payment failed"
                    self?.onPaymentComplete?(.error(error))
                }
                session.invalidate()
                self?.cleanup()
            }
        }
    }

    /// Cancel the current NFC session
    func cancelSession() {
        session?.invalidate()
        cleanup()
        onPaymentComplete?(.cancelled)
    }

    // MARK: - Write-Only Mode (for transmitting tokens/requests via NFC)

    private var onWriteComplete: ((Result<Void, NFCPaymentError>) -> Void)?
    private var contentToWrite: String?

    /// Write content (token or payment request) to an NFC tag
    /// - Parameters:
    ///   - content: The string content to write (Cashu token or payment request)
    ///   - onComplete: Called when write completes or fails
    func writeContent(
        _ content: String,
        onComplete: @escaping (Result<Void, NFCPaymentError>) -> Void
    ) {
        guard NFCPaymentService.isAvailable else {
            onComplete(.failure(.nfcNotAvailable))
            return
        }

        self.contentToWrite = content
        self.onWriteComplete = onComplete

        session = NFCTagReaderSession(
            pollingOption: [.iso14443],
            delegate: self,
            queue: nil
        )
        session?.alertMessage = "Hold your iPhone near an NFC tag"
        session?.begin()

        DispatchQueue.main.async {
            self.isScanning = true
            self.scanStatus = "Looking for NFC tag..."
        }

        AppLogger.network.info("NFC write scan started")
    }

    // MARK: - Private Methods

    private func cleanup() {
        DispatchQueue.main.async {
            self.isScanning = false
            self.isProcessing = false
            self.scanStatus = ""
            self.paymentRequest = nil
        }
        session = nil
        currentTag = nil
        onPaymentRequestRead = nil
        onPaymentComplete = nil
        onWriteComplete = nil
        contentToWrite = nil
    }

    /// Parse payment request from NDEF Text record
    private func parsePaymentRequest(from message: NFCNDEFMessage) -> NFCPaymentRequestData? {
        for record in message.records {
            // Check for Text record type
            guard record.typeNameFormat == .nfcWellKnown,
                  let type = String(data: record.type, encoding: .utf8),
                  type == "T" else {
                continue
            }

            // Parse text payload (first byte is language code length)
            let payload = record.payload
            guard payload.count > 1 else { continue }

            let languageCodeLength = Int(payload[0] & 0x3F)
            guard payload.count > languageCodeLength + 1 else { continue }

            let textData = payload.subdata(in: (1 + languageCodeLength)..<payload.count)
            guard let text = String(data: textData, encoding: .utf8) else { continue }

            // Check for creq prefix (NUT-18 payment request)
            guard text.lowercased().hasPrefix("creq") else { continue }

            do {
                let paymentRequest = try PaymentRequest.fromString(encoded: text)
                let amount = paymentRequest.amount()?.value ?? 0
                // Default to "sat" - this app only supports sat unit
                let unit = "sat"
                let description = paymentRequest.description()
                let mints = paymentRequest.mints() ?? []

                return NFCPaymentRequestData(
                    paymentRequest: paymentRequest,
                    encodedRequest: text,
                    amount: amount,
                    unit: unit,
                    description: description,
                    mintUrls: mints
                )
            } catch {
                AppLogger.network.error("Failed to parse payment request: \(error.localizedDescription)")
                continue
            }
        }
        return nil
    }

    /// Write Cashu token to the tag as NDEF Text record
    private func writeTokenToTag(
        tag: NFCNDEFTag,
        token: String,
        session: NFCTagReaderSession,
        completion: @escaping (Result<Void, NFCPaymentError>) -> Void
    ) {
        // Create NDEF Text record with the token
        // Format: [status byte][language code][text]
        let languageCode = "en"
        var payload = Data()
        payload.append(UInt8(languageCode.count))  // Status byte (language code length)
        payload.append(languageCode.data(using: .utf8)!)
        payload.append(token.data(using: .utf8)!)

        let textRecord = NFCNDEFPayload(
            format: .nfcWellKnown,
            type: "T".data(using: .utf8)!,
            identifier: Data(),
            payload: payload
        )

        let message = NFCNDEFMessage(records: [textRecord])

        tag.writeNDEF(message) { error in
            if let error = error {
                AppLogger.network.error("NDEF write failed: \(error.localizedDescription)")
                completion(.failure(.writeFailure(error.localizedDescription)))
            } else {
                AppLogger.network.info("NDEF write successful")
                completion(.success(()))
            }
        }
    }
}

// MARK: - NFCTagReaderSessionDelegate

extension NFCPaymentService: NFCTagReaderSessionDelegate {

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        AppLogger.network.debug("NFC session became active")
        DispatchQueue.main.async {
            self.scanStatus = "Ready to scan..."
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        AppLogger.network.debug("NFC session invalidated: \(error.localizedDescription)")

        let nfcError = error as? NFCReaderError
        if nfcError?.code != .readerSessionInvalidationErrorUserCanceled {
            // Only report non-user-cancelled errors
            DispatchQueue.main.async {
                if self.contentToWrite != nil {
                    // Write-only mode
                    self.onWriteComplete?(.failure(.sessionTimeout))
                } else {
                    // Payment mode
                    self.onPaymentComplete?(.error(.sessionTimeout))
                }
                self.cleanup()
            }
        } else {
            DispatchQueue.main.async {
                self.cleanup()
            }
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else {
            session.alertMessage = "No tag found"
            session.invalidate()
            return
        }

        // Connect to the tag
        session.connect(to: tag) { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                AppLogger.network.error("Tag connection failed: \(error.localizedDescription)")
                session.alertMessage = "Connection failed"
                session.invalidate()
                if self.contentToWrite != nil {
                    self.onWriteComplete?(.failure(.tagConnectionFailed))
                } else {
                    self.onPaymentComplete?(.error(.tagConnectionFailed))
                }
                return
            }

            // Get NDEF tag interface
            var ndefTag: NFCNDEFTag?
            switch tag {
            case .iso7816(let iso7816Tag):
                ndefTag = iso7816Tag
            case .miFare(let mifareTag):
                ndefTag = mifareTag
            default:
                session.alertMessage = "Unsupported tag type"
                session.invalidate()
                if self.contentToWrite != nil {
                    self.onWriteComplete?(.failure(.tagConnectionFailed))
                } else {
                    self.onPaymentComplete?(.error(.tagConnectionFailed))
                }
                return
            }

            guard let ndef = ndefTag else {
                session.alertMessage = "Tag does not support NDEF"
                session.invalidate()
                return
            }

            self.currentTag = ndef

            // Query NDEF status
            ndef.queryNDEFStatus { status, capacity, error in
                if let error = error {
                    AppLogger.network.error("NDEF status query failed: \(error.localizedDescription)")
                    session.alertMessage = "Cannot access tag"
                    session.invalidate()
                    if self.contentToWrite != nil {
                        self.onWriteComplete?(.failure(.readFailure(error.localizedDescription)))
                    } else {
                        self.onPaymentComplete?(.error(.readFailure(error.localizedDescription)))
                    }
                    return
                }

                guard status == .readWrite else {
                    session.alertMessage = "Tag not ready"
                    session.invalidate()
                    if self.contentToWrite != nil {
                        self.onWriteComplete?(.failure(.readFailure("Tag is not read/write")))
                    } else {
                        self.onPaymentComplete?(.error(.readFailure("Tag is not read/write")))
                    }
                    return
                }

                // Branch based on mode
                if let content = self.contentToWrite {
                    // Write-only mode: just write the content
                    self.writeTokenToTag(tag: ndef, token: content, session: session) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success:
                                session.alertMessage = "Content written successfully!"
                                self.onWriteComplete?(.success(()))
                            case .failure(let error):
                                session.alertMessage = "Write failed"
                                self.onWriteComplete?(.failure(error))
                            }
                            session.invalidate()
                            self.cleanup()
                        }
                    }
                    return
                }

                // Payment mode: Read NDEF message
                ndef.readNDEF { message, error in
                    if let error = error {
                        AppLogger.network.error("NDEF read failed: \(error.localizedDescription)")
                        session.alertMessage = "Cannot read payment request"
                        session.invalidate()
                        self.onPaymentComplete?(.error(.readFailure(error.localizedDescription)))
                        return
                    }

                    guard let message = message else {
                        session.alertMessage = "No payment request found"
                        session.invalidate()
                        self.onPaymentComplete?(.error(.noPaymentRequestFound))
                        return
                    }

                    // Parse payment request
                    guard let requestData = self.parsePaymentRequest(from: message) else {
                        session.alertMessage = "Invalid payment request"
                        session.invalidate()
                        self.onPaymentComplete?(.error(.invalidPaymentRequest("Could not parse")))
                        return
                    }

                    AppLogger.network.info("Payment request read: amount=\(requestData.amount) \(requestData.unit)")

                    // Update session message to prompt for confirmation
                    session.alertMessage = "Payment request received. Keep phone near terminal."

                    DispatchQueue.main.async {
                        self.paymentRequest = requestData
                        self.scanStatus = "Payment request received"
                        self.onPaymentRequestRead?(requestData)
                    }

                    // Note: Session stays open - we'll write the response when user confirms
                }
            }
        }
    }
}
