# Quick CORS Fix - Choose One Option

## ✅ Option 1: CORS Proxy (Already Applied)
I've updated `lib/utils/app_config.dart` to use a CORS proxy. 

**Try running:**
```bash
flutter run -d chrome
```

**If you get errors about the proxy**, the proxy service might need activation. Use Option 2 instead.

---

## ✅ Option 2: Chrome with CORS Disabled (Most Reliable)

**Step 1:** Close ALL Chrome windows completely

**Step 2:** Run this command in Terminal:
```bash
./run_chrome_dev.sh
```

**Or manually:**
```bash
open -na Google\ Chrome --args --user-data-dir=/tmp/chrome_dev_session --disable-web-security --disable-features=VizDisplayCompositor
```

**Step 3:** In a NEW terminal window, run:
```bash
flutter run -d chrome
```

**Important:** 
- Keep the Chrome window that opened with CORS disabled
- Use that Chrome instance to run your Flutter app
- Don't close that Chrome window until you're done testing

---

## Option 3: Revert to Original URL + Use Chrome Workaround

If you want to use the original API URL:

1. Update `lib/utils/app_config.dart`:
```dart
static const String baseUrl = 'https://zenai-labs.replit.app';
```

2. Then use Option 2 (Chrome with CORS disabled)

---

## Which Option to Use?

- **Option 1 (CORS Proxy)**: Easiest, but proxy might have limits
- **Option 2 (Chrome CORS Disabled)**: Most reliable for development
- **For Production**: Server must add CORS headers (contact server admin)

---

## Still Having Issues?

1. Make sure Chrome is completely closed before running the script
2. Check that you're using the Chrome instance that opened with CORS disabled
3. Try restarting your terminal and running the commands again

