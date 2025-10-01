import Foundation
import CashuDevKit

/// Local in-memory cache for wallet data that doesn't use Amplify models
/// Handles Mints, KeySets, Keys, and other non-generated model storage
/// NOTE: With CDK 0.13.0+, types are now Codable and API has changed significantly
/// TODO: Refactor to use the new Codable types and updated APIs
actor LocalWalletCache {
    private let logger = AppLogger.wallet

    // In-memory storage (will be lost on app restart)
    // NOTE: Types have changed in CDK 0.13.0 - needs refactoring
    private var mintsCache: [String: MintInfo?] = [:]
    private var keysetsCache: [String: [KeySetInfo]] = [:]
    private var keysCache: [String: Any] = [:]  // Temporarily using Any until we understand new structure
    private var countersCache: [String: UInt32] = [:]

    init() {
        logger.debug("LocalWalletCache initialized with in-memory storage")
    }
}

// MARK: - Mint Management
extension LocalWalletCache {

    func addMint(url: MintUrl, info: MintInfo?) async throws {
        let urlString = String(describing: url)
        mintsCache[urlString] = info
        logger.debug("Added mint: \(urlString, privacy: .public)")
    }

    func removeMint(url: MintUrl) async throws {
        let urlString = String(describing: url)
        mintsCache.removeValue(forKey: urlString)
        logger.debug("Removed mint: \(urlString, privacy: .public)")
    }

    func getMint(url: MintUrl) async throws -> MintInfo? {
        let urlString = String(describing: url)
        return mintsCache[urlString] ?? nil
    }

    func getAllMints() async throws -> [MintUrl: MintInfo?] {
        let result: [MintUrl: MintInfo?] = [:]
        // Note: MintUrl type needs to be reconstructed from String
        // This is a temporary workaround until we understand the new API
        return result
    }

    func updateMintUrl(from oldUrl: MintUrl, to newUrl: MintUrl) async throws {
        let oldUrlString = String(describing: oldUrl)
        let newUrlString = String(describing: newUrl)
        if let mintInfo = mintsCache.removeValue(forKey: oldUrlString) {
            mintsCache[newUrlString] = mintInfo
            logger.debug("Updated mint URL from \(oldUrlString, privacy: .public) to \(newUrlString, privacy: .public)")
        }
    }
}

// MARK: - Keyset Management
extension LocalWalletCache {

    func addKeysets(mintUrl: MintUrl, keysets: [KeySetInfo]) async throws {
        let urlString = String(describing: mintUrl)
        keysetsCache[urlString] = keysets
        logger.debug("Added \(keysets.count) keysets for mint: \(urlString, privacy: .public)")
    }

    func getKeysets(mintUrl: MintUrl) async throws -> [KeySetInfo]? {
        let urlString = String(describing: mintUrl)
        return keysetsCache[urlString]
    }

    func getKeyset(id: Id) async throws -> KeySetInfo? {
        let idString = String(describing: id)
        for (_, keysets) in keysetsCache {
            if let keyset = keysets.first(where: { String(describing: $0.id) == idString }) {
                return keyset
            }
        }
        return nil
    }
}

// MARK: - Keys Management
extension LocalWalletCache {

    func addKeys(keyset: KeySet) async throws {
        let keysetIdString = String(describing: keyset.id)
        keysCache[keysetIdString] = keyset.keys
        logger.debug("Added keys for keyset: \(keysetIdString, privacy: .public)")
    }

    func getKeys(id: Id) async throws -> Keys? {
        let idString = String(describing: id)
        return keysCache[idString] as? Keys
    }

    func removeKeys(id: Id) async throws {
        let idString = String(describing: id)
        keysCache.removeValue(forKey: idString)
        logger.debug("Removed keys for ID: \(idString, privacy: .public)")
    }
}

// MARK: - Keyset Counter Management
extension LocalWalletCache {

    func incrementKeysetCounter(keysetId: Id, count: UInt32) async throws -> UInt32 {
        let keysetIdString = String(describing: keysetId)
        let currentCount = countersCache[keysetIdString] ?? 0
        let newCount = currentCount + count
        countersCache[keysetIdString] = newCount

        logger.debug("Incremented counter for keyset \(keysetIdString, privacy: .public) by \(count), new total: \(newCount)")
        return newCount
    }
}