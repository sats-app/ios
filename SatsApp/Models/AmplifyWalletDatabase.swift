import Foundation
import Amplify
import CashuDevKit

/// Amplify-based implementation of WalletDatabase using generated data models
final class AmplifyWalletDatabase: WalletDatabase, @unchecked Sendable {
    private let logger = AppLogger.wallet
    private let localCache: LocalWalletCache
    private let walletEncryption: WalletEncryption
    private weak var authManager: AuthManager?

    init(walletEncryption: WalletEncryption, authManager: AuthManager?) {
        self.localCache = LocalWalletCache()
        self.walletEncryption = walletEncryption
        self.authManager = authManager
    }

    // MARK: - WalletDatabase Protocol Implementation
    // MARK: - Mint Management
    func addMint(mintUrl: CashuDevKit.MintUrl, mintInfo: CashuDevKit.MintInfo?) async throws {
        logger.debug("Adding mint: \(String(describing: mintUrl))")
        try await localCache.addMint(url: mintUrl, info: mintInfo)
    }

    func removeMint(mintUrl: CashuDevKit.MintUrl) async throws {
        logger.debug("Removing mint: \(String(describing: mintUrl))")
        try await localCache.removeMint(url: mintUrl)
    }

    func getMint(mintUrl: CashuDevKit.MintUrl) async throws -> CashuDevKit.MintInfo? {
        return try await localCache.getMint(url: mintUrl)
    }

    func getMints() async throws -> [CashuDevKit.MintUrl: CashuDevKit.MintInfo?] {
        let mints = try await localCache.getAllMints()
        return mints
    }

    func updateMintUrl(oldMintUrl: CashuDevKit.MintUrl, newMintUrl: CashuDevKit.MintUrl) async throws {
        logger.debug("Updating mint URL from \(String(describing: oldMintUrl)) to \(String(describing: newMintUrl))")
        try await localCache.updateMintUrl(from: oldMintUrl, to: newMintUrl)
    }

    // MARK: - Keyset Management
    func addMintKeysets(mintUrl: CashuDevKit.MintUrl, keysets: [CashuDevKit.KeySetInfo]) async throws {
        logger.debug("Adding keysets for mint: \(String(describing: mintUrl))")
        try await localCache.addKeysets(mintUrl: mintUrl, keysets: keysets)
    }

    func getMintKeysets(mintUrl: CashuDevKit.MintUrl) async throws -> [CashuDevKit.KeySetInfo]? {
        return try await localCache.getKeysets(mintUrl: mintUrl)
    }

    func getKeysetById(keysetId: CashuDevKit.Id) async throws -> CashuDevKit.KeySetInfo? {
        return try await localCache.getKeyset(id: keysetId)
    }

    func addKeys(keyset: CashuDevKit.KeySet) async throws {
        logger.debug("Adding keyset: \(String(describing: keyset.id))")
        try await localCache.addKeys(keyset: keyset)
    }

    func getKeys(id: CashuDevKit.Id) async throws -> CashuDevKit.Keys? {
        return try await localCache.getKeys(id: id)
    }

    func removeKeys(id: CashuDevKit.Id) async throws {
        logger.debug("Removing keys: \(String(describing: id))")
        try await localCache.removeKeys(id: id)
    }

    func incrementKeysetCounter(keysetId: CashuDevKit.Id, count: UInt32) async throws -> UInt32 {
        return try await localCache.incrementKeysetCounter(keysetId: keysetId, count: count)
    }

    // MARK: - Mint Quote Management
    func addMintQuote(quote: CashuDevKit.MintQuote) async throws {
        logger.debug("Adding mint quote: \(quote.id)")

        do {
            // Serialize the quote data
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let quoteData = try encoder.encode(quote)
            let encryptedData = try await encryptData(quoteData)

            // Create Amplify model - qualify with SatsApp to avoid ambiguity
            let amplifyQuote = MintQuote(
                quoteId: quote.id,
                encryptedQuote: encryptedData,
                state: mapMintQuoteState(quote.state),
                owner: await getCurrentUserId()
            )

            let savedQuote = try await Amplify.DataStore.save(amplifyQuote)
            logger.debug("Mint quote saved with ID: \(savedQuote.id)")

        } catch {
            logger.error("Failed to add mint quote: \(error.localizedDescription)")
            throw error
        }
    }

    func getMintQuote(quoteId: String) async throws -> CashuDevKit.MintQuote? {
        logger.debug("Getting mint quote: \(quoteId)")

        do {
            let predicate = MintQuote.keys.quoteId.eq(quoteId)
            let quotes = try await Amplify.DataStore.query(MintQuote.self, where: predicate)

            guard let amplifyQuote = quotes.first else {
                return nil
            }

            // Decrypt and deserialize
            let decryptedData = try await decryptData(amplifyQuote.encryptedQuote)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            return try decoder.decode(CashuDevKit.MintQuote.self, from: decryptedData)

        } catch {
            logger.error("Failed to get mint quote: \(error.localizedDescription)")
            throw error
        }
    }

    func getMintQuotes() async throws -> [CashuDevKit.MintQuote] {
        logger.debug("Getting all mint quotes")

        do {
            let userId = await getCurrentUserId()
            let predicate = MintQuote.keys.owner.eq(userId)
            let amplifyQuotes = try await Amplify.DataStore.query(MintQuote.self, where: predicate)

            var quotes: [CashuDevKit.MintQuote] = []
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            for amplifyQuote in amplifyQuotes {
                do {
                    let decryptedData = try await decryptData(amplifyQuote.encryptedQuote)
                    let quote = try decoder.decode(CashuDevKit.MintQuote.self, from: decryptedData)
                    quotes.append(quote)
                } catch {
                    logger.error("Failed to decrypt/decode quote \(amplifyQuote.id, privacy: .public): \(error.localizedDescription)")
                    // Continue with other quotes
                }
            }

            return quotes

        } catch {
            logger.error("Failed to get mint quotes: \(error.localizedDescription)")
            throw error
        }
    }

    func removeMintQuote(quoteId: String) async throws {
        logger.debug("Removing mint quote: \(quoteId)")

        do {
            let predicate = MintQuote.keys.quoteId.eq(quoteId)
            let quotes = try await Amplify.DataStore.query(MintQuote.self, where: predicate)

            if let quoteToDelete = quotes.first {
                try await Amplify.DataStore.delete(quoteToDelete)
                logger.debug("Mint quote removed: \(quoteId)")
            }

        } catch {
            logger.error("Failed to remove mint quote: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Melt Quote Management
    func addMeltQuote(quote: CashuDevKit.MeltQuote) async throws {
        logger.debug("Adding melt quote: \(quote.id)")

        do {
            // Serialize the quote data
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let quoteData = try encoder.encode(quote)
            let encryptedData = try await encryptData(quoteData)

            // Create Amplify model
            let amplifyQuote = MeltQuote(
                quoteId: quote.id,
                encryptedQuote: encryptedData,
                state: mapMeltQuoteState(quote.state),
                owner: await getCurrentUserId()
            )

            let savedQuote = try await Amplify.DataStore.save(amplifyQuote)
            logger.debug("Melt quote saved with ID: \(savedQuote.id)")

        } catch {
            logger.error("Failed to add melt quote: \(error.localizedDescription)")
            throw error
        }
    }

    func getMeltQuote(quoteId: String) async throws -> CashuDevKit.MeltQuote? {
        logger.debug("Getting melt quote: \(quoteId)")

        do {
            let predicate = MeltQuote.keys.quoteId.eq(quoteId)
            let quotes = try await Amplify.DataStore.query(MeltQuote.self, where: predicate)

            guard let amplifyQuote = quotes.first else {
                return nil
            }

            // Decrypt and deserialize
            let decryptedData = try await decryptData(amplifyQuote.encryptedQuote)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            return try decoder.decode(CashuDevKit.MeltQuote.self, from: decryptedData)

        } catch {
            logger.error("Failed to get melt quote: \(error.localizedDescription)")
            throw error
        }
    }

    func getMeltQuotes() async throws -> [CashuDevKit.MeltQuote] {
        logger.debug("Getting all melt quotes")

        do {
            let userId = await getCurrentUserId()
            let predicate = MeltQuote.keys.owner.eq(userId)
            let amplifyQuotes = try await Amplify.DataStore.query(MeltQuote.self, where: predicate)

            var quotes: [CashuDevKit.MeltQuote] = []
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            for amplifyQuote in amplifyQuotes {
                do {
                    let decryptedData = try await decryptData(amplifyQuote.encryptedQuote)
                    let quote = try decoder.decode(CashuDevKit.MeltQuote.self, from: decryptedData)
                    quotes.append(quote)
                } catch {
                    logger.error("Failed to decrypt/decode melt quote \(amplifyQuote.id): \(error.localizedDescription)")
                    // Continue with other quotes
                }
            }

            return quotes

        } catch {
            logger.error("Failed to get melt quotes: \(error.localizedDescription)")
            throw error
        }
    }

    func removeMeltQuote(quoteId: String) async throws {
        logger.debug("Removing melt quote: \(quoteId)")

        do {
            let predicate = MeltQuote.keys.quoteId.eq(quoteId)
            let quotes = try await Amplify.DataStore.query(MeltQuote.self, where: predicate)

            if let quoteToDelete = quotes.first {
                try await Amplify.DataStore.delete(quoteToDelete)
                logger.debug("Melt quote removed: \(quoteId)")
            }

        } catch {
            logger.error("Failed to remove melt quote: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Proof Management
    func updateProofs(added: [CashuDevKit.ProofInfo], removedYs: [CashuDevKit.PublicKey]) async throws {
        logger.debug("Updating proofs: adding \(added.count), removing \(removedYs.count)")

        // Remove proofs by Y values
        for publicKey in removedYs {
            let publicKeyString = publicKey.hex
            let predicate = Proof.keys.proofId.eq(publicKeyString)
            let proofsToRemove = try await Amplify.DataStore.query(Proof.self, where: predicate)

            for proofToRemove in proofsToRemove {
                try await Amplify.DataStore.delete(proofToRemove)
            }
        }

        // Add new proofs
        // NOTE: ProofInfo is not Codable in cdk-swift 0.13.1, so we cannot store proofs in Amplify yet
        // This functionality will be re-enabled when CDK types become Codable
        for proofInfo in added {
            logger.debug("Would add proof with Y: \(proofInfo.y.hex) (storage not implemented)")
            // TODO: Implement when ProofInfo becomes Codable
            // let encoder = JSONEncoder()
            // let proofData = try encoder.encode(proofInfo)
            // let encryptedData = try await encryptData(proofData)
            //
            // let amplifyProof = Proof(
            //     proofId: proofInfo.y.hex,
            //     encryptedProof: encryptedData,
            //     state: mapProofState(proofInfo.state),
            //     owner: await getCurrentUserId()
            // )
            //
            // try await Amplify.DataStore.save(amplifyProof)
        }

        logger.debug("Proofs update completed (storage not implemented)")
    }

    func getProofs(mintUrl: CashuDevKit.MintUrl?, unit: CashuDevKit.CurrencyUnit?, state: [CashuDevKit.ProofState]?, spendingConditions: [CashuDevKit.SpendingConditions]?) async throws -> [CashuDevKit.ProofInfo] {
        logger.debug("Getting proofs with filters (not implemented - ProofInfo not Codable)")

        // NOTE: ProofInfo is not Codable in cdk-swift 0.13.1, so we cannot retrieve proofs from Amplify
        // Returning empty array for now
        return []

        // TODO: Re-enable when ProofInfo becomes Codable
        // do {
        //     let userId = await getCurrentUserId()
        //     var predicate = Proof.keys.owner.eq(userId)
        //
        //     let amplifyProofs = try await Amplify.DataStore.query(Proof.self, where: predicate)
        //     var proofs: [CashuDevKit.ProofInfo] = []
        //     let decoder = JSONDecoder()
        //
        //     for amplifyProof in amplifyProofs {
        //         do {
        //             let decryptedData = try await decryptData(amplifyProof.encryptedProof)
        //             let proofInfo = try decoder.decode(CashuDevKit.ProofInfo.self, from: decryptedData)
        //
        //             // Apply filters...
        //             proofs.append(proofInfo)
        //         } catch {
        //             logger.error("Failed to decrypt/decode proof \(amplifyProof.id): \(error.localizedDescription)")
        //         }
        //     }
        //
        //     return proofs
        // } catch {
        //     logger.error("Failed to get proofs: \(error.localizedDescription)")
        //     throw error
        // }
    }

    func updateProofsState(ys: [CashuDevKit.PublicKey], state: CashuDevKit.ProofState) async throws {
        let stateString = String(describing: state)
        logger.debug("Updating proof states for \(ys.count) proofs to \(stateString)")

        let amplifyState = mapProofState(state)

        for publicKey in ys {
            let publicKeyString = publicKey.hex
            let predicate = Proof.keys.proofId.eq(publicKeyString)
            let proofsToUpdate = try await Amplify.DataStore.query(Proof.self, where: predicate)

            for var proofToUpdate in proofsToUpdate {
                proofToUpdate.state = amplifyState
                try await Amplify.DataStore.save(proofToUpdate)
            }
        }

        logger.debug("Proof states updated successfully")
    }

    // MARK: - Transaction Management
    // Note: CDK Transaction types don't conform to Codable, so using in-memory storage for now
    func addTransaction(transaction: CashuDevKit.Transaction) async throws {
        logger.debug("Adding transaction - in-memory storage (CDK Transaction not Codable)")
        // For now, we'll rely on the CDK's internal storage
        // When CDK types become Codable, we can implement proper Amplify storage
    }

    func getTransaction(transactionId: CashuDevKit.TransactionId) async throws -> CashuDevKit.Transaction? {
        logger.debug("Getting transaction - not implemented (CDK Transaction not Codable)")
        return nil
    }

    func listTransactions(mintUrl: CashuDevKit.MintUrl?, direction: CashuDevKit.TransactionDirection?, unit: CashuDevKit.CurrencyUnit?) async throws -> [CashuDevKit.Transaction] {
        logger.debug("Listing transactions - returning empty array (CDK Transaction not Codable)")
        return []
    }

    func removeTransaction(transactionId: CashuDevKit.TransactionId) async throws {
        logger.debug("Removing transaction - not implemented (CDK Transaction not Codable)")
    }
}

// MARK: - Helper Methods
private extension AmplifyWalletDatabase {

    func getCurrentUserId() async -> String {
        // Get the authenticated user ID from AWS Cognito
        do {
            // Get current authenticated user
            let user = try await Amplify.Auth.getCurrentUser()
            return user.userId
        } catch {
            logger.warning("No authenticated user, using fallback ID")
            return "anonymous_user"
        }
    }

    func encryptData(_ data: Data) async throws -> String {
        return try await walletEncryption.encrypt(data)
    }

    func decryptData(_ encryptedString: String) async throws -> Data {
        return try await walletEncryption.decrypt(encryptedString)
    }

    func mapProofState(_ cdkState: CashuDevKit.ProofState) -> ProofState {
        switch cdkState {
        case .unspent: return .unspent
        case .spent: return .spent
        case .pending: return .pending
        case .reserved: return .reserved
        @unknown default:
            logger.warning("Unknown proof state, defaulting to unspent")
            return .unspent
        }
    }

    func mapMintQuoteState(_ cdkState: CashuDevKit.QuoteState) -> MintQuoteState {
        switch cdkState {
        case .unpaid: return .unpaid
        case .paid: return .paid
        case .issued: return .issued
        @unknown default:
            logger.warning("Unknown quote state, defaulting to unpaid")
            return .unpaid
        }
    }

    func mapMeltQuoteState(_ cdkState: CashuDevKit.QuoteState) -> MeltQuoteState {
        switch cdkState {
        case .unpaid: return .unpaid
        case .paid: return .paid
        case .issued: return .unpaid  // Map issued to unpaid since MeltQuoteState doesn't have issued
        @unknown default:
            logger.warning("Unknown quote state, defaulting to unpaid")
            return .unpaid
        }
    }
}

// MARK: - Error Types
enum DatabaseError: LocalizedError {
    case decryptionFailed
    case userNotAuthenticated
    case dataCorrupted

    var errorDescription: String? {
        switch self {
        case .decryptionFailed:
            return "Failed to decrypt data"
        case .userNotAuthenticated:
            return "User is not authenticated"
        case .dataCorrupted:
            return "Data is corrupted or invalid"
        }
    }
}