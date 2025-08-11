# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. **IMPORTANT**: Update the `justfile`, `README.md`, and `CLAUDE.md` when making changes to the project structure or development flows.

## Project Overview

SatsApp is a Bitcoin wallet iOS application using the Cashu ecash protocol. It uses a SwiftUI-based interface with AWS Cognito authentication.

## Build Commands

This project uses `just` (command runner) for build automation. Key commands:

```bash
# Build and Development
just build          # Build for iOS simulator
just run           # Build, install, and launch with log streaming
just quick         # Fast rebuild and run (skips clean)

# Testing and Debugging
just test          # Run tests on simulator
just logs          # Stream console logs
just list-apps     # List all installed apps
just restart       # Restart the app

# Dependency Management
just deps          # Install Swift Package dependencies
just update-deps   # Update all dependencies
just show-deps     # Show resolved package versions

# Utilities
just clean         # Clean build artifacts
just uninstall     # Remove app from simulator
just boot          # Boot iOS simulator
```

**IMPORTANT**: Use the `justfile` to run and codify common development tasks. Update the tasks as necessary. Keep the tasks simple and DRY (do not repeat yourself).

## Architecture

The app follows MVVM pattern with SwiftUI:

- **App/SatsApp.swift**: Main app entry with @StateObject managers (WalletManager, AuthManager)
- **Models/**: Business logic and state management
  - `WalletManager`: Cashu wallet operations, mnemonic generation, Lightning invoice creation
  - `AuthManager`: AWS Cognito authentication flow
- **Views/**: SwiftUI views organized by feature
  - Authentication flow: AuthView → SignUpView → ConfirmEmailView
  - Main app: ContentView (tab container) → TransactView, ActivityView, BalanceView
- **Components/Theme.swift**: Centralized UI theming and styling

## Key Dependencies

- **Cashu/Bitcoin**: `cdk-swift` (Cashu Development Kit)
- **AWS Services**: Amplify Swift SDK for Cognito authentication

## Development Notes

### Wallet Integration
- Mnemonic stored securely in iOS Keychain
- Connects to Cashu mints
- Supports Lightning invoice generation for funding

### Authentication Flow
1. User signs up with email via AWS Cognito
2. Email verification required
3. Authenticated state managed by AuthManager
4. Token refresh handled automatically

### Common Issues and Solutions

**Package Resolution**: If dependencies fail to resolve:
```bash
just clean
just update-deps
just build
```

## Project Configuration

- **Bundle ID**: app.paywithsats
- **Minimum iOS**: 16.0 (deployment target)
- **Swift Version**: 5.0
- **Xcode Project**: SatsApp.xcodeproj

