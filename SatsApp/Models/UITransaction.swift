import Foundation

struct UITransaction {
    let id = UUID()
    let type: TransactionType
    let amount: Int
    let description: String
    let memo: String?
    let date: Date
    let status: TransactionStatus
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
