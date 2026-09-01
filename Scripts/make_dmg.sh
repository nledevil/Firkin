#!/usr/bin/env bash
# Build a release Firkin.app and wrap it in a drag-to-Applications DMG at
# build/Firkin-<version>.dmg. Set ARCHES="arm64 x86_64" for a universal build.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"
APP_NAME=${APP_NAME:-Firkin}

"$ROOT/Scripts/package_app.sh" release

STAGING="$ROOT/build/dmg-staging"
DMG="$ROOT/build/${APP_NAME}-${MARKETING_VERSION}.dmg"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$ROOT/${APP_NAME}.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
echo "Created $DMG"
