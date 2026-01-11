# UVCCamera Dependency Fix

## Issue
JitPack doesn't support `master` as a version. We need to use a specific commit hash or tag.

## Solutions

### Option 1: Use Specific Commit Hash (Recommended)
Find a recent commit hash from the UVCCamera repository and use:
```gradle
implementation 'com.github.saki4510t:UVCCamera:COMMIT_HASH'
```

### Option 2: Use Latest Snapshot
```gradle
implementation 'com.github.saki4510t:UVCCamera:-SNAPSHOT'
```

### Option 3: Include as Local Module
Clone the UVCCamera repository and include it as a local module in your project.

### Option 4: Use Pre-built AAR
Download a pre-built AAR file and include it locally.

## Current Status
Trying commit hash approach. If this fails, we'll implement Option 3 or 4.
