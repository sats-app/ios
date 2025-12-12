import UIKit
import Messages
import SwiftUI

/// Main view controller for the iMessage extension
/// Hosts SwiftUI views and handles message interactions
class MessagesViewController: MSMessagesAppViewController {
    private var hostingController: UIHostingController<AnyView>?
    private var walletManager: WalletManager?
    private var isWalletReady = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)

        // Initialize storage and wallet
        StorageManager.shared.initialize()

        // Create wallet manager and initialize
        let manager = WalletManager()
        self.walletManager = manager

        Task {
            await manager.initializeWallet()
            await MainActor.run {
                self.isWalletReady = manager.isInitialized
                self.setupSwiftUIHost(conversation: conversation)
            }
        }
    }

    override func didResignActive(with conversation: MSConversation) {
        super.didResignActive(with: conversation)
        // Clean up hosting controller
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        hostingController = nil
    }

    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)

        // Handle tapped messages containing tokens
        guard let url = message.url else { return }

        if let token = extractToken(from: url) {
            openTokenInMainApp(token)
        }
    }

    override func didStartSending(_ message: MSMessage, conversation: MSConversation) {
        super.didStartSending(message, conversation: conversation)
        // Dismiss to compact after sending
        requestPresentationStyle(.compact)
    }

    // MARK: - Setup

    private func setupSwiftUIHost(conversation: MSConversation?) {
        // Remove existing host if any
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()

        guard let manager = walletManager else { return }

        let rootView = MessageAppView(
            walletManager: manager,
            isWalletReady: isWalletReady,
            sendMessage: { [weak self] message in
                self?.insertMessage(message, conversation: conversation)
            },
            requestExpanded: { [weak self] in
                self?.requestPresentationStyle(.expanded)
            },
            requestCompact: { [weak self] in
                self?.requestPresentationStyle(.compact)
            }
        )

        let hostingController = UIHostingController(rootView: AnyView(rootView))
        addChild(hostingController)
        view.addSubview(hostingController.view)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        hostingController.didMove(toParent: self)
        self.hostingController = hostingController
    }

    // MARK: - Message Handling

    private func insertMessage(_ message: MSMessage, conversation: MSConversation?) {
        guard let conversation = conversation ?? activeConversation else {
            AppLogger.ui.error("No active conversation to insert message")
            return
        }

        conversation.insert(message) { error in
            if let error = error {
                AppLogger.ui.error("Failed to insert message: \(error.localizedDescription)")
            } else {
                AppLogger.ui.debug("Message inserted successfully")
            }
        }
    }

    private func extractToken(from url: URL) -> String? {
        // Handle data: URL scheme (data:cashu,<token>)
        let urlString = url.absoluteString
        if urlString.hasPrefix("data:cashu,") {
            return String(urlString.dropFirst("data:cashu,".count))
        }
        if urlString.hasPrefix("data:creq,") {
            return String(urlString.dropFirst("data:creq,".count))
        }
        return nil
    }

    private func openTokenInMainApp(_ token: String) {
        guard let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "cashu://receive?token=\(encoded)") else {
            AppLogger.ui.error("Failed to create URL for token")
            return
        }

        extensionContext?.open(url) { success in
            if success {
                AppLogger.ui.info("Opened token in main app")
            } else {
                AppLogger.ui.error("Failed to open token in main app")
            }
        }
    }
}
