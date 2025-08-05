import Foundation
import Security
import CashuDevKit

class WalletManager: ObservableObject {
    private let keychainService = "app.paywithsats.keychain"
    private let mnemonicKey = "wallet_mnemonic"
    private let defaultMintURL = "https://fake.thesimplekid.dev"
    
    @Published var wallet: Wallet?
    @Published var isInitialized = false
    
    private var documentsURL: URL {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return urls[0]
    }
    
    private var walletDataURL: URL {
        return documentsURL.appendingPathComponent("wallet_data", isDirectory: true)
    }
    
    init() {
        setupWalletDirectory()
        Task {
            await initializeWallet()
        }
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
        let mnemonic = getMnemonicFromKeychain() ?? generateAndStoreMnemonic()
        
        do {
            let walletConfig = WalletConfig(
                workDir: walletDataURL.path,
                targetProofCount: nil
            )
            
            self.wallet = try await Wallet(
                mintUrl: defaultMintURL,
                unit: CurrencyUnit.sat,
                mnemonic: mnemonic,
                config: walletConfig
            )
            
            await MainActor.run {
                self.isInitialized = true
            }
        } catch {
            print("Failed to initialize wallet: \(error)")
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
        do {
            return try CashuDevKit.generateMnemonic()
        } catch {
            print("Failed to generate mnemonic: \(error)")
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
            return []
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
            return 0
        }
        
        do {
            let balance = try await wallet.totalBalance()
            return balance.value
        } catch {
            print("Failed to get balance: \(error)")
            return 0
        }
    }
}
