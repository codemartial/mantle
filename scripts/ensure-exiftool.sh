#!/usr/bin/env bash
# Ensure a vendored copy of ExifTool exists at the expected path.
# Fetches the current release from exiftool.org when missing or stale.
# exiftool.org only hosts the latest release, so we always track latest.
# Upstream version check is rate-limited to once per week.
# Delete .last-check inside the target dir to force a recheck.

set -euo pipefail

cd "$(dirname "$0")/.."

TARGET_DIR="Sources/Mantle/Resources/exiftool"
LAST_CHECK="$TARGET_DIR/.last-check"
MAX_AGE_SECONDS=$((7 * 24 * 60 * 60))

# Fast path: skip the network entirely if we have exiftool and a recent marker.
if [ -f "$TARGET_DIR/exiftool" ] && [ -f "$LAST_CHECK" ]; then
    AGE=$(( $(date +%s) - $(stat -f %m "$LAST_CHECK") ))
    if [ "$AGE" -lt "$MAX_AGE_SECONDS" ]; then
        exit 0
    fi
fi

# Discover the current release from the homepage (only one tarball is ever linked).
LATEST=$(curl -sSL https://exiftool.org/ \
    | grep -oE 'Image-ExifTool-[0-9.]+\.tar\.gz' \
    | head -1 \
    | sed -E 's/Image-ExifTool-([0-9.]+)\.tar\.gz/\1/')

if [ -z "$LATEST" ]; then
    echo "error: could not detect current ExifTool version from exiftool.org" >&2
    exit 1
fi

if [ -f "$TARGET_DIR/exiftool" ]; then
    LOCAL=$(awk -F"'" '/^my \$version =/ {print $2; exit}' "$TARGET_DIR/exiftool")
    if [ "$LOCAL" = "$LATEST" ]; then
        touch "$LAST_CHECK"
        exit 0
    fi
    echo "==> exiftool $LOCAL present; current is $LATEST, refetching"
else
    echo "==> exiftool missing; fetching $LATEST"
fi

TARBALL_URL="https://exiftool.org/Image-ExifTool-${LATEST}.tar.gz"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

curl -sSfL "$TARBALL_URL" -o "$TMP/exiftool.tar.gz"
tar -xzf "$TMP/exiftool.tar.gz" -C "$TMP"

rm -rf "$TARGET_DIR"
mkdir -p "$(dirname "$TARGET_DIR")"
mv "$TMP/Image-ExifTool-${LATEST}" "$TARGET_DIR"
touch "$TARGET_DIR/.last-check"

echo "==> exiftool $LATEST installed at $TARGET_DIR"
