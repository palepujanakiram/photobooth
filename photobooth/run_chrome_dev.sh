#!/bin/bash
# Script to run Chrome with CORS disabled for Flutter web development
# WARNING: Only use for development, never for production!

echo "🚀 Starting Chrome with CORS disabled..."
echo "⚠️  WARNING: This disables web security. Only use for development!"
echo ""

# Kill any existing Chrome instances to avoid conflicts
echo "Closing existing Chrome instances..."
pkill -f "Google Chrome" 2>/dev/null || true
sleep 2

# Start Chrome with CORS disabled
echo "Launching Chrome with CORS disabled..."
open -na Google\ Chrome --args \
  --user-data-dir=/tmp/chrome_dev_session \
  --disable-web-security \
  --disable-features=VizDisplayCompositor \
  --disable-site-isolation-trials \
  --disable-blink-features=AutomationControlled

echo ""
echo "✅ Chrome started with CORS disabled!"
echo ""
echo "📋 Next steps:"
echo "   1. Wait for Chrome to fully open"
echo "   2. In a NEW terminal, run: flutter run -d chrome"
echo "   3. Keep this Chrome window open while testing"
echo ""
echo "⚠️  Remember: This Chrome instance has security disabled!"
echo "   Close it when you're done testing."
