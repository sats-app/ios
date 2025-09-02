import Foundation
import Security
import CashuDevKit
import os.log

/// Central logging utility for the SatsApp
struct AppLogger {
    /// The subsystem for all app logs
    static let subsystem = "app.paywithsats"
    
    /// Logger for wallet-related operations
    static let wallet = Logger(subsystem: subsystem, category: "wallet")
    
    /// Logger for UI-related operations
    static let ui = Logger(subsystem: subsystem, category: "ui")
    
    /// Logger for transaction-related operations
    static let transaction = Logger(subsystem: subsystem, category: "transaction")
    
    /// Logger for network/API operations
    static let network = Logger(subsystem: subsystem, category: "network")
    
    /// Logger for minting operations
    static let mint = Logger(subsystem: subsystem, category: "mint")
    
    /// Logger for general app operations
    static let general = Logger(subsystem: subsystem, category: "general")
}


class WalletManager: ObservableObject {
    private let keychainService = "app.paywithsats.keychain"
    private let mnemonicKey = "wallet_mnemonic"
    let defaultMintURL = "https://fake.thesimplekid.dev"
    
    @Published var wallet: Wallet?
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
        
        let walletDatabasePath = walletDataURL.appendingPathComponent("wallet.sqlite").path
        AppLogger.wallet.info("Creating wallet database with path: \(walletDatabasePath)")
        let database = try await WalletSqliteDatabase(filePath: walletDatabasePath)
        
        AppLogger.wallet.info("Initializing wallet with mint: \(self.defaultMintURL)")
        let newWallet = try await Wallet(
            mintUrl: defaultMintURL,
            unit: CurrencyUnit.sat,
            mnemonic: mnemonic,
            db: database,
            config: walletConfig
        )
        
        AppLogger.wallet.info("Wallet created successfully, updating UI...")
        await MainActor.run {
            self.wallet = newWallet
            self.isInitialized = true
            self.isLoading = false
            AppLogger.wallet.info("✅ Wallet initialized successfully with mint: \(self.defaultMintURL)")
            
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
    
    func listTransactions() async -> [Transaction] {
        guard let wallet = self.wallet else {
            AppLogger.transaction.debug("Wallet not available, returning mock transactions")
            // Return some mock transactions for testing
            let mockTransactions = [
                Transaction(
                    type: .received,
                    amount: 5000,
                    description: "Received",
                    memo: "Payment from Alice",
                    date: Date().addingTimeInterval(-3600), // 1 hour ago
                    status: .completed
                ),
                Transaction(
                    type: .sent,
                    amount: 1200,
                    description: "Sent", 
                    memo: "Coffee purchase",
                    date: Date().addingTimeInterval(-7200), // 2 hours ago
                    status: .completed
                ),
                Transaction(
                    type: .received,
                    amount: 3000,
                    description: "Received",
                    memo: "Tip received",
                    date: Date().addingTimeInterval(-14400), // 4 hours ago
                    status: .completed
                )
            ]
            return mockTransactions
        }
        
        do {
            // Get proofs by different states to simulate transaction history
            let allStates: [ProofState] = [.unspent, .spent, .pending]
            let proofs = try await wallet.getProofsByStates(states: allStates)
            
            // Convert proofs to transactions
            var transactions: [Transaction] = []
            
            // For now, create mock transactions based on proofs
            // In a real implementation, this would need actual transaction tracking
            for (index, proof) in proofs.enumerated() {
                let isReceived = index % 2 == 0
                let mockMemos = [
                    "Payment from Alice",
                    "Coffee purchase",
                    "Lunch money",
                    "Book payment",
                    "Tip received",
                    "Service fee",
                    "Refund",
                    "Donation"
                ]
                let memo = mockMemos[index % mockMemos.count]
                
                // Get actual amount from proof
                let amount = Int(proof.amount().value)
                
                let transaction = Transaction(
                    type: isReceived ? .received : .sent,
                    amount: amount > 0 ? amount : 1000 + (index * 100), // Use proof amount or fallback
                    description: isReceived ? "Received" : "Sent",
                    memo: memo,
                    date: Date().addingTimeInterval(-Double(index * 3600)), // Mock dates
                    status: .completed // Since proofs exist, assume completed
                )
                transactions.append(transaction)
            }
            
            return transactions.sorted { $0.date > $1.date }
        } catch {
            AppLogger.transaction.error("Failed to get transactions: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Balance
    
    func getBalance() async -> UInt64 {
        guard let wallet = self.wallet else {
            AppLogger.wallet.debug("Wallet not available, returning mock balance")
            return 21000 // Return mock balance for testing
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
    
    func generateMintQuote(amount: UInt64) async throws -> (String, String, String) {
        guard let wallet = self.wallet else {
            AppLogger.mint.debug("Wallet not available, returning mock mint quote")
            // Return mock data for testing
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay to simulate network
            let mockInvoice = "lnbc\(amount)u1p3xnhl2pp5jptserfk3zk4qy42tlucycrfwxhydvlemu9pqr93tuzlv9cc7g3s6qsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygs9q7sqqqqqqqqqqqqqqqqqqqsqqqqqysgx5vwd4hy6tsw56kd5ltx83m7fqd9d7zqj"
            let mockQuoteId = "mock_quote_\(UUID().uuidString.prefix(8))"
            return (mockInvoice, "Unpaid", mockQuoteId)
        }
        
        do {
            let amountObj = Amount(value: amount)
            let mintQuote = try await wallet.mintQuote(amount: amountObj, description: nil)
            let state = mintQuote.state
            let statusString = switch state {
            case .unpaid: "Unpaid"
            case .paid: "Paid"
            case .pending: "Pending"
            case .issued: "Issued"
            }
            return (mintQuote.request, statusString, mintQuote.id)
        } catch {
            AppLogger.mint.error("Failed to generate mint quote: \(error.localizedDescription)")
            throw error
        }
    }
    
    func checkMintQuoteStatus(quoteId: String) async throws -> String {
        guard self.wallet != nil else {
            AppLogger.mint.debug("Wallet not available, simulating quote status check")
            // Simulate payment after some time
            let randomDelay = Int.random(in: 3...8)
            if Date().timeIntervalSince1970.truncatingRemainder(dividingBy: Double(randomDelay)) < 2 {
                return "Paid"
            }
            return "Unpaid"
        }
        
        // For now, we'll need to regenerate the quote to check its status
        // This is a limitation - ideally we'd store the MintQuote object
        // or have a dedicated status check method
        AppLogger.mint.warning("Cannot check quote status directly - method not available in current API")
        return "Unpaid" // Default to unpaid for now
    }
    
    func mintTokens(quoteId: String) async throws -> UInt64 {
        guard let wallet = self.wallet else {
            AppLogger.mint.debug("Wallet not available, simulating minting")
            // Simulate minting delay
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            return 1000 // Return mock minted amount
        }
        
        do {
            let proofs = try await wallet.mint(quoteId: quoteId, amountSplitTarget: SplitTarget.none, spendingConditions: nil)
            let totalMinted = proofs.reduce(0) { total, proof in
                total + proof.amount().value
            }
            AppLogger.mint.info("✅ Successfully minted \(totalMinted) sats from quote \(quoteId)")
            return totalMinted
        } catch {
            AppLogger.mint.error("Failed to mint tokens: \(error.localizedDescription)")
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
