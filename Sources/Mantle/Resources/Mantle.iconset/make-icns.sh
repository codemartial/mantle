#!/usr/bin/env bash
# make-icns.sh — turn Mantle.iconset/ into Mantle.icns.
# Run from the folder containing Mantle.iconset/.

set -euo pipefail

ICONSET="Mantle.iconset"
OUT="Mantle.icns"

if [ ! -d "$ICONSET" ]; then
  echo "error: $ICONSET not found in $(pwd)" >&2
  exit 1
fi

# Step 1 — rename -2x back to @2x. (The design project's filesystem
# sandbox doesn't allow '@' in paths, so the files ship as -2x; iconutil
# wants @2x exactly.)
echo "→ renaming -2x → @2x"
(
  cd "$ICONSET"
  for f in *-2x.png; do
    [ -e "$f" ] || continue
    target="${f/-2x/@2x}"
    if [ "$f" != "$target" ]; then
      mv -- "$f" "$target"
      echo "  $f → $target"
    fi
  done
)

# Step 2 — compile.
echo "→ iconutil -c icns $ICONSET"
iconutil -c icns "$ICONSET" -o "$OUT"

echo "✓ wrote $OUT"
