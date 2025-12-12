import Foundation
import os.log

/// Centralized logging utility for SatsApp
/// Provides categorized loggers for different subsystems
struct AppLogger {
    /// The subsystem identifier for all app logs
    private static let subsystem = "app.paywithsats"

    /// Logger for authentication operations (sign up, sign in, OTP verification)
    static let auth = Logger(subsystem: subsystem, category: "auth")

    /// Logger for wallet operations (balance, mnemonic, transactions, encryption, database)
    static let wallet = Logger(subsystem: subsystem, category: "wallet")

    /// Logger for UI-related operations and app lifecycle
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Logger for network/API operations (mint quotes, melt quotes, API calls)
    static let network = Logger(subsystem: subsystem, category: "network")

    /// Logger for storage operations (iCloud, file system, seed management)
    static let storage = Logger(subsystem: subsystem, category: "storage")

    /// Logger for settings and user preferences
    static let settings = Logger(subsystem: subsystem, category: "settings")
}
