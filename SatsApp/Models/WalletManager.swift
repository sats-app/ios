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
    @Published var mintNames: [String: String] = [:]

    var formattedBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return "₿" + (formatter.string(from: NSNumber(value: balance)) ?? "0")
    }

    /// Format a sats amount with Bitcoin symbol and grouping
    static func formatAmount(_ sats: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return "\u{20BF}" + (formatter.string(from: NSNumber(value: sats)) ?? "0")
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
                let transactionDate = Date(timeIntervalSince1970: TimeInterval(cdkTransaction.timestamp))

                // Check pending status for outgoing transactions
                let isPending = cdkTransaction.direction == .outgoing
                    ? await checkTransactionPending(cdkTransaction)
                    : false

                let transaction = UITransaction(
                    id: cdkTransaction.id.hex,
                    type: cdkTransaction.direction == .incoming ? .received : .sent,
                    amount: Int(cdkTransaction.amount.value),
                    fee: Int(cdkTransaction.fee.value),
                    description: cdkTransaction.direction == .incoming ? "Received" : "Sent",
                    memo: cdkTransaction.memo,
                    date: transactionDate,
                    status: isPending ? .pending : .completed,
                    mintUrl: cdkTransaction.mintUrl.url
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

        // Check if mint has balance before removing
        let balances = try await getMintBalances()
        if let balance = balances[mintUrl], balance > 0 {
            AppLogger.wallet.warning("Cannot remove mint with balance: \(mintUrl) has \(balance) sats")
            throw WalletError.mintHasBalance
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

    /// Returns the display name for a mint URL, with fallback to URL host
    func getMintDisplayName(for url: String) -> String {
        if let name = mintNames[url], !name.isEmpty {
            return name
        }
        return URL(string: url)?.host ?? url
    }

    /// Returns the preferred mint from available mints
    /// Uses default mint if set and still configured, otherwise returns first available
    func getPreferredMint(from mints: [String]) -> String? {
        if let defaultMint = SettingsManager.shared.defaultMintUrl,
           mints.contains(defaultMint) {
            return defaultMint
        }
        return mints.first
    }

    /// Returns the current default mint, validated against configured mints
    /// Falls back to first available mint if default is not valid
    func getDefaultMint() async -> String? {
        let mints = await getMints()
        if let defaultMint = SettingsManager.shared.defaultMintUrl,
           mints.contains(defaultMint) {
            return defaultMint
        }
        return mints.first
    }

    /// Check if a mint URL is already trusted (configured in wallet)
    func isMintTrusted(mintUrl: String) async -> Bool {
        AppLogger.wallet.debug("Checking if mint is trusted: \(mintUrl)")
        let configuredMints = await getMints()
        let isTrusted = configuredMints.contains(mintUrl)
        AppLogger.wallet.debug("Mint trusted: \(isTrusted) (configured mints: \(configuredMints.count))")
        return isTrusted
    }

    /// Parse a Cashu token to extract mint URL and amount
    /// Uses direct Token methods to avoid requiring the mint to be pre-configured
    func parseToken(tokenString: String) async throws -> (mintUrl: String, amount: UInt64) {
        let tokenPrefix = String(tokenString.prefix(20))
        AppLogger.wallet.debug("parseToken called with token: \(tokenPrefix)...")

        // Step 1: Decode the token
        AppLogger.wallet.debug("Decoding token with Token.decode()...")
        let token: Token
        do {
            token = try Token.decode(encodedToken: tokenString)
            AppLogger.wallet.debug("Token decoded successfully")
        } catch {
            AppLogger.wallet.error("Token.decode() failed - Type: \(String(describing: type(of: error))), Description: \(error.localizedDescription), Details: \(String(describing: error))")
            throw error
        }

        // Step 2: Extract mint URL directly from token (no wallet/mint contact required)
        AppLogger.wallet.debug("Extracting mint URL from token...")
        let mintUrl: MintUrl
        do {
            mintUrl = try token.mintUrl()
            AppLogger.wallet.debug("Mint URL extracted: \(mintUrl.url)")
        } catch {
            AppLogger.wallet.error("token.mintUrl() failed - Type: \(String(describing: type(of: error))), Description: \(error.localizedDescription), Details: \(String(describing: error))")
            throw error
        }

        // Step 3: Get amount directly from token
        AppLogger.wallet.debug("Extracting amount from token...")
        let amount: UInt64
        do {
            let tokenAmount = try token.value()
            amount = tokenAmount.value
            AppLogger.wallet.debug("Amount extracted: \(amount)")
        } catch {
            AppLogger.wallet.error("token.value() failed - Type: \(String(describing: type(of: error))), Description: \(error.localizedDescription), Details: \(String(describing: error))")
            throw error
        }

        AppLogger.wallet.info("Parsed token successfully: mint=\(mintUrl.url), amount=\(amount)")
        return (mintUrl.url, amount)
    }

    /// Fetches and caches mint names for all configured mints
    func refreshMintNames() {
        Task {
            let mints = await getMints()
            for mintUrl in mints {
                // Skip if already cached
                if mintNames[mintUrl] != nil {
                    continue
                }

                do {
                    let info = try await MintInfoService.shared.fetchMintInfo(mintUrl: mintUrl)
                    if let name = info.name, !name.isEmpty {
                        await MainActor.run {
                            self.mintNames[mintUrl] = name
                        }
                    }
                } catch {
                    AppLogger.network.debug("Failed to fetch mint info for \(mintUrl): \(error.localizedDescription)")
                }
            }
        }
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
        refreshMintNames()
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

    // MARK: - Prepared Send (Two-Phase)

    /// Prepares a send operation and returns the fee without executing
    func prepareSendWithFee(mintUrl: String, amount: UInt64) async throws -> (PreparedSend, UInt64) {
        guard let wallet = self.wallet else {
            AppLogger.network.error("Wallet not available")
            throw WalletError.walletNotInitialized
        }

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
        let fee = preparedSend.fee().value
        AppLogger.network.info("Prepared send for \(amount) sats with fee \(fee) sats")
        return (preparedSend, fee)
    }

    /// Confirms a previously prepared send operation
    func confirmPreparedSend(_ preparedSend: PreparedSend, memo: String?) async throws -> String {
        let token = try await preparedSend.confirm(memo: memo)
        let tokenString = token.encode()
        AppLogger.network.info("Confirmed prepared send")
        return tokenString
    }

    /// Cancels a prepared send (cleanup if user dismisses)
    func cancelPreparedSend(_ preparedSend: PreparedSend) async {
        do {
            try await preparedSend.cancel()
            AppLogger.network.info("Cancelled prepared send")
        } catch {
            AppLogger.network.debug("Failed to cancel prepared send: \(error.localizedDescription)")
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

    /// Receive a token with options for handling untrusted mints
    /// - Parameters:
    ///   - tokenString: The encoded Cashu token
    ///   - trustMint: If true, allows receiving from untrusted mint. If false, transfers to default mint.
    /// - Returns: The received amount in sats
    func receiveToken(tokenString: String, trustMint: Bool) async throws -> UInt64 {
        let tokenPrefix = String(tokenString.prefix(20))
        AppLogger.wallet.info("receiveToken called: trustMint=\(trustMint), token=\(tokenPrefix)...")

        guard let wallet = self.wallet else {
            AppLogger.wallet.error("receiveToken failed: wallet not initialized")
            throw WalletError.walletNotInitialized
        }

        // Step 1: Decode the token
        AppLogger.wallet.debug("Decoding token for receive...")
        let token: Token
        do {
            token = try Token.decode(encodedToken: tokenString)
            AppLogger.wallet.debug("Token decoded for receive")
        } catch {
            AppLogger.wallet.error("receiveToken: Token.decode() failed - Type: \(String(describing: type(of: error))), Description: \(error.localizedDescription), Details: \(String(describing: error))")
            throw error
        }

        let receiveOptions = ReceiveOptions(
            amountSplitTarget: SplitTarget.none,
            p2pkSigningKeys: [],
            preimages: [],
            metadata: [:]
        )

        // Step 2: Configure options based on trust decision
        let transferMint: MintUrl?
        if trustMint {
            AppLogger.wallet.debug("Trust path: allowUntrusted=true, transferToMint=nil")
            transferMint = nil
        } else {
            // Transfer to default mint when not trusting the source mint
            if let defaultMintUrl = await getDefaultMint() {
                AppLogger.wallet.debug("Transfer path: allowUntrusted=false, transferToMint=\(defaultMintUrl)")
                transferMint = MintUrl(url: defaultMintUrl)
            } else {
                AppLogger.wallet.error("receiveToken failed: no default mint available for transfer")
                throw WalletError.walletNotInitialized
            }
        }

        let options = MultiMintReceiveOptions(
            allowUntrusted: trustMint,
            transferToMint: transferMint,
            receiveOptions: receiveOptions
        )

        // Step 3: Call CDK receive
        AppLogger.wallet.debug("Calling wallet.receive() with options: allowUntrusted=\(trustMint), transferToMint=\(transferMint?.url ?? "nil")")
        do {
            let receivedAmount = try await wallet.receive(token: token, options: options)
            AppLogger.wallet.info("Received \(receivedAmount.value) sats successfully (trustMint: \(trustMint), transfer: \(transferMint?.url ?? "none"))")
            return receivedAmount.value
        } catch {
            AppLogger.wallet.error("wallet.receive() failed - Type: \(String(describing: type(of: error))), Description: \(error.localizedDescription), Details: \(String(describing: error))")
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

    // MARK: - Payment Requests (NUT-18)

    func createPaymentRequest(amount: UInt64?, unit: String = "sat", description: String?) async throws -> String {
        guard let wallet = self.wallet else {
            AppLogger.network.error("Wallet not available")
            throw WalletError.walletNotInitialized
        }

        do {
            let params = CreateRequestParams(
                amount: amount,
                unit: unit,
                description: description,
                pubkeys: nil,
                numSigs: 1,
                hash: nil,
                preimage: nil,
                transport: "none",
                httpUrl: nil,
                nostrRelays: nil
            )

            let result = try await wallet.createRequest(params: params)
            let encoded = result.paymentRequest.toStringEncoded()
            AppLogger.network.info("Created payment request for \(amount ?? 0) sats")
            return encoded
        } catch {
            AppLogger.network.error("Failed to create payment request: \(error.localizedDescription)")
            throw error
        }
    }

    func payPaymentRequest(paymentRequest: PaymentRequest, mintUrl: String, amount: UInt64?) async throws {
        guard let multiMintWallet = self.wallet else {
            AppLogger.network.error("Wallet not available")
            throw WalletError.walletNotInitialized
        }

        do {
            // Get the single-mint wallet for the specified mint
            let mint = MintUrl(url: mintUrl)
            guard let singleWallet = await multiMintWallet.getWallet(mintUrl: mint) else {
                AppLogger.network.error("Wallet not found for mint: \(mintUrl)")
                throw WalletError.walletNotInitialized
            }

            let customAmount = amount.map { Amount(value: $0) }
            try await singleWallet.payRequest(paymentRequest: paymentRequest, customAmount: customAmount)
            AppLogger.network.info("Successfully paid payment request")
        } catch {
            AppLogger.network.error("Failed to pay request: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Proof State Checking (NUT-07)

    /// Response from mint's /v1/checkstate endpoint
    private struct CheckStateResponse: Codable {
        let states: [ProofStateInfo]
    }

    /// Individual proof state from mint response
    private struct ProofStateInfo: Codable {
        let Y: String
        let state: String  // "UNSPENT", "PENDING", "SPENT"
    }

    /// Check if a token's proofs have been spent (claimed by recipient)
    /// Returns true if all proofs are spent, false otherwise
    func checkTokenSpent(tokenString: String) async throws -> Bool {
        guard let multiMintWallet = self.wallet else {
            return false
        }

        // Decode the token
        let token = try Token.decode(encodedToken: tokenString)

        // Get token data (mint URL and proofs) using wallet method
        let tokenData = try await multiMintWallet.getTokenData(token: token)
        let proofs = tokenData.proofs

        // Check proof states at the mint
        let states = try await multiMintWallet.checkProofsState(
            mintUrl: tokenData.mintUrl,
            proofs: proofs
        )

        // Token is spent if all proofs are spent
        let allSpent = states.allSatisfy { $0 == ProofState.spent }
        AppLogger.network.debug("Token spent check: \(allSpent) for \(proofs.count) proofs")
        return allSpent
    }

    /// Check if a sent transaction's proofs are still unspent at the mint
    /// Returns true if transaction is pending (all proofs unspent), false if completed
    func checkTransactionPending(_ cdkTransaction: Transaction) async -> Bool {
        guard cdkTransaction.direction == .outgoing else { return false }
        guard !cdkTransaction.ys.isEmpty else { return false }

        do {
            // Build the Y values array for the request
            let ys = cdkTransaction.ys.map { $0.hex }
            let payload: [String: Any] = ["Ys": ys]

            // Construct the checkstate URL
            guard var urlComponents = URLComponents(string: cdkTransaction.mintUrl.url) else {
                AppLogger.network.debug("Invalid mint URL for state check")
                return false
            }
            urlComponents.path = "/v1/checkstate"

            guard let url = urlComponents.url else {
                AppLogger.network.debug("Failed to construct checkstate URL")
                return false
            }

            // Build the request
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            request.timeoutInterval = 10  // Shorter timeout for state checks

            // Make the request
            let (data, response) = try await URLSession.shared.data(for: request)

            // Check HTTP status
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                AppLogger.network.debug("Checkstate returned non-success status")
                return false
            }

            // Parse response
            let checkResponse = try JSONDecoder().decode(CheckStateResponse.self, from: data)

            // Transaction is pending if ALL proofs are unspent
            let isPending = checkResponse.states.allSatisfy { $0.state == "UNSPENT" }
            AppLogger.network.debug("Transaction pending check: \(isPending) for \(ys.count) proofs")
            return isPending

        } catch {
            AppLogger.network.debug("Failed to check proof state: \(error.localizedDescription)")
            return false  // Assume completed on error (safe default)
        }
    }

    // MARK: - Transaction Reclaim

    /// Reclaim a pending transaction by reverting it
    /// This returns the proofs to the wallet if they haven't been claimed
    func reclaimTransaction(transactionId: String, mintUrl: String) async throws {
        guard let multiMintWallet = self.wallet else {
            AppLogger.wallet.error("Wallet not available for reclaim")
            throw WalletError.walletNotInitialized
        }

        // Get the single-mint wallet for this transaction's mint
        let mint = MintUrl(url: mintUrl)
        guard let singleWallet = await multiMintWallet.getWallet(mintUrl: mint) else {
            AppLogger.wallet.error("Wallet not found for mint: \(mintUrl)")
            throw WalletError.walletNotInitialized
        }

        let id = TransactionId(hex: transactionId)
        try await singleWallet.revertTransaction(id: id)
        AppLogger.network.info("Successfully reclaimed transaction: \(transactionId)")

        // Refresh balance after reclaim
        refreshBalance()
    }
}

enum WalletError: LocalizedError {
    case walletNotInitialized
    case failedToGenerateMnemonic
    case mintHasBalance

    var errorDescription: String? {
        switch self {
        case .walletNotInitialized:
            return "Wallet is not initialized"
        case .failedToGenerateMnemonic:
            return "Failed to generate or retrieve wallet mnemonic"
        case .mintHasBalance:
            return "Cannot remove mint with remaining balance. Please transfer or spend funds first."
        }
    }
}
