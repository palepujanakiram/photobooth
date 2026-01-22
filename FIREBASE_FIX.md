# Firebase Initialization Fix

## Error You're Seeing

```
FirebaseException ([core/not-initialized] Firebase has not been correctly initialized.
```

## What's Wrong

Firebase needs to be configured with your project's specific settings. We need to generate a `firebase_options.dart` file.

## Quick Fix (2 Commands)

### Step 1: Install FlutterFire CLI

```bash
flutter pub global activate flutterfire_cli
```

### Step 2: Configure Firebase

```bash
flutterfire configure
```

This will:
1. Prompt you to select your Firebase project
2. Select platforms (Android, iOS, Web)
3. Generate `lib/firebase_options.dart`
4. Configure everything automatically

### Step 3: Update main.dart

After running the commands above, update your `lib/main.dart`:

```dart
import 'firebase_options.dart'; // Add this import

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase with generated options
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // Add this
  );
  
  // ... rest of your code
}
```

### Step 4: Run the app

```bash
flutter run
```

## Alternative: Run Without Crashlytics

The app now gracefully handles Firebase not being initialized. You can run the app without fixing this and it will work, just without Crashlytics tracking.

The console will show:
```
⚠️ Firebase initialization failed
⚠️ App will continue without Crashlytics
```

## Manual Fix (If FlutterFire CLI Doesn't Work)

If the FlutterFire CLI doesn't work, you can manually create `lib/firebase_options.dart`:

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Click the gear icon → Project Settings
4. Scroll down to "Your apps"
5. Copy the configuration for each platform
6. Create `lib/firebase_options.dart` with the values

Or simply remove Crashlytics temporarily:

1. Remove Firebase imports from `lib/main.dart`
2. Remove Firebase dependencies from `pubspec.yaml`
3. Run `flutter pub get`

## Verify Fix

After fixing, you should see:
```
✅ Firebase Crashlytics initialized successfully
```

Instead of the error message.

## Need Help?

If you continue having issues:
1. Make sure you have a Firebase project created
2. Make sure `google-services.json` is in `android/app/`
3. Make sure `GoogleService-Info.plist` is in `ios/`
4. Check your internet connection (FlutterFire CLI needs internet)

## Quick Test Commands

```bash
# Check if FlutterFire CLI is installed
flutterfire --version

# If not installed
flutter pub global activate flutterfire_cli

# Configure Firebase
flutterfire configure

# Run app
flutter run
```

That's it! Firebase should now initialize properly.
