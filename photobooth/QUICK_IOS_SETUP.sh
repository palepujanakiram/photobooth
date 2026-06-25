#!/bin/bash
# Quick iOS Setup Script (Swift Package Manager + CocoaPods fallback)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🍎 iOS Setup for iPad Development"
echo "=================================="
echo ""
echo "This project uses Swift Package Manager (SPM) by default."
echo "CocoaPods is still used as a fallback for plugins without SPM support."
echo ""

echo "1️⃣  Resolving Flutter dependencies..."
flutter pub get
echo "   ✅ Flutter dependencies ready"
echo ""

echo "2️⃣  Configuring iOS build (SPM + CocoaPods fallback)..."
flutter build ios --config-only --no-codesign
echo "   ✅ iOS project configured"
echo ""

echo "3️⃣  Checking CocoaPods (required for fallback plugins)..."
if ! command -v pod &> /dev/null; then
    echo "   CocoaPods not found. Installing..."
    echo "   This may take a few minutes..."
    sudo gem install cocoapods
    echo "   ✅ CocoaPods installed"
else
    echo "   CocoaPods already installed ✅"
    pod --version
fi
echo ""

echo "4️⃣  Opening Xcode workspace..."
open ios/Runner.xcworkspace
echo "   ✅ Xcode opened"
echo ""

echo "📋 Next Steps in Xcode:"
echo "   1. Select 'Runner' in the left sidebar"
echo "   2. Click on 'Runner' under TARGETS"
echo "   3. Go to 'Signing & Capabilities' tab"
echo "   4. Check 'Automatically manage signing'"
echo "   5. Select your Apple Developer Team"
echo "   6. Connect your iPad and select it from device dropdown"
echo "   7. Click Play button to build and run"
echo ""
echo "Or run from terminal:"
echo "   flutter run -d <device-id>"
echo ""
echo "ℹ️  Plugins still on CocoaPods fallback:"
echo "   bugsnag_flutter, device_info_plus, flutter_secure_storage,"
echo "   flutter_zxing, permission_handler_apple, printing"
echo ""
echo "   Flutter runs 'pod install' automatically when needed."
echo "   After a Flutter SDK upgrade, run 'flutter clean' if you see"
echo "   precompiled-module errors."
echo ""
