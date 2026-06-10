#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Tahir Hashmi
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
#
# This file is part of Mantle, licensed under the PolyForm Noncommercial
# License 1.0.0 -- free for any noncommercial purpose, including
# modification. See the LICENSE file for the full text, or
# <https://polyformproject.org/licenses/noncommercial/1.0.0>.

# Build Mantle as a .app bundle wrapping the SPM-built executable.
set -euo pipefail

cd "$(dirname "$0")/.."

"$(dirname "$0")/ensure-exiftool.sh"

CONFIG="${CONFIG:-release}"
APP="dist/Mantle.app"
BIN_NAME="Mantle"

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
cp Sources/Mantle/Resources/Info.plist "$APP/Contents/Info.plist"
cp Sources/Mantle/Resources/Mantle.icns "$APP/Contents/Resources/Mantle.icns"
cp Sources/Mantle/Resources/Credits.rtf "$APP/Contents/Resources/Credits.rtf"

# Stamp the current year into the copyright string.
plutil -replace NSHumanReadableCopyright -string "© $(date +%Y) Tahir Hashmi" "$APP/Contents/Info.plist"

# Copy SPM-bundled resources if present (target_target.bundle convention)
BUILD_DIR=$(dirname "$BIN_PATH")
if [ -d "$BUILD_DIR/Mantle_Mantle.bundle" ]; then
    cp -R "$BUILD_DIR/Mantle_Mantle.bundle" "$APP/Contents/Resources/"
fi

# Ad-hoc sign so Gatekeeper doesn't refuse to launch a quarantined binary
codesign --force --deep --sign - \
    --entitlements Sources/Mantle/Resources/Mantle.entitlements \
    "$APP" 2>/dev/null || codesign --force --deep --sign - "$APP"

echo "==> built $APP"
ls -la "$APP/Contents/MacOS"

# Package into a DMG for distribution
DMG="dist/Mantle Installer.dmg"
STAGE="dist/dmg-stage"
echo "==> packaging $DMG"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp Sources/Mantle/Resources/Mantle.icns "$STAGE/.VolumeIcon.icns"
cat > "$STAGE/Read Me first.txt" <<'EOF'
DO NOT CLICK 'AGREE'. READ THIS.
================================

Requires macOS 14 (Sonoma) or later on Apple Silicon.

This app is ad-hoc signed (no paid Apple Developer account), so macOS
Gatekeeper blocks the first launch. One-time workaround:

  1. Drag Mantle.app onto the Applications shortcut in this window.
  2. Open Applications and double-click Mantle. You will see a
     dialog saying it cannot be opened. Click Done.
  3. Open System Settings -> Privacy & Security.
  4. Scroll to the Security section near the bottom. You will see
     a message about Mantle being blocked, with an Open Anyway
     button. Click it.
  5. Confirm with your password or Touch ID.

After this one-time approval, double-click launches it normally.

Mantle is provided AS-IS with NO WARRANTY of SUITABILITY or SECURITY.
The developer is NOT LIABLE for any harm caused by the use of this
software.

If you have understood the instructions and wish to proceed, please
click 'Agree'.
EOF

# Build a writable DMG, mount it, set the custom-icon attribute on the
# volume, detach, then convert to compressed read-only.
RWDMG="dist/Mantle-rw.dmg"
rm -f "$RWDMG"
hdiutil detach -force "/Volumes/Mantle Installer" 2>/dev/null || true
hdiutil create -volname "Mantle Installer" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RWDMG" >/dev/null
DEVICE=$(hdiutil attach -nobrowse -noverify -noautoopen "$RWDMG" | awk 'NR==1{print $1}')
SetFile -a C "/Volumes/Mantle Installer"
hdiutil detach "$DEVICE" >/dev/null
hdiutil convert "$RWDMG" -format UDZO -ov -o "$DMG" >/dev/null
rm -f "$RWDMG"

# Set a custom icon on the DMG file itself; this is also what shows up
# in the left sidebar of the SLA dialog.
ICNS_COPY="$(mktemp -t mantle-icon).icns"
cp Sources/Mantle/Resources/Mantle.icns "$ICNS_COPY"
sips -i "$ICNS_COPY" >/dev/null
RSRC="$(mktemp -t mantle-icon).rsrc"
DeRez -only icns "$ICNS_COPY" > "$RSRC"
Rez -append "$RSRC" -o "$DMG"
SetFile -a C "$DMG"
rm -f "$ICNS_COPY" "$RSRC"

# Embed the install instructions as a Software License Agreement so they
# pop up in a mandatory dialog before the DMG mounts.
echo "==> embedding install instructions as SLA"
SLA_PLIST="$(mktemp -t mantle-sla).plist"
python3 - "$STAGE/Read Me first.txt" > "$SLA_PLIST" <<'PY'
import plistlib, struct, sys

text = open(sys.argv[1], "rb").read().replace(b"\n", b"\r")

# LPic: default English, one language entry, IDs at offset 0, single-byte text
lpic = struct.pack(">HHHHH", 0, 1, 0, 0, 0)

# STR# 5000: 6 Pascal strings used by the SLA dialog chrome
def pstr(s):
    b = s.encode("mac_roman")
    return bytes([len(b)]) + b

strings = [
    "English",
    "Agree",
    "Disagree",
    "Print",
    "Save...",
    "",
]
str_pound = struct.pack(">H", len(strings)) + b"".join(pstr(s) for s in strings)

def res(rid, name, data):
    return {"Attributes": "0x0000", "ID": str(rid), "Name": name, "Data": data}

plist = {
    "LPic": [res(5000, "", lpic)],
    "STR#": [res(5000, "English", str_pound)],
    "TEXT": [res(5000, "English", text)],
}

sys.stdout.buffer.write(plistlib.dumps(plist, fmt=plistlib.FMT_XML))
PY

# `udifrez` is the only way to attach SLA resources to a UDIF image.
# Apple deprecated it in macOS 12 but shipped no replacement -- there is
# no SLA/license flag on `hdiutil create`/`convert`, and create-dmg /
# dmgbuild still call udifrez under the hood too. `-quiet` suppresses the
# (unactionable) deprecation notice while still returning non-zero on a
# real failure, so `set -e` aborts the build if Apple ever removes it.
hdiutil udifrez -quiet -xml "$SLA_PLIST" '' "$DMG" >/dev/null
rm -f "$SLA_PLIST"
rm -rf "$STAGE"

echo "==> built $DMG"
ls -la "$DMG"
