#!/bin/bash
# Every helper shadow_ui.js calls must exist in it. isShiftHeld() was deleted once and its later
# call sites (Scenes, canvas escape) threw ReferenceError, which silently dropped the input.
set -e
cd "$(dirname "$0")/../.."
f=src/shadow/shadow_ui.js
calls=$(grep -c 'isShiftHeld()' "$f" || true)
defs=$(grep -c '^function isShiftHeld()' "$f" || true)
if [ "$calls" -gt 0 ] && [ "$defs" -ne 1 ]; then
  echo "FAIL: isShiftHeld() is called $calls times but defined $defs times in $f"; exit 1
fi
echo "PASS: isShiftHeld() defined once ($calls uses)"
