#!/usr/bin/env just --justfile

# Configuration
project := "SatsApp.xcodeproj"
scheme := "SatsApp"
bundle_id := "app.paywithsats"
build_dir := ".build"
derived_data := "~/Library/Developer/Xcode/DerivedData/SatsApp-*"

# Build settings
arch := "arm64"
configuration := "Debug"

# Default recipe to display help information
default:
    @just --list

# Clean build artifacts
clean:
    xcodebuild -project {{project}} -scheme {{scheme}} clean
    rm -rf {{derived_data}}
    rm -rf {{build_dir}}

# Build the app for simulator
build:
    #!/bin/bash
    set -euo pipefail
    
    # Get or boot a simulator
    BOOTED=$(xcrun simctl list devices | grep -E "Booted" | head -n 1 | grep -oE '[A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{12}' || true)
    
    if [ -n "$BOOTED" ]; then
        SIMULATOR_ID="$BOOTED"
    else
        # Get any iPhone simulator
        SIMULATOR_ID=$(xcrun simctl list devices | grep -E "iPhone.*(17\.[4-5]|18\.)" | head -n 1 | grep -oE '[A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{12}' || true)
        
        if [ -z "$SIMULATOR_ID" ]; then
            echo "Error: No suitable iPhone simulator found"
            exit 1
        fi
    fi
    
    echo "Building for simulator: $SIMULATOR_ID"
    xcodebuild -project {{project}} -scheme {{scheme}} \
        -destination "platform=iOS Simulator,arch={{arch}},id=$SIMULATOR_ID" \
        -configuration {{configuration}} \
        -derivedDataPath {{build_dir}} \
        build

# Run the app (build, install, launch, and stream logs)
run:
    #!/bin/bash
    set -euo pipefail
    
    # Get or boot a simulator
    BOOTED=$(xcrun simctl list devices | grep -E "Booted" | head -n 1 | grep -oE '[A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{12}' || true)
    
    if [ -n "$BOOTED" ]; then
        SIMULATOR_ID="$BOOTED"
        echo "Using booted simulator: $SIMULATOR_ID"
    else
        # Get any iPhone simulator
        IPHONE=$(xcrun simctl list devices | grep -E "iPhone.*(17\.[4-5]|18\.)" | head -n 1 | grep -oE '[A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{12}' || true)
        
        if [ -z "$IPHONE" ]; then
            echo "Error: No suitable iPhone simulator found"
            exit 1
        fi
        
        echo "Booting simulator: $IPHONE"
        open -a Simulator
        xcrun simctl boot "$IPHONE" 2>/dev/null || true
        
        # Wait for boot
        for i in {1..10}; do
            if xcrun simctl list devices | grep -q "$IPHONE.*Booted"; then
                break
            fi
            sleep 1
        done
        
        SIMULATOR_ID="$IPHONE"
    fi
    
    # Build
    echo "Building..."
    xcodebuild -project {{project}} -scheme {{scheme}} \
        -destination "platform=iOS Simulator,arch={{arch}},id=$SIMULATOR_ID" \
        -configuration {{configuration}} \
        -derivedDataPath {{build_dir}} \
        -allowProvisioningUpdates \
        build > /dev/null
    
    if [ $? -ne 0 ]; then
        echo "Error: Build failed!"
        exit 1
    fi
    echo "Build succeeded"
    
    # Install
    echo "Installing app..."
    xcrun simctl install "$SIMULATOR_ID" {{build_dir}}/Build/Products/{{configuration}}-iphonesimulator/{{scheme}}.app
    
    if [ $? -ne 0 ]; then
        echo "Error: Installation failed!"
        exit 1
    fi
    echo "App installed"
    
    # Launch
    echo "Launching app..."
    xcrun simctl launch "$SIMULATOR_ID" {{bundle_id}}
    echo "App launched"
    
    # Stream logs
    echo "Streaming logs for {{bundle_id}}..."
    echo "Press Ctrl+C to stop"
    echo "----------------------------------------"
    
    /usr/bin/log stream --level debug --predicate 'subsystem == "{{bundle_id}}"' --style compact

# Run on specific simulator by name
run-on device: 
    #!/bin/bash
    set -euo pipefail
    SIMULATOR_ID=$(xcrun simctl list devices | grep "{{device}}" | head -n 1 | grep -oE '[A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{12}' || true)
    
    if [ -z "$SIMULATOR_ID" ]; then
        echo "Error: Device '{{device}}' not found"
        exit 1
    fi
    
    # Boot device if needed
    xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
    open -a Simulator
    echo "Using simulator: $SIMULATOR_ID"
    
    # Build
    echo "Building..."
    xcodebuild -project {{project}} -scheme {{scheme}} \
        -destination "platform=iOS Simulator,arch={{arch}},id=$SIMULATOR_ID" \
        -configuration {{configuration}} \
        -derivedDataPath {{build_dir}} \
        build > /dev/null || { echo "Error: Build failed!"; exit 1; }
    
    # Install and launch
    echo "Installing and launching..."
    xcrun simctl install "$SIMULATOR_ID" {{build_dir}}/Build/Products/{{configuration}}-iphonesimulator/{{scheme}}.app || { echo "Error: Install failed!"; exit 1; }
    xcrun simctl launch "$SIMULATOR_ID" {{bundle_id}}
    echo "App launched on {{device}}"

# Stream app logs in real-time
logs:
    /usr/bin/log stream --level debug --predicate 'subsystem == "{{bundle_id}}"' --style compact

# Quick rebuild and run (skips some checks for faster iteration)
quick:
    #!/bin/bash
    set -euo pipefail
    echo "Quick build and run..."
    
    # Get booted simulator
    SIMULATOR_ID=$(xcrun simctl list devices | grep -E "Booted" | head -n 1 | grep -oE '[A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{12}' || true)
    
    if [ -z "$SIMULATOR_ID" ]; then
        echo "Error: No booted simulator found. Run 'just run' first."
        exit 1
    fi
    
    echo "Using simulator: $SIMULATOR_ID"
    
    # Quick build with minimal output
    xcodebuild -project {{project}} -scheme {{scheme}} \
        -destination "platform=iOS Simulator,arch={{arch}},id=$SIMULATOR_ID" \
        -configuration {{configuration}} \
        -derivedDataPath {{build_dir}} \
        build | grep -E "^(=== BUILD|\\*\\* BUILD|\\.\\.\\.)" || true
    
    # Install and launch
    xcrun simctl install "$SIMULATOR_ID" {{build_dir}}/Build/Products/{{configuration}}-iphonesimulator/{{scheme}}.app
    xcrun simctl launch "$SIMULATOR_ID" {{bundle_id}}
    echo "Quick launch complete"

# Run tests
test:
    #!/bin/bash
    set -euo pipefail
    
    # Get or boot a simulator
    SIMULATOR_ID=$(xcrun simctl list devices | grep -E "Booted" | head -n 1 | grep -oE '[A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{12}' || \
        xcrun simctl list devices | grep -E "iPhone.*(17\.[4-5]|18\.)" | head -n 1 | grep -oE '[A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{12}')
        
    if [ -z "$SIMULATOR_ID" ]; then
        echo "Error: No suitable simulator found"
        exit 1
    fi
    
    echo "Running tests on simulator: $SIMULATOR_ID"
    xcodebuild -project {{project}} -scheme {{scheme}} \
        -destination "platform=iOS Simulator,arch={{arch}},id=$SIMULATOR_ID" \
        test

# Open the project in Xcode
open:
    open {{project}}

# Show available simulators
simulators:
    xcrun simctl list devices available

# Show build settings
settings:
    xcodebuild -project {{project}} -scheme {{scheme}} -showBuildSettings

# Install dependencies
deps:
    xcodebuild -resolvePackageDependencies -project {{project}}

# Update dependencies
update-deps:
    rm -f {{project}}/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
    rm -rf ~/Library/Caches/org.swift.swiftpm
    rm -rf {{derived_data}}
    xcodebuild -resolvePackageDependencies -project {{project}}
    @echo "Dependencies updated"

# Show current dependencies
show-deps:
    @if [ -f "{{project}}/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" ]; then \
        cat {{project}}/project.xcworkspace/xcshareddata/swiftpm/Package.resolved | \
        grep -E "(identity|revision)" | sed 's/^[[:space:]]*//' | sed 's/[",]//g'; \
    else \
        echo "No Package.resolved file found. Run 'just deps' first."; \
    fi

# Archive for release
archive:
    xcodebuild -project {{project}} -scheme {{scheme}} \
        -archivePath ./build/{{scheme}}.xcarchive \
        -destination 'generic/platform=iOS' \
        archive

# Reset everything (clean + remove derived data + reset simulators)
reset: clean
    xcrun simctl shutdown all
    xcrun simctl erase all
    @echo "Reset complete"
