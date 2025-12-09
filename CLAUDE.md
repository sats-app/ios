# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. **IMPORTANT**: Update the `justfile`, `README.md`, and `CLAUDE.md` when making changes to the project structure or development flows.

## Project Overview

SatsApp is a Bitcoin wallet iOS application using the Cashu ecash protocol. It uses a SwiftUI-based interface with no authentication required - the wallet opens directly on launch.

## Build Commands

This project uses `just` (command runner) for build automation. Key commands:

```bash
# Build and Development
just build          # Build for iOS simulator
just run            # Build, install, and launch with log streaming
just quick          # Fast rebuild and run (skips clean)

# Testing and Debugging
just test           # Run tests on simulator
just logs           # Stream console logs

# Dependency Management
just deps           # Install Swift Package dependencies
just update-deps    # Update all dependencies
just show-deps      # Show resolved package versions

# Utilities
just clean          # Clean build artifacts
just simulators     # Show available simulators
just open           # Open project in Xcode
just reset          # Clean + reset all simulators
```

**IMPORTANT**: Use the `justfile` to run and codify common development tasks. Update the tasks as necessary. Keep the tasks simple and DRY (do not repeat yourself).

## Architecture

The app follows MVVM pattern with SwiftUI:

- **App/SatsApp.swift**: Main app entry with @StateObject WalletManager
- **Models/**: Business logic and state management
  - `WalletManager`: Cashu wallet operations via MultiMintWallet, balance tracking, mint management
  - `StorageManager`: iCloud/local storage management for wallet data
  - `MintDirectory`, `MintInfoService`: Mint discovery and info fetching
  - `UITransaction`: Transaction data model for UI display
  - `AppLogger`: Centralized logging utility
- **Views/**: SwiftUI views organized by feature
  - First launch: MintSelectionView, MintDetailView (configure initial mint)
  - Main app: ContentView (tab container) -> TransactView, ActivityView, BalanceView
  - Sheets: DepositSheetView (funding flow), WalletLoadingView (initialization)
- **Components/**: Reusable UI components
  - `Theme.swift`: Centralized UI theming and styling
  - `QRCodeView.swift`, `AnimatedQRCodeView.swift`: QR code display (static and animated)

## Key Dependencies

- **Cashu/Bitcoin**: `cdk-swift` 0.14.2 (Cashu Development Kit) - provides MultiMintWallet and WalletSqliteDatabase

## Development Notes

### Storage
- Wallet data stored in iCloud Documents (with local fallback if iCloud unavailable)
- Mnemonic (seed) stored as seed.txt in wallet directory
- SQLite database (wallet.db) for wallet state via WalletSqliteDatabase
- StorageManager handles storage location selection and file operations

### Wallet Integration
- Uses MultiMintWallet for multi-mint support with unified balance
- First launch requires mint selection (MintSelectionView)
- Connects to Cashu mints for ecash operations
- Supports Lightning invoice generation for funding (mint quote/melt)

### Common Issues and Solutions

**Package Resolution**: If dependencies fail to resolve:
```bash
just clean
just update-deps
just build
```

### Logging
Use the iOS logging library. Most logs should remain at the DEBUG level, however log important applications events at INFO. Use WARN and ERROR as appropriate.

### Amount Display
- Amounts use Bitcoin symbol as prefix: `₿1,000` (no space between symbol and number)
- Primary formatter: `WalletManager.formattedBalance` uses NumberFormatter with comma grouping
- Used consistently across: balance display, transaction amounts, deposit flow, mints drawer

## Project Configuration

- **Bundle ID**: app.paywithsats
- **Minimum iOS**: 16.0 (deployment target)
- **Swift Version**: 5.0
- **Xcode Project**: SatsApp.xcodeproj

