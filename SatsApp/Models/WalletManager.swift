import Foundation
import Security
import CashuDevKit
import Amplify
import CryptoKit
import CommonCrypto

class WalletManager: ObservableObject {
    private let keychainService = "app.paywithsats.keychain"
    private let mnemonicKey = "wallet_mnemonic"
    let defaultMintURL = "https://fake.thesimplekid.dev"
    
    @Published var wallet: MultiMintWallet?
    @Published var isInitialized = false
    @Published var initializationError: String?
    @Published var isLoading = true
    @Published var balance: UInt64 = 0
    
    var formattedBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return (formatter.string(from: NSNumber(value: balance)) ?? "0") + " sat"
    }
    
    private var documentsURL: URL {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return urls[0]
    }

    private var walletDataURL: URL {
        return documentsURL.appendingPathComponent("wallet_data", isDirectory: true)
    }

    private var database: AmplifyWalletDatabase?
    private var walletEncryption: WalletEncryption?

    // Dependency injection
    private weak var authManager: AuthManager?
    
    init() {
        AppLogger.wallet.info("WalletManager: Initializing...")
        setupWalletDirectory()
        AppLogger.wallet.info("WalletManager: Starting wallet initialization task...")
        Task { @MainActor in
            await initializeWallet()
        }
        AppLogger.wallet.info("WalletManager: Init complete, task started")
    }
    
    private func setupWalletDirectory() {
        do {
            try FileManager.default.createDirectory(at: walletDataURL, withIntermediateDirectories: true, attributes: nil)
            
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = false
            var url = walletDataURL
            try url.setResourceValues(resourceValues)
            
            AppLogger.wallet.info("Wallet data directory configured at: \(self.walletDataURL.path)")
            AppLogger.wallet.info("iCloud backup enabled for wallet data")
        } catch {
            AppLogger.wallet.error("Failed to setup wallet directory: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    private func initializeWallet() async {
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
        AppLogger.wallet.info("Retrieving mnemonic...")
        let mnemonic = getMnemonicFromKeychain() ?? generateAndStoreMnemonic()
        AppLogger.wallet.info("Mnemonic retrieved/generated: \(!mnemonic.isEmpty)")

        // Check if mnemonic is valid
        guard !mnemonic.isEmpty else {
            AppLogger.wallet.error("Mnemonic is empty")
            throw WalletError.failedToGenerateMnemonic
        }

        AppLogger.wallet.info("Creating wallet config")
        let walletConfig = WalletConfig(targetProofCount: nil)

        AppLogger.wallet.info("Initializing wallet encryption with mnemonic")
        let encryption = WalletEncryption()
        try await encryption.initializeEncryption(with: mnemonic)
        self.walletEncryption = encryption

        AppLogger.wallet.info("Creating Amplify wallet database")
        let amplifyDatabase = AmplifyWalletDatabase(
            walletEncryption: encryption,
            authManager: self.authManager
        )
        self.database = amplifyDatabase

        AppLogger.wallet.info("Initializing MultiMintWallet")
        let newWallet = try await MultiMintWallet(
            unit: CurrencyUnit.sat,
            mnemonic: mnemonic,
            db: amplifyDatabase
        )

        // Add the default mint
        AppLogger.wallet.info("Adding default mint: \(self.defaultMintURL)")
        let mintUrl = MintUrl(url: defaultMintURL)
        try await newWallet.addMint(mintUrl: mintUrl, targetProofCount: nil)

        AppLogger.wallet.info("Wallet created successfully, updating UI...")
        await MainActor.run {
            self.wallet = newWallet
            self.isInitialized = true
            self.isLoading = false
            AppLogger.wallet.info("✅ MultiMintWallet initialized successfully with default mint: \(self.defaultMintURL)")

            // Load initial balance
            self.refreshBalance()
        }
    }
    
    // Public method to retry initialization if it fails
    func retryInitialization() {
        Task { @MainActor in
            await initializeWallet()
        }
    }

    // Set the auth manager for dependency injection
    func setAuthManager(_ authManager: AuthManager) {
        self.authManager = authManager
    }
    
    private func getMnemonicFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: mnemonicKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess else {
            return nil
        }
        
        guard let data = item as? Data,
              let mnemonic = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return mnemonic
    }
    
    private func generateAndStoreMnemonic() -> String {
        let mnemonic = generateMnemonic()
        storeMnemonicInKeychain(mnemonic)
        return mnemonic
    }
    
    private func generateMnemonic() -> String {
        AppLogger.wallet.debug("Generating new mnemonic...")
        do {
            let mnemonic = try CashuDevKit.generateMnemonic()
            AppLogger.wallet.debug("Mnemonic generated successfully, length: \(mnemonic.count)")
            return mnemonic
        } catch {
            AppLogger.wallet.error("Failed to generate mnemonic: \(error.localizedDescription)")
            // Return a fallback empty mnemonic - this should trigger wallet initialization error
            return ""
        }
    }
    
    private func storeMnemonicInKeychain(_ mnemonic: String) {
        guard let data = mnemonic.data(using: .utf8) else {
            AppLogger.wallet.error("Failed to convert mnemonic to data")
            return
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: mnemonicKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            AppLogger.wallet.error("Failed to store mnemonic in keychain: \(status)")
        } else {
            AppLogger.wallet.debug("Mnemonic stored successfully in keychain")
        }
    }
    
    // MARK: - Transaction History

    func listTransactions(direction: TransactionDirection? = nil) async -> [UITransaction] {
        guard let wallet = self.wallet else {
            AppLogger.wallet.debug("Wallet not available, returning empty transactions")
            return []
        }

        do {
            // Get transactions from the wallet, optionally filtered by direction
            let cdkTransactions = try await wallet.listTransactions(direction: direction)

            // Convert CDK transactions to UI transactions
            var transactions: [UITransaction] = []

            for cdkTransaction in cdkTransactions {
                // Get the actual timestamp from the CDK transaction
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
        AppLogger.wallet.info("✅ Mint added successfully: \(mintUrl)")
    }

    func removeMint(mintUrl: String) async throws {
        guard let wallet = self.wallet else {
            AppLogger.wallet.error("Wallet not available")
            throw WalletError.walletNotInitialized
        }

        AppLogger.wallet.info("Removing mint: \(mintUrl)")
        let mint = MintUrl(url: mintUrl)
        try await wallet.removeMint(mintUrl: mint)
        AppLogger.wallet.info("✅ Mint removed successfully: \(mintUrl)")
    }

    func getMints() async throws -> [String] {
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

    func generateMintQuote(mintUrl: String, amount: UInt64) async throws -> (String, String, String) {
        guard let wallet = self.wallet else {
            AppLogger.network.error("Wallet not available")
            throw WalletError.walletNotInitialized
        }

        do {
            let mint = MintUrl(url: mintUrl)
            let amountObj = Amount(value: amount)
            let mintQuote = try await wallet.mintQuote(mintUrl: mint, amount: amountObj, description: nil)
            let state = mintQuote.state
            let statusString = switch state {
            case .unpaid: "Unpaid"
            case .paid: "Paid"
            case .pending: "Pending"
            case .issued: "Issued"
            }
            return (mintQuote.request, statusString, mintQuote.id)
        } catch {
            AppLogger.network.error("Failed to generate mint quote: \(error.localizedDescription)")
            throw error
        }
    }

    func checkMintQuoteStatus(mintUrl: String, quoteId: String) async throws -> String {
        guard let database = self.database else {
            AppLogger.network.error("Database not available")
            throw WalletError.walletNotInitialized
        }

        do {
            // Check the quote status from the database
            guard let mintQuote = try await database.getMintQuote(quoteId: quoteId) else {
                AppLogger.network.warning("Mint quote \(quoteId) not found in database")
                return "Unpaid"
            }

            let state = mintQuote.state
            let statusString = switch state {
            case .unpaid: "Unpaid"
            case .paid: "Paid"
            case .pending: "Pending"
            case .issued: "Issued"
            }
            return statusString
        } catch {
            AppLogger.network.error("Failed to check mint quote status: \(error.localizedDescription)")
            throw error
        }
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
                total + proof.amount().value
            }
            AppLogger.network.info("✅ Successfully minted \(totalMinted) sats from quote \(quoteId)")
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
            AppLogger.network.info("✅ Successfully melted tokens for invoice")
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
            AppLogger.network.info("✅ Created send token for \(amount) sats")
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
            // Decode the token string to Token
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
            AppLogger.network.info("✅ Received \(receivedAmount.value) sats")
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
            AppLogger.network.info("✅ Swapped \(amount) sats between mints")
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
