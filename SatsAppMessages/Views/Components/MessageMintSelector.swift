import SwiftUI

/// Mint selector dropdown for the iMessage extension
struct MessageMintSelector: View {
    @Binding var selectedMint: String
    let mints: [String]
    let balances: [String: UInt64]
    let getMintDisplayName: (String) -> String

    var body: some View {
        HStack {
            Image(systemName: "building.columns")
                .foregroundColor(.orange)
                .font(.subheadline)

            Picker("Mint", selection: $selectedMint) {
                ForEach(mints, id: \.self) { mint in
                    Text(mintLabel(for: mint))
                        .tag(mint)
                }
            }
            .pickerStyle(.menu)
            .tint(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(8)
    }

    private func mintLabel(for mint: String) -> String {
        let name = getMintDisplayName(mint)
        let balance = balances[mint] ?? 0
        return "\(name) (\(WalletManager.formatAmount(balance)))"
    }
}
