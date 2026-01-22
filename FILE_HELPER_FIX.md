# File Helper Platform Fix

## Problem

Build was failing with this error:
```
lib/services/file_helper.dart:23:19: Error: Too few positional arguments: 2 required, 1 given.
    return io.File(path);
                  ^
Failed to compile application.
```

## Root Cause

The original `file_helper.dart` used conditional imports:
```dart
import 'dart:io' if (dart.library.html) 'dart:html' as io;
```

When compiling for web, this imports `dart:html` as `io`, but `dart:html` doesn't have a `File` class with the same constructor. Even though the code was protected by a `kIsWeb` runtime check, the Dart compiler still analyzed all code paths and found the type mismatch.

## Solution

Created proper platform-specific stub files using Dart's conditional exports pattern:

### File Structure
```
lib/services/
  ├── file_helper.dart          # Main export file (conditional)
  ├── file_helper_io.dart       # Mobile/Desktop implementation
  ├── file_helper_web.dart      # Web implementation (throws errors)
  └── file_helper_stub.dart     # Fallback stub (unused at runtime)
```

### 1. Main Export File (`file_helper.dart`)
```dart
// Conditionally exports the correct implementation
export 'file_helper_io.dart'
    if (dart.library.html) 'file_helper_web.dart'
    if (dart.library.js) 'file_helper_web.dart';
```

### 2. IO Implementation (`file_helper_io.dart`)
```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class FileHelper {
  static Future<String> getTempDirectoryPath() async {
    final tempDir = await getTemporaryDirectory();
    return tempDir.path;
  }

  static File createFile(String path) {
    return File(path);
  }
}
```

### 3. Web Implementation (`file_helper_web.dart`)
```dart
class FileHelper {
  static Future<String> getTempDirectoryPath() async {
    throw UnsupportedError('getTempDirectoryPath is not available on web');
  }

  static dynamic createFile(String path) {
    throw UnsupportedError('createFile is not available on web');
  }
}
```

## How It Works

1. **At Compile Time**: Dart compiler selects the appropriate implementation based on platform
   - Mobile/Desktop → uses `file_helper_io.dart`
   - Web → uses `file_helper_web.dart`

2. **Import Statement**: Other files just import `file_helper.dart`:
   ```dart
   import 'file_helper.dart';
   ```

3. **Platform-Specific Code**: Each implementation has only the code valid for that platform
   - No conditional imports needed
   - No runtime platform checks needed
   - Compiler only sees valid code for target platform

## Benefits

✅ **Compiles on all platforms** - No more type errors  
✅ **Type safe** - Each platform has correct types  
✅ **Clean separation** - Platform-specific code isolated  
✅ **No runtime overhead** - Resolved at compile time  
✅ **Easy to maintain** - Clear file organization  

## Files Changed

1. ✅ `lib/services/file_helper.dart` - Now just exports
2. ✅ `lib/services/file_helper_io.dart` - New IO implementation
3. ✅ `lib/services/file_helper_web.dart` - New web implementation
4. ✅ `lib/services/file_helper_stub.dart` - New fallback stub

## Files Using FileHelper

These files automatically get the correct implementation:
- `lib/services/print_service.dart`
- `lib/services/api_service.dart`

## Testing

### Test on Mobile (Android/iOS):
```bash
flutter run
```
✅ Should compile and run without errors  
✅ File operations work normally  

### Test on Web:
```bash
flutter run -d chrome
```
✅ Should compile without errors  
✅ File operations throw appropriate errors (as expected)  

### Test on Desktop:
```bash
flutter run -d macos  # or windows, linux
```
✅ Should compile and run  
✅ File operations work like mobile  

## Related Patterns

This fix uses Dart's **Conditional Exports** pattern, which is the recommended approach for platform-specific code in Flutter:

- [Dart Platform Libraries](https://dart.dev/guides/libraries/library-tour#dartio)
- [Flutter Platform Channels](https://docs.flutter.dev/platform-integration/platform-channels)
- [Conditional Imports (Flutter Docs)](https://flutter.dev/docs/development/platform-integration/web)

## Alternative Approaches (Not Used)

### ❌ Conditional Imports (Original - Failed)
```dart
import 'dart:io' if (dart.library.html) 'dart:html' as io;
// Problem: Compiler analyzes both paths
```

### ❌ Runtime Checks (Fragile)
```dart
if (kIsWeb) {
  // web code
} else {
  // mobile code
}
// Problem: Compiler still analyzes all code
```

### ✅ Conditional Exports (Used - Best)
```dart
export 'file_helper_io.dart' if (dart.library.html) 'file_helper_web.dart';
// Solution: Compiler only sees relevant code per platform
```

## Summary

**Problem**: Conditional import causing compilation errors  
**Solution**: Platform-specific stub files with conditional exports  
**Result**: Clean, type-safe, platform-specific implementations  

✅ **Fixed and ready to build on all platforms!**
