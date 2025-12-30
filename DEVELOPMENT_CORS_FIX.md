# Quick CORS Fix for Development

## The Problem
Your web app running on `localhost:63939` cannot make requests to `https://zenai-labs.replit.app` due to CORS restrictions.

## Quick Fix: Run Chrome with CORS Disabled

**⚠️ IMPORTANT: This is ONLY for development. Never use this in production!**

### macOS
```bash
# Close all Chrome windows first, then run:
open -na Google\ Chrome --args --user-data-dir=/tmp/chrome_dev_session --disable-web-security --disable-features=VizDisplayCompositor

# In another terminal, run your Flutter app:
flutter run -d chrome
```

### Alternative: Use a CORS Proxy

1. Update `lib/utils/app_config.dart`:
```dart
static const String baseUrl = 'https://cors-anywhere.herokuapp.com/https://zenai-labs.replit.app';
```

2. Run your app:
```bash
flutter run -d chrome
```

**Note:** Public CORS proxies may have rate limits. For production, the server must be configured with proper CORS headers.

## Permanent Solution

The server at `https://zenai-labs.replit.app` needs to add CORS headers. Contact the server administrator to add:

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, PATCH, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
```

See `CORS_SOLUTION.md` for more details.

