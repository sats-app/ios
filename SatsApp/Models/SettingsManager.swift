import Foundation
import Combine

/// Manages user preferences stored in UserDefaults (App Groups container)
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let defaults: UserDefaults
    private let defaultMintKey = "defaultMintUrl"
    private let hideBalanceKey = "hideBalance"

    @Published var defaultMintUrl: String? {
        didSet {
            defaults.set(defaultMintUrl, forKey: defaultMintKey)
            AppLogger.settings.debug("Default mint updated: \(self.defaultMintUrl ?? "none")")
        }
    }

    @Published var hideBalance: Bool {
        didSet {
            defaults.set(hideBalance, forKey: hideBalanceKey)
            AppLogger.settings.debug("Hide balance updated: \(self.hideBalance)")
        }
    }

    private init() {
        // Use App Groups UserDefaults for extension compatibility
        defaults = UserDefaults(suiteName: "group.app.paywithsats") ?? .standard

        // Load initial values
        defaultMintUrl = defaults.string(forKey: defaultMintKey)
        hideBalance = defaults.bool(forKey: hideBalanceKey)

        AppLogger.settings.debug("SettingsManager initialized")
    }

    /// Clear the default mint if it's no longer in the configured mints list
    func validateDefaultMint(against configuredMints: [String]) {
        if let current = defaultMintUrl, !configuredMints.contains(current) {
            AppLogger.settings.info("Default mint no longer configured, clearing")
            defaultMintUrl = nil
        }
    }
}
