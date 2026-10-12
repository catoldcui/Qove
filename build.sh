#!/bin/bash
# Builds build/Qove.app. Set SIGN_IDENTITY to a codesigning identity to keep
# the Accessibility grant across rebuilds (ad-hoc signatures change every build).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/Qove.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Qove "$APP/Contents/MacOS/Qove"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"

echo "Built $(pwd)/$APP"
