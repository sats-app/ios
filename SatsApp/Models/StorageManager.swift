import Foundation
import os.log

/// Manages wallet storage location, preferring iCloud Documents with local fallback
class StorageManager {
    static let shared = StorageManager()

    private let walletDirectoryName = "Wallet"
    private let seedFileName = "seed.txt"

    private var _isUsingICloud: Bool = false
    private var _walletDirectory: URL?

    /// Whether the wallet data is stored in iCloud
    var isUsingICloud: Bool { _isUsingICloud }

    /// The directory where wallet data (seed and database) is stored
    var walletDirectory: URL {
        if let dir = _walletDirectory {
            return dir
        }
        // This shouldn't happen if initialize() was called
        return getLocalWalletDirectory()
    }

    /// Full path to the seed file
    var seedFileURL: URL {
        walletDirectory.appendingPathComponent(seedFileName)
    }

    private init() {}

    /// Initialize the storage manager and determine storage location
    /// Call this early in app startup
    func initialize() {
        if let iCloudDir = getICloudWalletDirectory() {
            _walletDirectory = iCloudDir
            _isUsingICloud = true
            AppLogger.storage.info("Using iCloud storage: \(iCloudDir.path)")
        } else {
            _walletDirectory = getLocalWalletDirectory()
            _isUsingICloud = false
            AppLogger.storage.info("Using local storage (iCloud unavailable): \(self._walletDirectory!.path)")
        }
    }

    /// Ensures the wallet directory exists
    func ensureDirectoryExists() throws {
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: walletDirectory.path) {
            try fileManager.createDirectory(
                at: walletDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            AppLogger.storage.debug("Created wallet directory: \(self.walletDirectory.path)")
        }
    }

    /// Check if a seed file already exists
    func seedExists() -> Bool {
        FileManager.default.fileExists(atPath: seedFileURL.path)
    }

    /// Load the mnemonic from the seed file
    func loadMnemonic() throws -> String {
        let data = try Data(contentsOf: seedFileURL)
        guard let mnemonic = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw StorageError.invalidSeedFile
        }

        // Validate mnemonic has expected word count
        let words = mnemonic.split(separator: " ")
        guard words.count == 12 || words.count == 24 else {
            throw StorageError.invalidMnemonicWordCount(count: words.count)
        }

        AppLogger.storage.debug("Loaded mnemonic from seed file")
        return mnemonic
    }

    /// Save the mnemonic to the seed file
    func saveMnemonic(_ mnemonic: String) throws {
        try ensureDirectoryExists()

        guard let data = mnemonic.data(using: .utf8) else {
            throw StorageError.failedToEncodeMnemonic
        }

        // Write with file protection
        try data.write(to: seedFileURL, options: [.atomic, .completeFileProtection])

        // Set file attributes for additional protection
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: seedFileURL.path
        )

        AppLogger.storage.info("Saved mnemonic to seed file")
    }

    // MARK: - Private Helpers

    private func getICloudWalletDirectory() -> URL? {
        guard let iCloudContainer = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            AppLogger.storage.debug("iCloud container not available")
            return nil
        }

        // Use Documents subdirectory within iCloud container
        let documentsDir = iCloudContainer.appendingPathComponent("Documents")
        return documentsDir.appendingPathComponent(walletDirectoryName)
    }

    private func getLocalWalletDirectory() -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDir.appendingPathComponent(walletDirectoryName)
    }
}

enum StorageError: LocalizedError {
    case invalidSeedFile
    case invalidMnemonicWordCount(count: Int)
    case failedToEncodeMnemonic

    var errorDescription: String? {
        switch self {
        case .invalidSeedFile:
            return "Seed file is invalid or corrupted"
        case .invalidMnemonicWordCount(let count):
            return "Invalid mnemonic word count: \(count). Expected 12 or 24 words."
        case .failedToEncodeMnemonic:
            return "Failed to encode mnemonic"
        }
    }
}

