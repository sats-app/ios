import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var walletManager: WalletManager
    @State private var transactions: [UITransaction] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading transactions...")
                        Spacer()
                    }
                    .padding()
                } else if transactions.isEmpty {
                    HStack {
                        Spacer()
                        Text("No transactions yet")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding()
                } else {
                    ForEach(transactions, id: \.id) { transaction in
                        TransactionRowView(transaction: transaction)
                    }
                }
            }
            .balanceToolbar()
            .refreshable {
                await loadData()
            }
        }
        .task {
            await loadData()
        }
    }
    
    private func loadData() async {
        await MainActor.run {
            isLoading = true
        }
        
        let loadedTransactions = await walletManager.listTransactions()
        walletManager.refreshBalance()
        
        await MainActor.run {
            self.transactions = loadedTransactions
            self.isLoading = false
        }
    }
}

struct TransactionRowView: View {
    let transaction: UITransaction
    
    var body: some View {
        HStack {
            VStack {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(iconColor)
                    .frame(width: 24, height: 24)
            }
            .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.body)
                    .fontWeight(.medium)
                
                HStack {
                    Text(formatDate(transaction.date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if transaction.status != .completed {
                        Text("• \(statusText)")
                            .font(.caption)
                            .foregroundColor(statusColor)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text(amountText)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(amountColor)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var displayTitle: String {
        // Use memo as title if available, otherwise use "Sent" or "Received"
        if let memo = transaction.memo, !memo.isEmpty {
            return memo
        } else {
            switch transaction.type {
            case .sent:
                return "Sent"
            case .received:
                return "Received"
            case .request:
                return "Request"
            }
        }
    }
    
    private var iconName: String {
        switch transaction.type {
        case .received:
            return "arrow.down.circle.fill"
        case .sent:
            return "arrow.up.circle.fill"
        case .request:
            return "clock.circle.fill"
        }
    }
    
    private var iconColor: Color {
        switch transaction.status {
        case .completed:
            switch transaction.type {
            case .received:
                return .green
            case .sent:
                return .blue
            case .request:
                return .orange
            }
        case .pending:
            return .orange
        case .failed:
            return .red
        }
    }
    
    private var amountText: String {
        let prefix = transaction.type == .received ? "+" : "-"
        return "\(prefix)\(formatAmount(transaction.amount)) sat"
    }
    
    private var amountColor: Color {
        switch transaction.status {
        case .completed:
            return transaction.type == .received ? .green : .primary
        case .pending:
            return .orange
        case .failed:
            return .red
        }
    }
    
    private var statusText: String {
        switch transaction.status {
        case .completed:
            return "Completed"
        case .pending:
            return "Pending"
        case .failed:
            return "Failed"
        }
    }
    
    private var statusColor: Color {
        switch transaction.status {
        case .completed:
            return .green
        case .pending:
            return .orange
        case .failed:
            return .red
        }
    }
    
    private func formatAmount(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
    
    private func formatDate(_ date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            return "Just now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m ago"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours)h ago"
        } else if timeInterval < 604800 {
            let days = Int(timeInterval / 86400)
            return "\(days)d ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

#Preview {
    ActivityView()
        .environmentObject(WalletManager())
}