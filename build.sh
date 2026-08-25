#!/bin/bash
# Build the SwiftPM executable and package it as a runnable .app bundle.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="SimpleApp"
BUNDLE="$APP_NAME.app"

swift build -c release

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
cp ".build/release/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$BUNDLE/Contents/Info.plist"
codesign --force --deep --sign - "$BUNDLE"

echo "Built $BUNDLE — run with: open $BUNDLE"
