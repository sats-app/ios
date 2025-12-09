import Foundation

struct UITransaction: Identifiable {
    let id: String              // CDK TransactionId hex (for revert operations)
    let type: TransactionType
    let amount: Int
    let fee: Int                // Fee paid for this transaction
    let description: String
    let memo: String?
    let date: Date
    let status: TransactionStatus
    let mintUrl: String         // Mint URL for this transaction
}

enum TransactionType {
    case sent
    case received
    case request
}

enum TransactionStatus {
    case completed
    case pending
    case failed
}
