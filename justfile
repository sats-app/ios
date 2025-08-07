#!/usr/bin/env just --justfile

# Default recipe to display help information
default:
    @just --list

# Build the app for simulator
build:
    xcodebuild -scheme SatsApp \
        -destination 'platform=iOS Simulator,OS=latest' \
        build

# Build the app for device
build-device:
    xcodebuild -scheme SatsApp \
        -destination 'generic/platform=iOS' \
        build

# Clean build artifacts
clean:
    xcodebuild -scheme SatsApp clean
    rm -rf ~/Library/Developer/Xcode/DerivedData/SatsApp-*

# Run tests
test:
    xcodebuild -scheme SatsApp \
        -destination 'platform=iOS Simulator,OS=latest' \
        test

# Run the app in currently open simulator (or boot default if none open)
run:
    #!/bin/bash
    # Get the first booted simulator, or boot the default one
    BOOTED_DEVICE=$(xcrun simctl list devices | grep -E "Booted" | head -n 1 | grep -oE '[A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{12}')
    
    if [ -z "$BOOTED_DEVICE" ]; then
        echo "No simulator booted. Starting default simulator..."
        open -a Simulator
        # Wait for simulator to boot
        sleep 3
        BOOTED_DEVICE=$(xcrun simctl list devices | grep -E "Booted" | head -n 1 | grep -oE '[A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{12}')
    fi
    
    if [ -z "$BOOTED_DEVICE" ]; then
        echo "Failed to detect booted simulator"
        exit 1
    fi
    
    echo "Using simulator: $BOOTED_DEVICE"
    
    xcodebuild -scheme SatsApp \
        -destination "platform=iOS Simulator,id=$BOOTED_DEVICE" \
        -configuration Debug \
        -derivedDataPath .build \
        -allowProvisioningUpdates \
        build
    
    xcrun simctl install "$BOOTED_DEVICE" .build/Build/Products/Debug-iphonesimulator/SatsApp.app
    xcrun simctl launch "$BOOTED_DEVICE" app.paywithsats

# Open the project in Xcode
open:
    open SatsApp.xcodeproj

# Format Swift code
format:
    swift-format -i -r SatsApp/

# Lint Swift code
lint:
    swiftlint --strict

# Show available simulators
simulators:
    xcrun simctl list devices

# Archive for release
archive:
    xcodebuild -scheme SatsApp \
        -archivePath ./build/SatsApp.xcarchive \
        -destination 'generic/platform=iOS' \
        archive

# Export IPA from archive
export-ipa: archive
    xcodebuild -exportArchive \
        -archivePath ./build/SatsApp.xcarchive \
        -exportPath ./build \
        -exportOptionsPlist ExportOptions.plist

# Install dependencies
deps:
    xcodebuild -resolvePackageDependencies

# Update all dependencies to latest versions
update-deps:
    #!/bin/bash
    echo "Updating Swift package dependencies..."
    
    # Remove the Package.resolved file to force fetching latest versions
    rm -f SatsApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
    
    # Clear the SPM cache to ensure we get the latest version
    rm -rf ~/Library/Caches/org.swift.swiftpm
    rm -rf ~/Library/Developer/Xcode/DerivedData/SatsApp-*
    
    # Resolve dependencies fresh - this will fetch the latest commit from the branch
    xcodebuild -resolvePackageDependencies -project SatsApp.xcodeproj
    
    echo ""
    echo "Dependencies updated successfully!"
    echo ""
    echo "Updated packages:"
    just show-deps

# Show current dependency versions
show-deps:
    #!/bin/bash
    echo "Current Swift package dependencies:"
    if [ -f "SatsApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" ]; then
        cat SatsApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved | grep -E "(identity|revision)" | sed 's/^[[:space:]]*//'
    else
        echo "No Package.resolved file found. Run 'just deps' first."
    fi

# Run on specific simulator by name
run-on device:
    #!/bin/bash
    # Try to find the device by name and get its ID
    DEVICE_ID=$(xcrun simctl list devices | grep "{{device}}" | head -n 1 | grep -oE '[A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{12}')
    
    if [ -z "$DEVICE_ID" ]; then
        echo "Device '{{device}}' not found"
        exit 1
    fi
    
    # Boot the device if not already booted
    xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
    open -a Simulator
    
    xcodebuild -scheme SatsApp \
        -destination "platform=iOS Simulator,id=$DEVICE_ID" \
        -configuration Debug \
        -derivedDataPath .build \
        build
    
    xcrun simctl install "$DEVICE_ID" .build/Build/Products/Debug-iphonesimulator/SatsApp.app
    xcrun simctl launch "$DEVICE_ID" app.paywithsats

# Check Swift package dependencies
check-deps:
    swift package show-dependencies

# Generate Xcode project from Package.swift (if using SPM)
generate:
    swift package generate-xcodeproj

# Run UI tests
ui-test:
    xcodebuild -scheme SatsApp \
        -destination 'platform=iOS Simulator,OS=latest' \
        -only-testing:SatsAppUITests \
        test

# Run unit tests only
unit-test:
    xcodebuild -scheme SatsApp \
        -destination 'platform=iOS Simulator,OS=latest' \
        -only-testing:SatsAppTests \
        test

# Build for all platforms (iOS and iPadOS)
build-all:
    xcodebuild -scheme SatsApp -destination 'platform=iOS Simulator,OS=latest,name=iPhone 15 Pro' build
    xcodebuild -scheme SatsApp -destination 'platform=iOS Simulator,OS=latest,name=iPad Pro 11-inch (M4)' build

# Show build settings
settings:
    xcodebuild -scheme SatsApp -showBuildSettings

# Analyze code for potential issues
analyze:
    xcodebuild -scheme SatsApp \
        -destination 'platform=iOS Simulator,OS=latest' \
        analyze