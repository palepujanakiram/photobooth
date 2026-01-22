# Bugsnag Network Request Breadcrumbs

## ✅ Implemented

Automatic network request tracking for Bugsnag has been successfully implemented using a custom Dio interceptor.

## 🎯 What Was Done

### **Created Custom Bugsnag Dio Interceptor**

**File**: `lib/services/bugsnag_dio_interceptor.dart`

This interceptor automatically captures:
- ✅ **All HTTP requests** (method, URL, path)
- ✅ **All successful responses** (status code, status message)
- ✅ **All HTTP errors** (error type, status code, error message)

### **How It Works**

```dart
class BugsnagDioInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Automatically leave breadcrumb for every request
    bugsnag.leaveBreadcrumb(
      'HTTP Request: ${options.method} ${options.uri.path}',
      metadata: {
        'type': 'request',
        'method': options.method,
        'url': options.uri.toString(),
        'path': options.uri.path,
      },
      type: BugsnagBreadcrumbType.navigation,
    );
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // Automatically leave breadcrumb for successful responses
    bugsnag.leaveBreadcrumb(
      'HTTP Response: ${method} ${path} - ${statusCode}',
      metadata: { ... },
      type: BugsnagBreadcrumbType.navigation,
    );
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Automatically leave breadcrumb for errors
    bugsnag.leaveBreadcrumb(
      'HTTP Error: ${method} ${path} - ${error_type}',
      metadata: { ... },
      type: BugsnagBreadcrumbType.error,
    );
  }
}
```

### **Integrated Everywhere**

The interceptor is added to **all Dio instances** in the app:

**1. Main API Client** (`api_service.dart`):
```dart
final dio = Dio(BaseOptions(...));
dio.interceptors.add(BugsnagDioInterceptor());  // ✅ Added
dio.interceptors.add(ApiLoggingInterceptor());
```

**2. Image Generation API** (long timeout):
```dart
final dioWithTimeout = Dio(BaseOptions(...));
dioWithTimeout.interceptors.add(BugsnagDioInterceptor());  // ✅ Added
dioWithTimeout.interceptors.add(ApiLoggingInterceptor());
```

**3. Printer API** (`print_service.dart`):
```dart
final dio = Dio(BaseOptions(...));
dio.interceptors.add(BugsnagDioInterceptor());  // ✅ Added
dio.interceptors.add(ApiLoggingInterceptor());
```

**4. Image Download** (for printer):
```dart
final downloadDio = Dio(BaseOptions(...));
downloadDio.interceptors.add(BugsnagDioInterceptor());  // ✅ Added
downloadDio.interceptors.add(ApiLoggingInterceptor());
```

---

## 📊 Bugsnag Dashboard - Breadcrumb Examples

### **Example 1: Successful Photo Upload**

```
Breadcrumbs (in chronological order):

1. HTTP Request: POST /api/sessions
2. HTTP Response: POST /api/sessions - 200
3. User selected camera: external_123
4. 📸 Photo capture started
5. ✅ Photo captured successfully
6. HTTP Request: POST /api/photos
7. HTTP Response: POST /api/photos - 200
8. Theme selection completed
```

**Metadata for each breadcrumb**:
```json
{
  "type": "request",
  "method": "POST",
  "url": "https://api.example.com/api/sessions",
  "path": "/api/sessions"
}
```

---

### **Example 2: API Error Flow**

```
Breadcrumbs:

1. HTTP Request: POST /api/sessions
2. HTTP Response: POST /api/sessions - 200
3. User selected theme: theme_001
4. HTTP Request: POST /api/photos
5. HTTP Error: POST /api/photos - connectionTimeout
   ↑
   ERROR OCCURRED HERE

Then error report contains:
- All breadcrumbs above
- Full error details
- Request/response data
```

**Error breadcrumb metadata**:
```json
{
  "type": "error",
  "method": "POST",
  "url": "https://api.example.com/api/photos",
  "error_type": "connectionTimeout",
  "error_message": "Connection timeout [30000ms]",
  "status_code": "none"
}
```

---

### **Example 3: Print to Network Printer**

```
Breadcrumbs:

1. User selected photo for print
2. HTTP Request: POST /api/PrintImage
3. HTTP Error: POST /api/PrintImage - connectionError
   ↑
   PRINT FAILED

Metadata:
{
  "type": "error",
  "method": "POST",
  "url": "http://192.168.1.100/api/PrintImage",
  "error_type": "connectionError",
  "status_code": "none"
}
```

---

## 🎨 Breadcrumb Types

The interceptor uses appropriate Bugsnag breadcrumb types:

| Event | Breadcrumb Type | Icon in Dashboard |
|-------|----------------|-------------------|
| HTTP Request | `navigation` | 🔗 |
| HTTP Response | `navigation` | 🔗 |
| HTTP Error | `error` | ❌ |

---

## 📈 Benefits

### **Before (Manual Logging)**:
```dart
// Had to manually log each API call
ErrorReportingManager.log('API Request: POST /api/photos');
```

**Issues**:
- ❌ Easy to forget logging
- ❌ Inconsistent format
- ❌ Extra code maintenance

### **After (Automatic Breadcrumbs)**:
```dart
// Nothing needed - automatically tracked!
await apiClient.uploadPhoto(...);
```

**Benefits**:
- ✅ **Automatic** - No manual logging needed
- ✅ **Consistent** - Same format everywhere
- ✅ **Complete** - Captures all requests automatically
- ✅ **Less Code** - No manual breadcrumb calls needed

---

## 🔍 What Gets Captured

### **For Every Request:**
```
Breadcrumb: "HTTP Request: POST /api/photos"
Metadata:
  - type: request
  - method: POST
  - url: https://api.example.com/api/photos
  - path: /api/photos
```

### **For Every Response:**
```
Breadcrumb: "HTTP Response: POST /api/photos - 200"
Metadata:
  - type: response
  - method: POST
  - url: https://api.example.com/api/photos
  - status_code: 200
  - status_message: OK
```

### **For Every Error:**
```
Breadcrumb: "HTTP Error: POST /api/photos - timeout"
Metadata:
  - type: error
  - method: POST
  - url: https://api.example.com/api/photos
  - error_type: connectionTimeout
  - error_message: Connection timeout [30000ms]
  - status_code: none
```

---

## 🧪 Testing

### **Test Network Breadcrumbs:**

1. **Make successful API call:**
   ```dart
   await apiService.createSession();
   ```
   
   **Check Bugsnag**: Should see breadcrumbs:
   - `HTTP Request: POST /api/sessions`
   - `HTTP Response: POST /api/sessions - 200`

2. **Trigger API error:**
   ```dart
   // Turn off internet or use wrong URL
   await apiService.uploadPhoto(...);
   ```
   
   **Check Bugsnag**: Should see breadcrumbs:
   - `HTTP Request: POST /api/photos`
   - `HTTP Error: POST /api/photos - connectionTimeout`

3. **Print to network printer:**
   ```dart
   await printService.printImageToNetworkPrinter(...);
   ```
   
   **Check Bugsnag**: Should see breadcrumbs:
   - `HTTP Request: POST /api/PrintImage`
   - `HTTP Response: POST /api/PrintImage - 200`

---

## 📝 Files Modified

| File | Changes |
|------|---------|
| `pubspec.yaml` | No additional package needed |
| `lib/services/bugsnag_dio_interceptor.dart` | ✅ Created (custom interceptor) |
| `lib/services/api_service.dart` | Added interceptor to main Dio |
| `lib/services/api_service.dart` | Added interceptor to timeout Dio |
| `lib/services/print_service.dart` | Added interceptor to printer Dio |
| `lib/services/print_service.dart` | Added interceptor to download Dio |

---

## 🔄 Dual Tracking System

You now have **two levels** of network tracking:

### **Level 1: Bugsnag Automatic Breadcrumbs** (NEW!)
```
✅ Automatic via BugsnagDioInterceptor
✅ Captures requests, responses, errors
✅ Standard format
✅ Minimal metadata
```

### **Level 2: ErrorReportingManager Detailed Logging** (Existing)
```
✅ Manual via ApiLoggingInterceptor
✅ Detailed error records with full context
✅ Custom keys for filtering
✅ Rich metadata
```

**Why Both?**
- **Breadcrumbs** = Quick overview of all network activity
- **Error Records** = Deep dive into failures with full context

They complement each other perfectly!

---

## 📊 Bugsnag Dashboard View

### **Breadcrumbs Tab:**
```
🔗 HTTP Request: POST /api/sessions
🔗 HTTP Response: POST /api/sessions - 200
   User action breadcrumb
🔗 HTTP Request: POST /api/photos
❌ HTTP Error: POST /api/photos - timeout
   ↑ ERROR OCCURRED
```

### **Error Details:**
```
Error: DioException - Connection Timeout
Context: API Call Failed: POST /api/photos

Breadcrumbs (Last 20):
  [All the HTTP requests/responses above]

Custom Metadata:
  api_method: POST
  api_url: https://api.example.com/api/photos
  error_type: connectionTimeout
  [etc.]
```

---

## ✨ Features

### **1. Automatic Capture**
- No manual logging needed
- Works for all Dio requests
- Consistent format

### **2. Rich Metadata**
- URL and path
- HTTP method
- Status codes
- Error types
- Error messages

### **3. Error Context**
- See full API call sequence
- Understand what happened before error
- Track user journey
- Debug API issues

### **4. Silent Failure**
- If Bugsnag has issues, doesn't break app
- Wrapped in try-catch
- App continues normally

---

## 🎯 Use Cases

### **Debugging API Timeouts:**
```
Breadcrumbs show:
1. HTTP Request: POST /api/photos (started)
2. [8-10 seconds pass]
3. HTTP Error: POST /api/photos - timeout (failed)

→ Clearly shows which API timed out
```

### **Debugging 500 Errors:**
```
Breadcrumbs show:
1. HTTP Request: POST /api/sessions
2. HTTP Response: POST /api/sessions - 200
3. HTTP Request: POST /api/photos
4. HTTP Response: POST /api/photos - 500

→ Shows the exact endpoint that returned 500
```

### **Debugging Network Issues:**
```
Breadcrumbs show:
1. HTTP Request: POST /api/sessions
2. HTTP Error: POST /api/sessions - connectionError

→ Shows network unavailable from the start
```

---

## 🔍 Advanced Querying

### **In Bugsnag Dashboard:**

**Find all timeout errors:**
```
Search breadcrumbs: "HTTP Error" + "timeout"
```

**Find errors for specific endpoint:**
```
Search breadcrumbs: "/api/photos"
Filter by: type = "error"
```

**See full request/response flow:**
```
Click on error → View breadcrumbs tab
See: Request → Response → Request → Error
```

---

## 📚 Comparison: Manual vs Automatic

### **Manual Logging (Old Way - Still Works)**:
```dart
// Had to manually add in code
ErrorReportingManager.log('API Request: POST /api/photos');
await apiClient.uploadPhoto(...);
ErrorReportingManager.log('API Success: POST /api/photos - 200');
```

**Issues**:
- Extra code to maintain
- Easy to forget
- Inconsistent

### **Automatic Breadcrumbs (New Way)**:
```dart
// Just make the call - automatically tracked!
await apiClient.uploadPhoto(...);
```

**Benefits**:
- Zero code changes needed
- Never forgotten
- Always consistent
- Less maintenance

---

## ✅ Summary

| Feature | Status |
|---------|--------|
| Custom Bugsnag Dio interceptor | ✅ Created |
| Automatic request tracking | ✅ Enabled |
| Automatic response tracking | ✅ Enabled |
| Automatic error tracking | ✅ Enabled |
| Integrated in all Dio instances | ✅ Complete |
| Code compiles | ✅ No errors |

---

## 🚀 Next Steps

1. **Build and deploy:**
   ```bash
   flutter clean
   flutter pub get
   flutter build apk --release
   ```

2. **Test and monitor:**
   - Make API calls
   - Check Bugsnag breadcrumbs
   - Verify request/response tracking
   - Trigger errors and check breadcrumb trail

3. **Review in Bugsnag:**
   - Go to any error report
   - Click "Breadcrumbs" tab
   - See full network activity timeline

---

## 🎉 Result

**Every HTTP request** in your app is now automatically tracked in Bugsnag breadcrumbs!

No manual logging needed - just make API calls and they'll appear in Bugsnag with full context.

**Breadcrumb Trail Example:**
```
🔗 HTTP Request: POST /api/sessions
🔗 HTTP Response: POST /api/sessions - 200
📸 Photo capture started
✅ Photo captured successfully  
🔗 HTTP Request: POST /api/photos
❌ HTTP Error: POST /api/photos - timeout
```

**Perfect for debugging!** 🐛🔍
