#!/bin/bash

# Setup script to include UVCCamera library manually
# This is needed because JitPack cannot build the UVCCamera library

echo "🔧 Setting up UVCCamera library..."

# Navigate to android/app directory
cd android/app || exit 1

# Create libs directory if it doesn't exist
mkdir -p libs

# Clone UVCCamera repository
if [ ! -d "libs/UVCCamera" ]; then
    echo "📥 Cloning UVCCamera repository..."
    git clone https://github.com/saki4510t/UVCCamera.git libs/UVCCamera
else
    echo "✅ UVCCamera already cloned"
fi

# Check if settings.gradle needs to be updated
if ! grep -q "include ':app:libs:UVCCamera:libuvccamera'" ../settings.gradle 2>/dev/null; then
    echo "📝 Updating settings.gradle..."
    echo "include ':app:libs:UVCCamera:libuvccamera'" >> ../settings.gradle
else
    echo "✅ settings.gradle already updated"
fi

# Check if build.gradle needs to be updated
if ! grep -q "implementation project(':app:libs:UVCCamera:libuvccamera')" build.gradle; then
    echo "⚠️  Please uncomment the UVCCamera dependency in android/app/build.gradle:"
    echo "   implementation project(':app:libs:UVCCamera:libuvccamera')"
else
    echo "✅ build.gradle already configured"
fi

echo ""
echo "✅ Setup complete!"
echo "📋 Next steps:"
echo "   1. Uncomment the UVCCamera dependency in android/app/build.gradle"
echo "   2. Sync Gradle"
echo "   3. Build the app"
