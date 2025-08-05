import Foundation
import Security
import CashuDevKit

class WalletManager: ObservableObject {
    private let keychainService = "app.paywithsats.keychain"
    private let mnemonicKey = "wallet_mnemonic"
    let defaultMintURL = "https://fake.thesimplekid.dev"
    
    @Published var wallet: Wallet?
    @Published var isInitialized = false
    @Published var initializationError: String?
    @Published var isLoading = true
    
    private var documentsURL: URL {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return urls[0]
    }
    
    private var walletDataURL: URL {
        return documentsURL.appendingPathComponent("wallet_data", isDirectory: true)
    }
    
    init() {
        print("WalletManager: Initializing...")
        setupWalletDirectory()
        print("WalletManager: Starting wallet initialization task...")
        Task {
            await initializeWallet()
        }
        print("WalletManager: Init complete, task started")
    }
    
    private func setupWalletDirectory() {
        do {
            try FileManager.default.createDirectory(at: walletDataURL, withIntermediateDirectories: true, attributes: nil)
            
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = false
            var url = walletDataURL
            try url.setResourceValues(resourceValues)
            
            print("Wallet data directory configured at: \(walletDataURL.path)")
            print("iCloud backup enabled for wallet data")
        } catch {
            print("Failed to setup wallet directory: \(error)")
        }
    }
    
    private func initializeWallet() async {
        print("Starting wallet initialization...")
        
        await MainActor.run {
            self.isLoading = true
            self.initializationError = nil
        }
        
        // For now, let's skip the actual wallet initialization to test UI
        // and just simulate a successful initialization after a short delay
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        print("Retrieving mnemonic...")
        let mnemonic = getMnemonicFromKeychain() ?? generateAndStoreMnemonic()
        print("Mnemonic retrieved/generated: \(!mnemonic.isEmpty)")
        
        // Check if mnemonic is valid
        guard !mnemonic.isEmpty else {
            print("ERROR: Mnemonic is empty")
            await MainActor.run {
                self.initializationError = "Failed to generate or retrieve wallet mnemonic"
                self.isLoading = false
            }
            return
        }
        
        // For testing purposes, just mark as initialized without creating the actual wallet
        await MainActor.run {
            // self.wallet = nil // We'll create this later when actually needed
            self.isInitialized = true
            self.isLoading = false
            print("Wallet initialized successfully (simulation mode)")
        }
        
        // Comment out the actual wallet creation for now
        /*
        // Add timeout wrapper
        do {
            try await withTimeout(30.0) {
                await self.performWalletInitialization()
            }
        } catch {
            print("ERROR: Wallet initialization timed out or failed: \(error)")
            await MainActor.run {
                if error is TimeoutError {
                    self.initializationError = "Wallet initialization timed out. Please check your internet connection and try again."
                } else {
                    self.initializationError = "Failed to initialize wallet: \(error.localizedDescription)"
                }
                self.isLoading = false
            }
        }
        */
    }
    
    private func performWalletInitialization() async throws {
        print("Retrieving mnemonic...")
        let mnemonic = getMnemonicFromKeychain() ?? generateAndStoreMnemonic()
        print("Mnemonic retrieved/generated: \(!mnemonic.isEmpty)")
        
        // Check if mnemonic is valid
        guard !mnemonic.isEmpty else {
            print("ERROR: Mnemonic is empty")
            await MainActor.run {
                self.initializationError = "Failed to generate or retrieve wallet mnemonic"
                self.isLoading = false
            }
            return
        }
        
        print("Creating wallet config with workDir: \(walletDataURL.path)")
        let walletConfig = WalletConfig(
            workDir: walletDataURL.path,
            targetProofCount: nil
        )
        
        print("Initializing wallet with mint: \(defaultMintURL)")
        let newWallet = try await Wallet(
            mintUrl: defaultMintURL,
            unit: CurrencyUnit.sat,
            mnemonic: mnemonic,
            config: walletConfig
        )
        
        print("Wallet created successfully, updating UI...")
        await MainActor.run {
            self.wallet = newWallet
            self.isInitialized = true
            self.isLoading = false
            print("Wallet initialized successfully with mint: \(self.defaultMintURL)")
        }
    }
    
    // Add timeout functionality
    private func withTimeout<T>(_ timeout: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TimeoutError()
            }
            
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            
            group.cancelAll()
            return result
        }
    }
    
    // Public method to retry initialization if it fails
    func retryInitialization() {
        Task {
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
        print("Generating new mnemonic...")
        do {
            let mnemonic = try CashuDevKit.generateMnemonic()
            print("Mnemonic generated successfully, length: \(mnemonic.count)")
            return mnemonic
        } catch {
            print("ERROR: Failed to generate mnemonic: \(error)")
            // Return a fallback empty mnemonic - this should trigger wallet initialization error
            return ""
        }
    }
    
    private func storeMnemonicInKeychain(_ mnemonic: String) {
        guard let data = mnemonic.data(using: .utf8) else {
            print("Failed to convert mnemonic to data")
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
            print("Failed to store mnemonic in keychain: \(status)")
        }
    }
    
    // MARK: - Transaction History
    
    func listTransactions() async -> [Transaction] {
        guard let wallet = self.wallet else {
            print("Wallet not available, returning mock transactions")
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
            print("Failed to get transactions: \(error)")
            return []
        }
    }
    
    // MARK: - Balance
    
    func getBalance() async -> UInt64 {
        guard let wallet = self.wallet else {
            print("Wallet not available, returning mock balance")
            return 21000 // Return mock balance for testing
        }
        
        do {
            let balance = try await wallet.totalBalance()
            return balance.value
        } catch {
            print("Failed to get balance: \(error)")
            return 0
        }
    }
    
    // MARK: - Mint Quote
    
    func generateMintQuote(amount: UInt64) async throws -> (String, String) {
        guard let wallet = self.wallet else {
            print("Wallet not available, returning mock mint quote")
            // Return mock data for testing
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay to simulate network
            let mockInvoice = "lnbc\(amount)u1p3xnhl2pp5jptserfk3zk4qy42tlucycrfwxhydvlemu9pqr93tuzlv9cc7g3s6qsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygs9q7sqqqqqqqqqqqqqqqqqqqsqqqqqysgx5vwd4hy6tsw56kd5ltx83m7fqd9d7zqj"
            return (mockInvoice, "Unpaid")
        }
        
        do {
            let amountObj = Amount(value: amount)
            let mintQuote = try await wallet.mintQuote(amount: amountObj, description: nil)
            let state = mintQuote.state()
            let statusString = switch state {
            case .unpaid: "Unpaid"
            case .paid: "Paid"
            case .pending: "Pending"
            case .issued: "Issued"
            }
            return (mintQuote.request(), statusString)
        } catch {
            print("Failed to generate mint quote: \(error)")
            throw error
        }
    }
}

struct TimeoutError: Error, LocalizedError {
    var errorDescription: String? {
        return "Operation timed out"
    }
}

enum WalletError: LocalizedError {
    case walletNotInitialized
    
    var errorDescription: String? {
        switch self {
        case .walletNotInitialized:
            return "Wallet is not initialized"
        }
    }
}
