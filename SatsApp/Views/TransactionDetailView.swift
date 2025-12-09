import SwiftUI

struct TransactionDetailView: View {
    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.dismiss) private var dismiss

    let transaction: UITransaction
    let onReclaim: (() async -> Void)?

    @State private var isReclaiming = false
    @State private var showingReclaimAlert = false
    @State private var reclaimError: String?
    @State private var showingErrorAlert = false
    @State private var showCopiedFeedback = false

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            Divider()
                .padding(.horizontal, 20)

            detailsSection

            Spacer()

            if canReclaim {
                actionSection
            }
        }
        .alert("Reclaim Transaction?", isPresented: $showingReclaimAlert) {
            Button("Cancel", role: .cancel) { }
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
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconBackgroundColor)
                    .frame(width: 60, height: 60)

                Image(systemName: iconName)
                    .font(.title)
                    .foregroundColor(.white)
            }
            .padding(.top, 20)

            // Amount
            Text(formattedAmount)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(amountColor)

            // Fee breakdown
            if transaction.type == .sent && transaction.fee > 0 {
                Text("\(formatAmount(transaction.amount)) + \(formatAmount(transaction.fee)) fee")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Status badge
            statusBadge
        }
        .padding(.bottom, 24)
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(spacing: 16) {
            detailRow(label: "Type", value: typeDisplayName)

            detailRow(label: "Date", value: fullDateString)

            detailRow(label: "Status", value: statusText, valueColor: statusColor)

            if let memo = transaction.memo, !memo.isEmpty {
                detailRow(label: "Memo", value: memo)
            }

            detailRow(label: "Mint", value: mintDisplayName)

            transactionIdRow
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    // MARK: - Action Section

    private var actionSection: some View {
        VStack(spacing: 12) {
            Button(action: {
                showingReclaimAlert = true
            }) {
                HStack {
                    if isReclaiming {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    Text(isReclaiming ? "Reclaiming..." : "Reclaim Funds")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isReclaiming)

            Button("Close") {
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }

    // MARK: - Helper Views

    private func detailRow(label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(valueColor)
        }
    }

    private var transactionIdRow: some View {
        HStack {
            Text("Transaction ID")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(truncatedId)
                .font(.subheadline.monospaced())
                .foregroundColor(.primary)
            Button {
                UIPasteboard.general.string = transaction.id
                withAnimation {
                    showCopiedFeedback = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        showCopiedFeedback = false
                    }
                }
            } label: {
                Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundColor(showCopiedFeedback ? .green : .secondary)
            }
        }
    }

    private var statusBadge: some View {
        Text(statusText)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(statusColor)
            .cornerRadius(12)
    }

    // MARK: - Computed Properties

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

    private var iconBackgroundColor: Color {
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

    private var formattedAmount: String {
        let displayAmount = transaction.type == .sent
            ? transaction.amount + transaction.fee
            : transaction.amount
        let prefix = transaction.type == .received ? "+" : "-"
        return "\(prefix)\(formatAmount(displayAmount))"
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

    private var typeDisplayName: String {
        switch transaction.type {
        case .sent:
            return "Sent"
        case .received:
            return "Received"
        case .request:
            return "Request"
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

    private var fullDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter.string(from: transaction.date)
    }

    private var mintDisplayName: String {
        walletManager.getMintDisplayName(for: transaction.mintUrl)
    }

    private var truncatedId: String {
        let id = transaction.id
        if id.count > 16 {
            return "\(id.prefix(8))...\(id.suffix(8))"
        }
        return id
    }

    private var canReclaim: Bool {
        transaction.type == .sent && transaction.status == .pending
    }

    // MARK: - Actions

    private func formatAmount(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return "\u{20BF}" + (formatter.string(from: NSNumber(value: amount)) ?? "0")
    }

    private func performReclaim() async {
        await MainActor.run {
            isReclaiming = true
        }

        if let onReclaim = onReclaim {
            await onReclaim()
        }

        await MainActor.run {
            isReclaiming = false
            dismiss()
        }
    }
}

#Preview {
    TransactionDetailView(
        transaction: UITransaction(
            id: "abc123def456abc123def456abc123def456",
            type: .sent,
            amount: 1000,
            fee: 10,
            description: "Sent",
            memo: "Coffee payment",
            date: Date(),
            status: .pending,
            mintUrl: "https://mint.example.com"
        ),
        onReclaim: nil
    )
    .environmentObject(WalletManager())
}
