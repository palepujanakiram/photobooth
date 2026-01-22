#!/bin/bash

# Crashlytics Installation Script
# This script installs Firebase Crashlytics dependencies

echo "🚀 Installing Firebase Crashlytics..."
echo ""

# Step 1: Flutter pub get
echo "📦 Step 1/3: Installing Flutter dependencies..."
flutter pub get

if [ $? -ne 0 ]; then
    echo "❌ Error: flutter pub get failed"
    exit 1
fi

echo "✅ Flutter dependencies installed"
echo ""

# Step 2: iOS CocoaPods (if on macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "🍎 Step 2/3: Installing iOS CocoaPods..."
    cd ios
    pod install
    if [ $? -ne 0 ]; then
        echo "⚠️  Warning: pod install failed. You may need to run it manually."
        echo "   Run: cd ios && pod install"
    else
        echo "✅ iOS CocoaPods installed"
    fi
    cd ..
    echo ""
else
    echo "⏭️  Step 2/3: Skipped (iOS pods only needed on macOS)"
    echo ""
fi

# Step 3: Clean build
echo "🧹 Step 3/3: Cleaning previous build..."
flutter clean

if [ $? -ne 0 ]; then
    echo "⚠️  Warning: flutter clean failed"
else
    echo "✅ Build cleaned"
fi

echo ""
echo "========================================="
echo "✅ Firebase Crashlytics installation complete!"
echo "========================================="
echo ""
echo "📝 Next steps:"
echo "   1. Run: flutter run"
echo "   2. Test: See CRASHLYTICS_QUICK_START.md"
echo "   3. Monitor: https://console.firebase.google.com/"
echo ""
echo "📚 Documentation:"
echo "   - Quick Start: CRASHLYTICS_QUICK_START.md"
echo "   - Full Guide: CRASHLYTICS_SETUP.md"
echo "   - Summary: CRASHLYTICS_SUMMARY.md"
echo ""
