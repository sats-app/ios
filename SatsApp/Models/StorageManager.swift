import Foundation
import os.log

/// Manages wallet storage location using App Groups for extension access
/// Primary storage: App Groups container (shared with iMessage extension)
/// Backup/sync: iCloud Documents
class StorageManager {
    static let shared = StorageManager()

    private let walletDirectoryName = "Wallet"
    private let seedFileName = "seed.txt"
    private let databaseFileName = "wallet.db"
    private let appGroupIdentifier = "group.app.paywithsats"
    private let migrationCompleteKey = "walletMigrationComplete"

    private var _isUsingICloud: Bool = false
    private var _walletDirectory: URL?

    /// Whether iCloud is available for backup/sync
    var isUsingICloud: Bool { _isUsingICloud }

    /// The directory where wallet data (seed and database) is stored
    /// Uses App Groups container for extension access
    var walletDirectory: URL {
        if let dir = _walletDirectory {
            return dir
        }
        // This shouldn't happen if initialize() was called
        return getAppGroupWalletDirectory() ?? getLocalWalletDirectory()
    }

    /// Full path to the seed file
    var seedFileURL: URL {
        walletDirectory.appendingPathComponent(seedFileName)
    }

    /// Full path to the database file
    var databaseFileURL: URL {
        walletDirectory.appendingPathComponent(databaseFileName)
    }

    private init() {}

    /// Initialize the storage manager and determine storage location
    /// Uses App Groups as primary storage, migrating from iCloud/local if needed
    func initialize() {
        // Primary: App Groups container (required for extension access)
        if let appGroupDir = getAppGroupWalletDirectory() {
            _walletDirectory = appGroupDir

            // Check if iCloud is available for backup
            _isUsingICloud = FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil

            AppLogger.storage.info("Using App Groups storage: \(appGroupDir.path)")

            // Migrate existing data if needed
            migrateToAppGroupsIfNeeded()
        } else {
            // Fallback to local if App Groups not available (shouldn't happen)
            _walletDirectory = getLocalWalletDirectory()
            _isUsingICloud = false
            AppLogger.storage.warning("App Groups not available, using local storage: \(self._walletDirectory!.path)")
        }
    }

    /// Migrate wallet data from iCloud or local storage to App Groups container
    private func migrateToAppGroupsIfNeeded() {
        let defaults = UserDefaults.standard

        // Skip if migration already completed
        if defaults.bool(forKey: migrationCompleteKey) {
            return
        }

        let fileManager = FileManager.default
        let appGroupDir = walletDirectory

        // Check if App Groups already has wallet data
        let appGroupSeed = appGroupDir.appendingPathComponent(seedFileName)
        if fileManager.fileExists(atPath: appGroupSeed.path) {
            AppLogger.storage.debug("Wallet data already exists in App Groups, skipping migration")
            defaults.set(true, forKey: migrationCompleteKey)
            return
        }

        // Try to migrate from iCloud first
        if let iCloudDir = getICloudWalletDirectory() {
            let iCloudSeed = iCloudDir.appendingPathComponent(seedFileName)
            if fileManager.fileExists(atPath: iCloudSeed.path) {
                AppLogger.storage.info("Migrating wallet data from iCloud to App Groups")
                do {
                    try migrateDirectory(from: iCloudDir, to: appGroupDir)
                    defaults.set(true, forKey: migrationCompleteKey)
                    AppLogger.storage.info("Successfully migrated wallet from iCloud to App Groups")
                    return
                } catch {
                    AppLogger.storage.error("Failed to migrate from iCloud: \(error.localizedDescription)")
                }
            }
        }

        // Try to migrate from local storage
        let localDir = getLocalWalletDirectory()
        let localSeed = localDir.appendingPathComponent(seedFileName)
        if fileManager.fileExists(atPath: localSeed.path) {
            AppLogger.storage.info("Migrating wallet data from local storage to App Groups")
            do {
                try migrateDirectory(from: localDir, to: appGroupDir)
                defaults.set(true, forKey: migrationCompleteKey)
                AppLogger.storage.info("Successfully migrated wallet from local to App Groups")
                return
            } catch {
                AppLogger.storage.error("Failed to migrate from local: \(error.localizedDescription)")
            }
        }

        // No existing wallet to migrate
        AppLogger.storage.debug("No existing wallet data to migrate")
        defaults.set(true, forKey: migrationCompleteKey)
    }

    /// Copy all files from source directory to destination
    private func migrateDirectory(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default

        // Ensure destination exists
        if !fileManager.fileExists(atPath: destination.path) {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        }

        // Copy seed file
        let sourceSeed = source.appendingPathComponent(seedFileName)
        let destSeed = destination.appendingPathComponent(seedFileName)
        if fileManager.fileExists(atPath: sourceSeed.path) {
            if fileManager.fileExists(atPath: destSeed.path) {
                try fileManager.removeItem(at: destSeed)
            }
            try fileManager.copyItem(at: sourceSeed, to: destSeed)
        }

        // Copy database file
        let sourceDb = source.appendingPathComponent(databaseFileName)
        let destDb = destination.appendingPathComponent(databaseFileName)
        if fileManager.fileExists(atPath: sourceDb.path) {
            if fileManager.fileExists(atPath: destDb.path) {
                try fileManager.removeItem(at: destDb)
            }
            try fileManager.copyItem(at: sourceDb, to: destDb)

            // Also copy WAL and SHM files if they exist
            for suffix in ["-wal", "-shm"] {
                let sourceExtra = source.appendingPathComponent(databaseFileName + suffix)
                let destExtra = destination.appendingPathComponent(databaseFileName + suffix)
                if fileManager.fileExists(atPath: sourceExtra.path) {
                    if fileManager.fileExists(atPath: destExtra.path) {
                        try fileManager.removeItem(at: destExtra)
                    }
                    try fileManager.copyItem(at: sourceExtra, to: destExtra)
                }
            }
        }
    }

    /// Get App Groups container wallet directory
    private func getAppGroupWalletDirectory() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            AppLogger.storage.debug("App Groups container not available")
            return nil
        }
        return containerURL.appendingPathComponent(walletDirectoryName)
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

