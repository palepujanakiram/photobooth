#!/bin/bash
# Quick iOS Setup Script

echo "🍎 iOS Setup for iPad Development"
echo "=================================="
echo ""

# Check if CocoaPods is installed
if ! command -v pod &> /dev/null; then
    echo "1️⃣  Installing CocoaPods..."
    echo "   This may take a few minutes..."
    sudo gem install cocoapods
    echo "   ✅ CocoaPods installed"
else
    echo "1️⃣  CocoaPods already installed ✅"
    pod --version
fi

echo ""
echo "2️⃣  Installing iOS dependencies..."
cd ios || exit
pod install
echo "   ✅ Dependencies installed"
echo ""

echo "3️⃣  Opening Xcode workspace..."
open Runner.xcworkspace
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
echo "   flutter run -d 'Janakiram's iPad'"
echo ""

