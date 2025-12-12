import SwiftUI
import Messages
import UIKit

/// Confirmation view for creating payment requests via iMessage
struct MessageRequestView: View {
    @ObservedObject var walletManager: WalletManager
    let amount: UInt64
    let sendMessage: (MSMessage) -> Void
    let onCancel: () -> Void

    @State private var description: String = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var canRequest: Bool {
        amount > 0 && !isLoading
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Amount header
                Text("Request \(WalletManager.formatAmount(amount))")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                    .padding(.top, 8)

                // Description field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Note")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack {
                        Image(systemName: "text.bubble")
                            .foregroundColor(.gray)
                        TextField("What's this for?", text: $description)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(8)
                }
                .padding(.horizontal)

                Spacer()

                // Request button
                Button(action: createRequest) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(isLoading ? "Creating..." : "Request \(WalletManager.formatAmount(amount))")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(canRequest ? Color.orange : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(!canRequest)
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func createRequest() {
        guard canRequest else { return }

        isLoading = true

        Task {
            do {
                let request = try await walletManager.createPaymentRequest(
                    amount: amount,
                    description: description.isEmpty ? nil : description
                )

                let message = createRequestMessage(
                    request: request,
                    amount: amount,
                    description: description.isEmpty ? nil : description
                )

                await MainActor.run {
                    isLoading = false
                    sendMessage(message)
                }

            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func createRequestMessage(request: String, amount: UInt64, description: String?) -> MSMessage {
        let message = MSMessage()
        let layout = MSMessageTemplateLayout()

        layout.caption = "Request for \(WalletManager.formatAmount(amount))"
        if let description = description, !description.isEmpty {
            layout.subcaption = description
        }

        // Generate dynamic image with amount
        layout.image = MessageBubbleImageGenerator.generateImage(amount: amount, type: .request)

        message.layout = layout
        message.url = URL(string: "data:creq,\(request)")

        return message
    }
}
