import Foundation
import CashuDevKit

class WalletManager: ObservableObject {
    @Published var wallet: MultiMintWallet?
    @Published var isInitialized = false
    @Published var needsMintSelection = false
    @Published var initializationError: String?
    @Published var isLoading = true
    @Published var balance: UInt64 = 0
    @Published var isUsingICloud: Bool = false

    var formattedBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return (formatter.string(from: NSNumber(value: balance)) ?? "0") + " sat"
    }

    private var database: WalletSqliteDatabase?

    init() {
        AppLogger.wallet.info("WalletManager: Initializing...")
        AppLogger.wallet.info("WalletManager: Init complete, ready for wallet initialization")
    }

    @MainActor
    func initializeWallet() async {
        AppLogger.wallet.info("Starting wallet initialization...")

        self.isLoading = true
        self.initializationError = nil

        do {
            try await performWalletInitialization()
        } catch {
            AppLogger.wallet.error("Wallet initialization failed: \(error.localizedDescription)")
            self.initializationError = "Failed to initialize wallet: \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    private func performWalletInitialization() async throws {
        // Initialize storage manager
        let storageManager = StorageManager.shared
        storageManager.initialize()

        await MainActor.run {
            self.isUsingICloud = storageManager.isUsingICloud
        }

        // Ensure wallet directory exists
        try storageManager.ensureDirectoryExists()

        // Get or generate mnemonic
        AppLogger.wallet.info("Retrieving mnemonic...")
        let mnemonic: String
        if storageManager.seedExists() {
            mnemonic = try storageManager.loadMnemonic()
            AppLogger.wallet.info("Loaded existing mnemonic from storage")
        } else {
            mnemonic = try generateAndStoreMnemonic(storageManager: storageManager)
            AppLogger.wallet.info("Generated new mnemonic")
        }

        guard !mnemonic.isEmpty else {
            AppLogger.wallet.error("Mnemonic is empty")
            throw WalletError.failedToGenerateMnemonic
        }

        // Initialize WalletSqliteDatabase
        let dbPath = storageManager.walletDirectory.appendingPathComponent("wallet.db").path
        AppLogger.wallet.info("Initializing SQLite database at: \(dbPath)")
        let sqliteDatabase = try WalletSqliteDatabase(filePath: dbPath)
        self.database = sqliteDatabase

        // Create MultiMintWallet
        AppLogger.wallet.info("Initializing MultiMintWallet")
        let newWallet = try MultiMintWallet(
            unit: CurrencyUnit.sat,
            mnemonic: mnemonic,
            db: sqliteDatabase
        )

        // Check if any mints are configured
        let existingMints = await newWallet.getMintUrls()
        let hasMints = !existingMints.isEmpty

        AppLogger.wallet.info("Wallet created successfully, found \(existingMints.count) existing mints")

        await MainActor.run {
            self.wallet = newWallet
            self.isInitialized = true
            self.needsMintSelection = !hasMints
            self.isLoading = false
            AppLogger.wallet.info("MultiMintWallet initialized successfully")

            if hasMints {
                // Load initial balance
                self.refreshBalance()
            }
        }
    }

    // Public method to retry initialization if it fails
    func retryInitialization() {
        Task { @MainActor in
            await initializeWallet()
        }
    }

    private func generateAndStoreMnemonic(storageManager: StorageManager) throws -> String {
        AppLogger.wallet.debug("Generating new mnemonic...")
        do {
            let mnemonic = try CashuDevKit.generateMnemonic()
            try storageManager.saveMnemonic(mnemonic)
            AppLogger.wallet.debug("Mnemonic generated and stored successfully")
            return mnemonic
        } catch {
            AppLogger.wallet.error("Failed to generate mnemonic: \(error.localizedDescription)")
            throw WalletError.failedToGenerateMnemonic
        }
    }

    // MARK: - Mint Selection Complete

    /// Called when user completes mint selection during first launch
    @MainActor
    func completeMintSelection() {
        needsMintSelection = false
        refreshBalance()
    }

    // MARK: - Transaction History

    func listTransactions(direction: TransactionDirection? = nil) async -> [UITransaction] {
        guard let wallet = self.wallet else {
            AppLogger.wallet.debug("Wallet not available, returning empty transactions")
            return []
        }

        do {
            let cdkTransactions = try await wallet.listTransactions(direction: direction)

            var transactions: [UITransaction] = []

            for cdkTransaction in cdkTransactions {
                let timestamp = cdkTransaction.timestamp
                let transactionDate = Date(timeIntervalSince1970: TimeInterval(timestamp))

                let transaction = UITransaction(
                    type: cdkTransaction.direction == .incoming ? .received : .sent,
                    amount: Int(cdkTransaction.amount.value),
                    description: cdkTransaction.direction == .incoming ? "Received" : "Sent",
                    memo: cdkTransaction.memo,
                    date: transactionDate,
                    status: .completed
                )
                transactions.append(transaction)
            }

            return transactions.sorted { $0.date > $1.date }

        } catch {
            AppLogger.wallet.error("Failed to get transactions: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Mint Management

    func addMint(mintUrl: String) async throws {
        guard let wallet = self.wallet else {
            AppLogger.wallet.error("Wallet not available")
            throw WalletError.walletNotInitialized
        }

        AppLogger.wallet.info("Adding mint: \(mintUrl)")
        let mint = MintUrl(url: mintUrl)
        try await wallet.addMint(mintUrl: mint, targetProofCount: nil)
        AppLogger.wallet.info("Mint added successfully: \(mintUrl)")
    }

    func removeMint(mintUrl: String) async throws {
        guard let wallet = self.wallet else {
            AppLogger.wallet.error("Wallet not available")
            throw WalletError.walletNotInitialized
        }

        AppLogger.wallet.info("Removing mint: \(mintUrl)")
        let mint = MintUrl(url: mintUrl)
        await wallet.removeMint(mintUrl: mint)
        AppLogger.wallet.info("Mint removed successfully: \(mintUrl)")
    }

    func getMints() async -> [String] {
        guard let wallet = self.wallet else {
            AppLogger.wallet.debug("Wallet not available")
            return []
        }

        let mints = await wallet.getMintUrls()
        AppLogger.wallet.debug("Retrieved \(mints.count) mints")
        return mints
    }

    func getMintBalances() async throws -> [String: UInt64] {
        guard let wallet = self.wallet else {
            AppLogger.wallet.debug("Wallet not available")
            return [:]
        }

        do {
            let balances = try await wallet.getBalances()
            var result: [String: UInt64] = [:]
            for (mintUrlString, amount) in balances {
                result[mintUrlString] = amount.value
            }
            return result
        } catch {
            AppLogger.wallet.error("Failed to get mint balances: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Balance

    func getBalance() async -> UInt64 {
        guard let wallet = self.wallet else {
            AppLogger.wallet.debug("Wallet not available")
            return 0
        }

        do {
            let balance = try await wallet.totalBalance()
            return balance.value
        } catch {
            AppLogger.wallet.error("Failed to get balance: \(error.localizedDescription)")
            return 0
        }
    }

    func refreshBalance() {
        Task {
            let newBalance = await getBalance()
            await MainActor.run {
                self.balance = newBalance
                AppLogger.wallet.debug("Balance updated to: \(newBalance) sats")
            }
        }
    }

    // MARK: - Mint Quote

    func generateMintQuote(mintUrl: String, amount: UInt64) async throws -> (request: String, state: QuoteState, id: String) {
        guard let wallet = self.wallet else {
            AppLogger.network.error("Wallet not available")
            throw WalletError.walletNotInitialized
        }

        do {
            let mint = MintUrl(url: mintUrl)
            let amountObj = Amount(value: amount)
            let mintQuote = try await wallet.mintQuote(mintUrl: mint, amount: amountObj, description: nil)
            AppLogger.network.info("Generated mint quote \(mintQuote.id) with state: \(String(describing: mintQuote.state))")
            return (mintQuote.request, mintQuote.state, mintQuote.id)
        } catch {
            AppLogger.network.error("Failed to generate mint quote: \(error.localizedDescription)")
            throw error
        }
    }

    func checkMintQuoteStatus(mintUrl: String, quoteId: String) async throws -> QuoteState {
        guard let wallet = self.wallet else {
            AppLogger.network.error("Wallet not available")
            throw WalletError.walletNotInitialized
        }

        let mint = MintUrl(url: mintUrl)
        let quote = try await wallet.checkMintQuote(mintUrl: mint, quoteId: quoteId)
        AppLogger.network.debug("Mint quote \(quoteId) status: \(String(describing: quote.state))")
        return quote.state
    }

    func mintTokens(mintUrl: String, quoteId: String) async throws -> UInt64 {
        guard let wallet = self.wallet else {
            AppLogger.network.error("Wallet not available")
            throw WalletError.walletNotInitialized
        }

        do {
            let mint = MintUrl(url: mintUrl)
            let proofs = try await wallet.mint(mintUrl: mint, quoteId: quoteId, spendingConditions: nil)
            let totalMinted = proofs.reduce(0) { total, proof in
                total + proof.amount.value
            }
            AppLogger.network.info("Successfully minted \(totalMinted) sats from quote \(quoteId)")
            return totalMinted
        } catch {
            AppLogger.network.error("Failed to mint tokens: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Melt Quote (Pay Lightning Invoice)

    func generateMeltQuote(mintUrl: String, invoice: String) async throws -> (String, UInt64, UInt64) {
        guard let wallet = self.wallet else {
            AppLogger.network.error("Wallet not available")
            throw WalletError.walletNotInitialized
        }

        do {
            let mint = MintUrl(url: mintUrl)
            let meltQuote = try await wallet.meltQuote(mintUrl: mint, request: invoice, options: nil)
            AppLogger.network.info("Generated melt quote: \(meltQuote.id)")
            return (meltQuote.id, meltQuote.amount.value, meltQuote.feeReserve.value)
        } catch {
            AppLogger.network.error("Failed to generate melt quote: \(error.localizedDescription)")
            throw error
        }
    }

    func meltTokens(mintUrl: String, invoice: String) async throws -> (UInt64, String?) {
        guard let wallet = self.wallet else {
            AppLogger.network.error("Wallet not available")
            throw WalletError.walletNotInitialized
        }

        do {
            let meltResponse = try await wallet.melt(bolt11: invoice, options: nil, maxFee: nil)
            AppLogger.network.info("Successfully melted tokens for invoice")
            return (meltResponse.amount.value, meltResponse.preimage)
        } catch {
            AppLogger.network.error("Failed to melt tokens: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Token Operations (Send/Receive)

    func send(mintUrl: String, amount: UInt64, memo: String?) async throws -> String {
        guard let wallet = self.wallet else {
            AppLogger.network.error("Wallet not available")
            throw WalletError.walletNotInitialized
        }

        do {
            let mint = MintUrl(url: mintUrl)
            let amountObj = Amount(value: amount)
            let sendOptions = SendOptions(
                memo: nil,
                conditions: nil,
                amountSplitTarget: SplitTarget.none,
                sendKind: SendKind.onlineExact,
                includeFee: false,
                maxProofs: nil,
                metadata: [:]
            )
            let options = MultiMintSendOptions(
                allowTransfer: false,
                maxTransferAmount: nil,
                allowedMints: [],
                excludedMints: [],
                sendOptions: sendOptions
            )
            let preparedSend = try await wallet.prepareSend(mintUrl: mint, amount: amountObj, options: options)
            let token = try await preparedSend.confirm(memo: memo)
            let tokenString = token.encode()
            AppLogger.network.info("Created send token for \(amount) sats")
            return tokenString
        } catch {
            AppLogger.network.error("Failed to create send token: \(error.localizedDescription)")
            throw error
        }
    }

    func receive(tokenString: String) async throws -> UInt64 {
        guard let wallet = self.wallet else {
            AppLogger.network.error("Wallet not available")
            throw WalletError.walletNotInitialized
        }

        do {
            let token = try Token.decode(encodedToken: tokenString)
            let receiveOptions = ReceiveOptions(
                amountSplitTarget: SplitTarget.none,
                p2pkSigningKeys: [],
                preimages: [],
                metadata: [:]
            )
            let options = MultiMintReceiveOptions(
                allowUntrusted: false,
                transferToMint: nil,
                receiveOptions: receiveOptions
            )
            let receivedAmount = try await wallet.receive(token: token, options: options)
            AppLogger.network.info("Received \(receivedAmount.value) sats")
            return receivedAmount.value
        } catch {
            AppLogger.network.error("Failed to receive token: \(error.localizedDescription)")
            throw error
        }
    }

    func swap(amount: UInt64) async throws {
        guard let wallet = self.wallet else {
            AppLogger.network.error("Wallet not available")
            throw WalletError.walletNotInitialized
        }

        do {
            let amountObj = Amount(value: amount)
            _ = try await wallet.swap(amount: amountObj, spendingConditions: nil)
            AppLogger.network.info("Swapped \(amount) sats between mints")
        } catch {
            AppLogger.network.error("Failed to swap tokens: \(error.localizedDescription)")
            throw error
        }
    }
}

enum WalletError: LocalizedError {
    case walletNotInitialized
    case failedToGenerateMnemonic

    var errorDescription: String? {
        switch self {
        case .walletNotInitialized:
            return "Wallet is not initialized"
        case .failedToGenerateMnemonic:
            return "Failed to generate or retrieve wallet mnemonic"
        }
    }
}
