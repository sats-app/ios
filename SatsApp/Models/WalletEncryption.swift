import Foundation
import CryptoKit
import CashuDevKit

/// Handles wallet data encryption using AES-GCM-128 with the user's seed as the private key
actor WalletEncryption {
    private let logger = AppLogger.wallet
    private var encryptionKey: SymmetricKey?

    init() {}

    /// Initialize encryption with the user's mnemonic seed
    func initializeEncryption(with mnemonic: String) throws {
        // Derive a consistent key from the mnemonic
        let keyData = try deriveKeyFromMnemonic(mnemonic)
        self.encryptionKey = SymmetricKey(data: keyData)
        logger.debug("Wallet encryption initialized")
    }

    /// Encrypt data using AES-GCM-128
    func encrypt(_ data: Data) throws -> String {
        guard let key = encryptionKey else {
            throw WalletEncryptionError.encryptionNotInitialized
        }

        do {
            let sealedBox = try AES.GCM.seal(data, using: key)

            // Combine nonce and ciphertext for storage
            var combinedData = Data()
            combinedData.append(sealedBox.nonce.withUnsafeBytes { Data($0) })
            combinedData.append(sealedBox.ciphertext)
            combinedData.append(sealedBox.tag)

            return combinedData.base64EncodedString()
        } catch {
            logger.error("Failed to encrypt data: \(error.localizedDescription)")
            throw WalletEncryptionError.encryptionFailed(error.localizedDescription)
        }
    }

    /// Decrypt data using AES-GCM-128
    func decrypt(_ encryptedString: String) throws -> Data {
        guard let key = encryptionKey else {
            throw WalletEncryptionError.encryptionNotInitialized
        }

        guard let combinedData = Data(base64Encoded: encryptedString) else {
            throw WalletEncryptionError.invalidEncryptedData
        }

        do {
            // AES-GCM nonce is 12 bytes, tag is 16 bytes
            let nonceSize = 12
            let tagSize = 16

            guard combinedData.count >= nonceSize + tagSize else {
                throw WalletEncryptionError.invalidEncryptedData
            }

            let nonce = combinedData.prefix(nonceSize)
            let ciphertext = combinedData.dropFirst(nonceSize).dropLast(tagSize)
            let tag = combinedData.suffix(tagSize)

            let gcmNonce = try AES.GCM.Nonce(data: nonce)
            let sealedBox = try AES.GCM.SealedBox(nonce: gcmNonce, ciphertext: ciphertext, tag: tag)

            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            logger.error("Failed to decrypt data: \(error.localizedDescription)")
            throw WalletEncryptionError.decryptionFailed(error.localizedDescription)
        }
    }

    /// Derive a consistent encryption key from the mnemonic
    private func deriveKeyFromMnemonic(_ mnemonic: String) throws -> Data {
        // Use PBKDF2 to derive a key from the mnemonic
        let salt = "SatsApp.WalletEncryption.Salt".data(using: .utf8)!
        let iterations = 100_000 // PBKDF2 iterations

        guard let mnemonicData = mnemonic.data(using: .utf8) else {
            throw WalletEncryptionError.invalidMnemonic
        }

        // Use PBKDF2 from CryptoKit (available on iOS 13+)
        var derivedKey = Data(count: 32) // 256 bits for AES-256, but we'll use first 16 bytes for AES-128
        let derivedKeyLength = derivedKey.count

        let status = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            mnemonicData.withUnsafeBytes { mnemonicBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        mnemonicBytes.bindMemory(to: Int8.self).baseAddress,
                        mnemonicData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                        derivedKeyLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw WalletEncryptionError.keyDerivationFailed
        }

        // Use first 16 bytes for AES-128
        return derivedKey.prefix(16)
    }
}

// MARK: - Error Types
enum WalletEncryptionError: LocalizedError {
    case encryptionNotInitialized
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidEncryptedData
    case invalidMnemonic
    case keyDerivationFailed

    var errorDescription: String? {
        switch self {
        case .encryptionNotInitialized:
            return "Wallet encryption has not been initialized"
        case .encryptionFailed(let message):
            return "Encryption failed: \(message)"
        case .decryptionFailed(let message):
            return "Decryption failed: \(message)"
        case .invalidEncryptedData:
            return "Invalid encrypted data format"
        case .invalidMnemonic:
            return "Invalid mnemonic format"
        case .keyDerivationFailed:
            return "Failed to derive encryption key from mnemonic"
        }
    }
}

// Import for CommonCrypto PBKDF2
import CommonCrypto