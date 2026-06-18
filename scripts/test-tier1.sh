#!/bin/sh
# Tier 1: fast, in-memory sanity checks. Run after every code-complete.
#
# Pure logic only -- no ExifTool, no image decode, no real files -- so this
# finishes in well under a second. Pass extra args straight through to
# `swift test` (e.g. a --filter to narrow further).
set -eu
cd "$(dirname "$0")/.."
exec swift test --filter Tier1Tests "$@"
