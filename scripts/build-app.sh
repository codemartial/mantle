#!/usr/bin/env bash
# Build Metadater as a .app bundle wrapping the SPM-built executable.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="dist/Metadater.app"
BIN_NAME="Metadater"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

# Find the built binary (path differs slightly by arch / SPM version)
BIN_PATH=$(swift build -c "$CONFIG" --show-bin-path)/"$BIN_NAME"
if [ ! -x "$BIN_PATH" ]; then
    echo "ERROR: built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> wrapping into $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp Sources/Metadater/Resources/Info.plist "$APP/Contents/Info.plist"

# Copy SPM-bundled resources if present (target_target.bundle convention)
BUILD_DIR=$(dirname "$BIN_PATH")
if [ -d "$BUILD_DIR/Metadater_Metadater.bundle" ]; then
    cp -R "$BUILD_DIR/Metadater_Metadater.bundle" "$APP/Contents/Resources/"
fi

# Ad-hoc sign so Gatekeeper doesn't refuse to launch a quarantined binary
codesign --force --deep --sign - \
    --entitlements Sources/Metadater/Resources/Metadater.entitlements \
    "$APP" 2>/dev/null || codesign --force --deep --sign - "$APP"

echo "==> built $APP"
ls -la "$APP/Contents/MacOS"
