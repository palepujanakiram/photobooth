#!/bin/bash
# Complete solution: Kill Chrome, start with CORS disabled, then run Flutter

set -e  # Exit on error

echo "🚀 Complete CORS Fix for Flutter Web"
echo "====================================="
echo ""

# Step 1: Kill ALL Chrome processes
echo "1️⃣  Killing all Chrome processes..."
pkill -9 -f "Google Chrome" 2>/dev/null || true
pkill -9 -f "Chrome" 2>/dev/null || true
sleep 3
echo "   ✅ All Chrome processes killed"
echo ""

# Step 2: Create unique Chrome profile
CHROME_PROFILE="/tmp/chrome_flutter_dev_$$"
echo "2️⃣  Creating Chrome profile: $CHROME_PROFILE"
mkdir -p "$CHROME_PROFILE"
echo "   ✅ Profile created"
echo ""

# Step 3: Launch Chrome with CORS disabled
echo "3️⃣  Launching Chrome with CORS disabled..."
echo "   ⚠️  You'll see a security warning - that's EXPECTED!"
echo ""

/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --user-data-dir="$CHROME_PROFILE" \
  --disable-web-security \
  --disable-features=VizDisplayCompositor \
  --disable-site-isolation-trials \
  --disable-blink-features=AutomationControlled \
  --remote-debugging-port=9222 \
  > /dev/null 2>&1 &

CHROME_PID=$!
echo "   Chrome PID: $CHROME_PID"
sleep 5
echo "   ✅ Chrome launched"
echo ""

# Step 4: Verify Chrome is running
if ps -p $CHROME_PID > /dev/null; then
  echo "4️⃣  Chrome is running with CORS disabled"
  echo ""
  echo "5️⃣  Starting Flutter app..."
  echo ""
  
  # Run Flutter
  flutter run -d chrome
  
else
  echo "❌ Error: Chrome failed to start" >&2
  echo "   Try running manually:" >&2
  echo "   /Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome --user-data-dir=/tmp/chrome_dev --disable-web-security"
  exit 1
fi

