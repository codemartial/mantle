#!/bin/sh
# Tier 2: the full suite (tier 1 + integration). Run before cutting a release.
#
# Integration tests write real files, decode images via ImageIO, and round-trip
# metadata through the bundled ExifTool. The ExifTool-dependent tests skip
# (rather than fail) if the binary can't be resolved, so this first makes sure
# it is fetched into the resource bundle.
set -eu
cd "$(dirname "$0")/.."
if [ -x scripts/ensure-exiftool.sh ]; then
    scripts/ensure-exiftool.sh
fi
exec swift test "$@"
