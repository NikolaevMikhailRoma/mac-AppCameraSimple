#!/bin/bash
# Build the SwiftPM executable and package it as a runnable .app bundle.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="AppCameraSimple"
BUNDLE="$APP_NAME.app"

swift build -c release

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp ".build/release/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
swift Scripts/apply-config.swift app.json "$BUNDLE/Contents/Info.plist"

# app.json is the single source of the version; fail if the bundle disagrees.
EXPECTED=$(plutil -extract version raw app.json)
ACTUAL=$(plutil -extract CFBundleShortVersionString raw "$BUNDLE/Contents/Info.plist")
if [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "Version mismatch: app.json has $EXPECTED, bundle has $ACTUAL" >&2
    exit 1
fi
codesign --force --deep --sign - "$BUNDLE"

echo "Built $BUNDLE — run with: open $BUNDLE"
