#!/bin/sh
# Keep FlutterGeneratedPluginSwiftPackage minimum iOS in sync with Runner.
# Flutter generates the package with iOS 13.0; SPM plugins (Firebase, etc.)
# require 15.0+. Without this sync, Xcode builds fail with Target Integrity errors.
set -eu

DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-26.0}"
IOS_DIR="${SRCROOT:-$(cd "$(dirname "$0")" && pwd)}"
PACKAGE_SWIFT="${IOS_DIR}/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"

if [ ! -f "$PACKAGE_SWIFT" ]; then
  exit 0
fi

/usr/bin/sed -i '' "s/\\.iOS(\"[0-9][0-9]*\\.[0-9][0-9]*\")/.iOS(\"${DEPLOYMENT_TARGET}\")/" "$PACKAGE_SWIFT"
