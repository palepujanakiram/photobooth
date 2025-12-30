#!/bin/bash
# Complete CORS fix script for Flutter web development

echo "🔧 CORS Fix Script"
echo "=================="
echo ""

# Step 1: Kill all Chrome instances
echo "1️⃣  Closing all Chrome instances..."
pkill -9 -f "Google Chrome" 2>/dev/null || true
pkill -9 -f "Chrome" 2>/dev/null || true
sleep 3
echo "   ✅ Chrome closed"
echo ""

# Step 2: Create a unique user data directory
CHROME_DATA_DIR="/tmp/chrome_cors_dev_$(date +%s)"
echo "2️⃣  Creating Chrome profile: $CHROME_DATA_DIR"
mkdir -p "$CHROME_DATA_DIR"
echo "   ✅ Profile created"
echo ""

# Step 3: Launch Chrome with CORS disabled
echo "3️⃣  Launching Chrome with CORS disabled..."
echo "   ⚠️  You'll see a warning - that's normal!"
echo ""

open -na "Google Chrome" --args \
  --user-data-dir="$CHROME_DATA_DIR" \
  --disable-web-security \
  --disable-features=VizDisplayCompositor \
  --disable-site-isolation-trials \
  --disable-blink-features=AutomationControlled \
  --remote-debugging-port=9222

sleep 5

echo "   ✅ Chrome launched with CORS disabled"
echo ""

# Step 4: Instructions
echo "4️⃣  Next Steps:"
echo "   ============="
echo ""
echo "   In a NEW terminal window, run:"
echo "   flutter run -d chrome"
echo ""
echo "   ⚠️  IMPORTANT:"
echo "   - Keep this Chrome window open"
echo "   - Use THIS Chrome instance for Flutter"
echo "   - Don't open regular Chrome windows"
echo ""
echo "   To verify CORS is disabled, check:"
echo "   chrome://version/"
echo "   You should see '--disable-web-security' in the command line"
echo ""
echo "✅ Setup complete! Now run 'flutter run -d chrome' in another terminal."

