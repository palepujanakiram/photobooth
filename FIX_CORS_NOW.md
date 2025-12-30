# Fix CORS Error - Step by Step

## The Problem
Your web app can't connect to the API because of CORS restrictions. This is a browser security feature.

## ✅ Solution: Run Chrome with CORS Disabled

**Follow these steps EXACTLY:**

### Step 1: Close ALL Chrome Windows
- Close every Chrome window completely
- Make sure Chrome is not running in the background

### Step 2: Run the Script
```bash
./run_chrome_dev.sh
```

This will:
- Close any remaining Chrome instances
- Open a new Chrome window with CORS disabled
- Show you confirmation messages

### Step 3: Wait for Chrome to Open
- Wait 5-10 seconds for Chrome to fully launch
- You should see a warning about "You are using an unsupported command-line flag"
- **This is normal and expected!**

### Step 4: Run Your Flutter App
In a **NEW terminal window**, run:
```bash
flutter run -d chrome
```

### Step 5: Test Your App
- Your app should now work without CORS errors
- Keep the Chrome window (with CORS disabled) open while testing

---

## ⚠️ Important Notes

1. **Keep the CORS-disabled Chrome window open** - Don't close it while testing
2. **Only use this for development** - Never use in production
3. **Close the CORS-disabled Chrome when done** - For security

---

## If It Still Doesn't Work

1. **Make sure Chrome is completely closed** before running the script
2. **Check that you're using the Chrome window that opened** (not a regular Chrome window)
3. **Try manually:**
   ```bash
   # Close Chrome completely first
   pkill -f "Google Chrome"
   
   # Wait 2 seconds
   sleep 2
   
   # Open Chrome with CORS disabled
   open -na Google\ Chrome --args --user-data-dir=/tmp/chrome_dev_session --disable-web-security --disable-features=VizDisplayCompositor
   
   # Then run Flutter
   flutter run -d chrome
   ```

---

## Alternative: Contact Server Admin

The **permanent solution** is to have the server administrator add CORS headers:

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, PATCH, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
```

But for now, the Chrome workaround will let you develop and test your app.

