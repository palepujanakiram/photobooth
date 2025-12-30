# CORS Error Solution Guide

## Problem
The web app is getting CORS (Cross-Origin Resource Sharing) errors when trying to connect to `https://zenai-labs.replit.app` from `localhost`. This is a browser security feature that blocks cross-origin requests unless the server explicitly allows them.

## Solutions

### Option 1: Server-Side Fix (Recommended for Production)
The server at `https://zenai-labs.replit.app` needs to add CORS headers to allow requests from your web app.

**Required Headers:**
```
Access-Control-Allow-Origin: http://localhost:63939
Access-Control-Allow-Methods: GET, POST, PATCH, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
Access-Control-Allow-Credentials: true
```

**For Development (Allow all origins):**
```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, PATCH, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
```

**Contact:** The server administrator needs to configure these headers on the API server.

---

### Option 2: Development Workaround - CORS Proxy

For local development, you can use a CORS proxy service. Update `lib/utils/app_config.dart` to use a proxy:

```dart
class AppConfig {
  // For development with CORS proxy
  static const String baseUrl = 'https://cors-anywhere.herokuapp.com/https://zenai-labs.replit.app';
  
  // Or use a local proxy server
  // static const String baseUrl = 'http://localhost:8080/api';
}
```

**Note:** Public CORS proxy services may have rate limits. For production, always use Option 1.

---

### Option 3: Development Workaround - Chrome with CORS Disabled

**⚠️ WARNING: Only for development, never use in production!**

Run Chrome with CORS disabled:

```bash
# macOS
open -na Google\ Chrome --args --user-data-dir=/tmp/chrome_dev --disable-web-security --disable-features=VizDisplayCompositor

# Linux
google-chrome --user-data-dir=/tmp/chrome_dev --disable-web-security --disable-features=VizDisplayCompositor

# Windows
chrome.exe --user-data-dir="C:/tmp/chrome_dev" --disable-web-security --disable-features=VizDisplayCompositor
```

Then run your Flutter app:
```bash
flutter run -d chrome
```

---

### Option 4: Local Proxy Server

Set up a local proxy server that adds CORS headers:

1. Install a proxy server (e.g., `http-proxy-middleware` with Node.js)
2. Configure it to forward requests to `https://zenai-labs.replit.app` and add CORS headers
3. Update `AppConfig.baseUrl` to point to your local proxy (e.g., `http://localhost:8080`)

---

## Recommended Approach

1. **For Development:** Use Option 3 (Chrome with CORS disabled) or Option 4 (local proxy)
2. **For Production:** Use Option 1 (server-side CORS configuration)

---

## Testing

After implementing any solution, test by:
1. Running the web app: `flutter run -d chrome`
2. Checking the browser console for CORS errors
3. Verifying API calls succeed

---

## Additional Resources

- [MDN: CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS)
- [Flutter Web CORS Issues](https://docs.flutter.dev/development/platform-integration/web)

