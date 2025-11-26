import SwiftUI
import CashuDevKit

enum TransactMode {
    case pay
    case request
    
    var buttonTitle: String {
        switch self {
        case .pay: return "Pay Bitcoin"
        case .request: return "Request Bitcoin"
        }
    }
    
    var iconName: String {
        switch self {
        case .pay: return "arrow.up.circle.fill"
        case .request: return "arrow.down.circle.fill"
        }
    }
    
    var successMessage: String {
        switch self {
        case .pay: return "Payment sent!"
        case .request: return "Request sent!"
        }
    }
}

struct TransactView: View {
    @EnvironmentObject var walletManager: WalletManager
    @State private var amount: String = "0"
    @State private var showingTransactSheet = false
    @State private var transactMode: TransactMode = .pay
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()
                
                Text("\(amount) sat")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(Color.orange)
                    .padding(.horizontal)
                
                Spacer()
                
                NumberPadView(amount: $amount)
                
                HStack(spacing: 16) {
                    Button("Request") {
                        transactMode = .request
                        showingTransactSheet = true
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .font(.headline)
                    
                    Button(action: {
                    }) {
                        Image(systemName: "qrcode")
                            .font(.title2)
                            .foregroundColor(Color.orange)
                    }
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    
                    Button("Pay") {
                        transactMode = .pay
                        showingTransactSheet = true
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .font(.headline)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .balanceToolbar()
            .sheet(isPresented: $showingTransactSheet, onDismiss: {
                amount = "0"
            }) {
                TransactSheetView(amount: amount, mode: transactMode)
            }
        }
        .onAppear {
            walletManager.refreshBalance()
        }
    }
    
}

struct NumberPadView: View {
    @Binding var amount: String
    
    let buttons = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "⌫"]
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(buttons, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { button in
                        Button(action: {
                            handleButtonPress(button)
                        }) {
                            Text(button)
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(Color.orange)
                                .frame(maxWidth: .infinity, minHeight: 60)
                                .background(Color.clear)
                                .cornerRadius(8)
                        }
                        .disabled(button.isEmpty)
                    }
                }
            }
        }
        .padding(.horizontal)
    }
    
    private func handleButtonPress(_ button: String) {
        switch button {
        case "⌫":
            if !amount.isEmpty && amount != "0" {
                amount = String(amount.dropLast())
                if amount.isEmpty {
                    amount = "0"
                }
            }
        case "0":
            if amount != "0" {
                amount += button
            }
        default:
            if amount == "0" {
                amount = button
            } else {
                amount += button
            }
        }
    }
}

struct TransactSheetView: View {
    let amount: String
    let mode: TransactMode
    @EnvironmentObject var walletManager: WalletManager
    @State private var selectedMintUrl: String = ""
    @State private var availableMints: [String] = []
    @State private var isLoadingMints = true
    @State private var memo: String = ""
    @State private var isViewableByRecipient: Bool = false
    @State private var isLoading: Bool = false
    @State private var showQRResult: Bool = false
    @State private var generatedContent: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 0) {
            if showQRResult {
                // QR Result view
                qrResultView
            } else {
                // Input form
                inputFormView
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .task {
            await loadMints()
        }
    }

    private var qrResultView: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 60, height: 60)

                    Image(systemName: mode.iconName)
                        .font(.title)
                        .foregroundColor(Color.white)
                }

                Text("\(amount) sat")
                    .font(.title2)
                    .bold()
                    .foregroundColor(Color.orange)
            }
            .padding(.top, 20)

            // QR Code
            QRCodeView(text: generatedContent)
                .frame(width: 200, height: 200)

            // Truncated content text
            Text(truncatedContent(generatedContent))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)

            // Action buttons
            HStack(spacing: 16) {
                ShareLink(item: generatedContent) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .font(.subheadline.weight(.medium))
                }

                Button(action: {
                    // NFC placeholder - not implemented
                }) {
                    HStack {
                        Image(systemName: "wave.3.right.circle")
                        Text("NFC")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.gray)
                    .cornerRadius(8)
                    .font(.subheadline.weight(.medium))
                }
                .disabled(true)
            }
            .padding(.horizontal, 20)

            Spacer()

            // Done button
            Button("Done") {
                presentationMode.wrappedValue.dismiss()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.orange)
            .foregroundColor(.white)
            .cornerRadius(12)
            .font(.headline)
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }

    private var inputFormView: some View {
        VStack(spacing: 20) {
            // Header section
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 60, height: 60)

                    Image(systemName: mode.iconName)
                        .font(.title)
                        .foregroundColor(Color.white)
                }

                Text("\(amount) sat")
                    .font(.title2)
                    .bold()
                    .foregroundColor(Color.orange)
            }
            .padding(.top, 20)

            // Mint selector (only for pay mode)
            if mode == .pay {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Mint")
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(Color.orange)

                    if isLoadingMints {
                        ProgressView()
                    } else if availableMints.isEmpty {
                        Text("No mints available")
                            .foregroundColor(.gray)
                    } else {
                        Picker("Mint", selection: $selectedMintUrl) {
                            ForEach(availableMints, id: \.self) { mint in
                                Text(URL(string: mint)?.host ?? mint)
                                    .tag(mint)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Memo field
            VStack(alignment: .leading, spacing: 8) {
                Text("Memo")
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(Color.orange)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                        .frame(height: 80)

                    if memo.isEmpty {
                        Text("Add a note...")
                            .foregroundColor(.gray)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }

                    TextField("", text: $memo)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .frame(height: 80, alignment: .topLeading)
                }
            }

            // Viewable by recipient checkbox
            HStack {
                Button(action: {
                    isViewableByRecipient.toggle()
                }) {
                    Image(systemName: isViewableByRecipient ? "checkmark.square.fill" : "square")
                        .foregroundColor(isViewableByRecipient ? Color.orange : .gray)
                }

                Text("Viewable by Recipient")
                    .font(.subheadline)
                    .foregroundColor(Color.orange)

                Spacer()
            }

            Spacer()

            // Bottom button section
            Button(action: {
                handleTransaction()
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    Text(isLoading ? "Processing..." : mode.buttonTitle)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.orange)
            .foregroundColor(.white)
            .cornerRadius(12)
            .font(.headline)
            .disabled(isLoading)
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 20)
    }

    private func truncatedContent(_ content: String) -> String {
        let maxLength = 30
        if content.count <= maxLength {
            return content
        }
        let prefixLength = 12
        let suffixLength = 12
        let prefix = String(content.prefix(prefixLength))
        let suffix = String(content.suffix(suffixLength))
        return "\(prefix)...\(suffix)"
    }

    private func loadMints() async {
        isLoadingMints = true

        let mints = await walletManager.getMints()
        await MainActor.run {
            self.availableMints = mints
            if !mints.isEmpty && selectedMintUrl.isEmpty {
                self.selectedMintUrl = mints[0]
            }
            self.isLoadingMints = false
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }

    private func handleTransaction() {
        isLoading = true

        Task {
            do {
                switch mode {
                case .pay:
                    // Generate real Cashu token
                    guard !selectedMintUrl.isEmpty else {
                        await MainActor.run {
                            showError("Please select a mint")
                            isLoading = false
                        }
                        return
                    }

                    guard let amountValue = UInt64(amount), amountValue > 0 else {
                        await MainActor.run {
                            showError("Invalid amount")
                            isLoading = false
                        }
                        return
                    }

                    let token = try await walletManager.send(
                        mintUrl: selectedMintUrl,
                        amount: amountValue,
                        memo: memo.isEmpty ? nil : memo
                    )

                    await MainActor.run {
                        generatedContent = token
                        isLoading = false
                        showQRResult = true
                    }

                    // Refresh balance after sending
                    walletManager.refreshBalance()

                case .request:
                    // Placeholder for Cashu Payment Request (NUT-18)
                    // Format: creq:placeholder:<amount>:<memo>
                    let memoParam = memo.isEmpty ? "" : ":\(memo)"
                    let placeholder = "creq:placeholder:\(amount)\(memoParam)"

                    await MainActor.run {
                        generatedContent = placeholder
                        isLoading = false
                        showQRResult = true
                    }
                }
            } catch {
                await MainActor.run {
                    showError("Transaction failed: \(error.localizedDescription)")
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    TransactView()
}
