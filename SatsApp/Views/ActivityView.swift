import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var walletManager: WalletManager
    @State private var transactions: [UITransaction] = []
    @State private var isLoading = true
    @State private var showingReclaimAlert = false
    @State private var transactionToReclaim: UITransaction?
    @State private var reclaimError: String?
    @State private var showingErrorAlert = false
    @State private var selectedTransaction: UITransaction?

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
                        Button {
                            selectedTransaction = transaction
                        } label: {
                            TransactionRowView(transaction: transaction)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if transaction.type == .sent && transaction.status == .pending {
                                Button("Reclaim") {
                                    transactionToReclaim = transaction
                                    showingReclaimAlert = true
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
            }
            .balanceToolbar()
            .refreshable {
                await loadData()
            }
            .alert("Reclaim Transaction?", isPresented: $showingReclaimAlert) {
                Button("Cancel", role: .cancel) {
                    transactionToReclaim = nil
                }
                Button("Reclaim") {
                    Task { await performReclaim() }
                }
            } message: {
                Text("This will return the funds to your wallet. Only do this if the recipient has not claimed the payment.")
            }
            .alert("Reclaim Failed", isPresented: $showingErrorAlert) {
                Button("OK", role: .cancel) {
                    reclaimError = nil
                }
            } message: {
                Text(reclaimError ?? "These funds may have already been claimed by the recipient.")
            }
            .adaptiveSheet(item: $selectedTransaction) { transaction in
                TransactionDetailView(
                    transaction: transaction,
                    onReclaim: transaction.type == .sent && transaction.status == .pending
                        ? { await performReclaimFromDetail(transaction) }
                        : nil
                )
                .environmentObject(walletManager)
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

    private func performReclaim() async {
        guard let transaction = transactionToReclaim else { return }

        do {
            try await walletManager.reclaimTransaction(
                transactionId: transaction.id,
                mintUrl: transaction.mintUrl
            )
            await loadData()  // Refresh the list
        } catch {
            await MainActor.run {
                reclaimError = error.localizedDescription
                showingErrorAlert = true
            }
        }

        await MainActor.run {
            transactionToReclaim = nil
        }
    }

    private func performReclaimFromDetail(_ transaction: UITransaction) async {
        do {
            try await walletManager.reclaimTransaction(
                transactionId: transaction.id,
                mintUrl: transaction.mintUrl
            )
            await MainActor.run {
                selectedTransaction = nil  // Dismiss sheet
            }
            await loadData()
        } catch {
            await MainActor.run {
                reclaimError = error.localizedDescription
                showingErrorAlert = true
            }
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
        // For sent transactions, show total including fee
        let displayAmount = transaction.type == .sent
            ? transaction.amount + transaction.fee
            : transaction.amount
        let prefix = transaction.type == .received ? "+" : "-"
        return "\(prefix)₿\(formatAmount(displayAmount))"
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