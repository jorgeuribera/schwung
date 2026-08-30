#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# Shift Lock: double-tap Shift toggles a latch that OR's into the SAME two
# places every Shift-layer command already reads Shift from, so nothing
# downstream re-implements "shift or locked" for itself.
#
#   isShiftHeld()            the SHM-backed read most call sites use
#   hostEffectiveShiftHeld() the small overtake-mode-local-tracking group
#
# Static/source-pin style, matching test_overlay_shift_fine.sh and the static
# half of test_tempo_landmarks.sh: shadow_ui.js is a host-dependent monolith
# not meant to run standalone in Node, so this pins the SHAPE of the fix
# rather than executing it.

fail() { echo "FAIL: $1" >&2; exit 1; }
file="src/shadow/shadow_ui.js"
src="$(cat "$file")"

# 1. isShiftHeld() must check the lock, and momentary Shift must still work
#    (shadow_get_shift_held is still consulted, not replaced).
isShiftHeldBody=$(awk '/^function isShiftHeld\(\)/{f=1} f{print; if(/^}/) exit}' "$file")
echo "$isShiftHeldBody" | grep -q "shiftLocked" || \
  fail "isShiftHeld() no longer consults shiftLocked"
echo "$isShiftHeldBody" | grep -q "shadow_get_shift_held" || \
  fail "isShiftHeld() no longer consults shadow_get_shift_held -- momentary Shift would break"

# 2. hostEffectiveShiftHeld must exist and be the ONE place hostShiftHeld is
#    OR'd with the lock -- not duplicated at each of its few read sites.
grep -q "function hostEffectiveShiftHeld() { return hostShiftHeld || shiftLocked; }" "$file" || \
  fail "hostEffectiveShiftHeld() is missing or no longer a plain OR of hostShiftHeld and shiftLocked"

n=$(echo "$src" | grep -c "shiftLocked" || true)
[ "$n" -ge 3 ] || fail "shiftLocked appears in only $n places; expected the declaration plus both OR sites at minimum"

# 3. The overtake-mode-local escape/exit gestures and the co-run CHAIN_EDIT
#    Shift+Click branches must read the EFFECTIVE flag, not the raw one --
#    otherwise Shift Lock would work in most of the UI but silently not here.
for pattern in \
  'if (hostEffectiveShiftHeld() && hostVolumeKnobTouched)' \
  'if (hostEffectiveShiftHeld()) {' \
  'if (hostEffectiveShiftHeld() && view === VIEWS.CHAIN_EDIT && selectedChainComponent >= 0)' \
  'if (hostEffectiveShiftHeld() && view === VIEWS.MASTER_FX && masterFxSelectedIsModule())'
do
  echo "$src" | grep -qF "$pattern" || fail "missing effective-shift read: $pattern"
done

# Regression: no gating read of the BARE hostShiftHeld should remain (the
# three unconditional resets that clear the raw physical tracker for the
# swallowed-shift-release workaround are fine and expected to stay bare).
# (excludes the double-tap detector's own rising-edge check, which reads
# hostShiftHeld deliberately -- that IS the raw physical press, not a
# Shift-layer command gate)
bareGating=$(echo "$src" | grep -n "if (hostShiftHeld" | grep -v "wasDown" || true)
if [ -n "$bareGating" ]; then
  echo "FAIL: a gating read still uses raw hostShiftHeld instead of hostEffectiveShiftHeld():" >&2
  echo "$bareGating" >&2
  exit 1
fi

# 4. Double-tap detection: momentary Shift must go true on the SAME press
#    that might turn out to be a double-tap (no waiting to decide), and a
#    debounce window constant must exist and be applied on the rising edge
#    only (not on release, which would let a long hold plus a bounce count).
grep -q "SHIFT_DOUBLE_TAP_MS" "$file" || fail "no double-tap timing constant found"
grep -q "hostShiftHeld = (d2 > 0);" "$file" || fail "the CC49 handler no longer sets hostShiftHeld unconditionally on press/release"
awk '/Always track shift state/,/Always track mute state/' "$file" | grep -q "hostShiftHeld && !wasDown" || \
  fail "double-tap toggle is not gated on the RISING edge (wasDown check) -- a release could also toggle it"
awk '/Always track shift state/,/Always track mute state/' "$file" | grep -q "shiftLocked = !shiftLocked" || \
  fail "the rising-edge double-tap branch does not toggle shiftLocked"

echo "  ok  isShiftHeld() ORs in the lock without dropping the live SHM read"
echo "  ok  hostEffectiveShiftHeld() is the one OR site for the overtake-local tracker"
echo "  ok  the overtake escape/exit gestures and co-run Shift+Click read the effective flag"
echo "  ok  no gating read of the codebase was left on the raw, lock-blind hostShiftHeld"
echo "  ok  double-tap toggles on the rising edge only, behind a named debounce constant"
echo "PASS: Shift Lock ORs into every existing Shift-layer read from one place"
