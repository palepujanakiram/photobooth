# Setting Up iOS for iPad Development

## Current Status
Your iOS project needs to be fully configured. Here's how to set it up:

## Step 1: Install CocoaPods (Required)

CocoaPods is needed to manage iOS dependencies:

```bash
# Install CocoaPods using Ruby (comes with macOS)
sudo gem install cocoapods

# Verify installation
pod --version
```

## Step 2: Generate iOS Project Files

```bash
# This will create the Xcode project files
cd /Users/janakiram/Personal/Github/newPhotobooth
flutter create --platforms=ios .
```

## Step 3: Install iOS Dependencies

```bash
cd ios
pod install
```

This will:
- Install all iOS plugin dependencies
- Generate `Runner.xcworkspace` file
- Set up the project structure

## Step 4: Open in Xcode

After `pod install` completes:

```bash
# Open the workspace (NOT the .xcodeproj)
open ios/Runner.xcworkspace
```

**Important:** Always open `.xcworkspace`, never `.xcodeproj` when using CocoaPods!

## Step 5: Configure Signing in Xcode

1. In Xcode, select "Runner" in the left sidebar
2. Click on "Runner" under TARGETS
3. Go to "Signing & Capabilities" tab
4. Check "Automatically manage signing"
5. Select your Apple Developer Team
6. Xcode will automatically configure the provisioning profile

## Step 6: Run on iPad

### Option A: From Xcode
1. Select your iPad from the device dropdown (top toolbar)
2. Click the Play button to build and run

### Option B: From Terminal
```bash
flutter run -d "Janakiram's iPad"
```

## Troubleshooting

### "pod: command not found"
Install CocoaPods:
```bash
sudo gem install cocoapods
```

### "No Podfile found"
Run:
```bash
flutter create --platforms=ios .
cd ios
pod install
```

### "Code signing error"
- Open `ios/Runner.xcworkspace` in Xcode
- Go to Signing & Capabilities
- Select your Apple Developer Team
- Make sure "Automatically manage signing" is checked

### "Developer Mode not enabled"
On iPad:
- Settings > Privacy & Security > Developer Mode > ON
- Restart iPad

## Quick Setup Script

Run this to set everything up:

```bash
# 1. Install CocoaPods (if not installed)
sudo gem install cocoapods

# 2. Generate iOS project
cd /Users/janakiram/Personal/Github/newPhotobooth
flutter create --platforms=ios .

# 3. Install dependencies
cd ios
pod install

# 4. Open in Xcode
open Runner.xcworkspace
```

Then configure signing in Xcode and you're ready to go!

