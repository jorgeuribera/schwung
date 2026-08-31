#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# Fine Lock is no longer a global "virtual Shift held" OR.
#
# This pins the corrected split:
#   - physical Shift keeps global/navigation semantics
#   - Fine Lock is double-tapped from physical Shift only
#   - Fine Lock is consumed only by parameter-fine paths
#   - leaving the parameter-editing domain clears it

fail() { echo "FAIL: $1" >&2; exit 1; }

shadow="src/shadow/shadow_ui.js"
pages="src/shadow/shadow_ui_param_pages.mjs"
mfx="src/shadow/shadow_ui_master_fx.mjs"

shadowSrc="$(cat "$shadow")"
pagesSrc="$(cat "$pages")"
mfxSrc="$(cat "$mfx")"
scopeBody="$(sed -n '/const FINE_LOCK_SCOPE_VIEWS = new Set(\[/,/^]);/p' "$shadow")"

grep -q "const FINE_LOCK_SCOPE_VIEWS = new Set" "$shadow" || \
  fail "Fine Lock scope set is missing"
for want in \
  "VIEWS.PARAM_PAGES" \
  "VIEWS.HIERARCHY_EDITOR" \
  "VIEWS.CANVAS"
do
  grep -q "$want" "$shadow" || fail "Fine Lock scope does not name $want"
done
for avoid in \
  "VIEWS.FILEPATH_BROWSER" \
  "VIEWS.ENUM_PICKER" \
  "VIEWS.DYNAMIC_PARAM_PICKER"
do
  if grep -q "$avoid" <<<"$scopeBody"; then
    fail "Fine Lock scope should not include list/picker view $avoid"
  fi
done

grep -q "let fineLockActive = false;" "$shadow" || \
  fail "Fine Lock latch state is missing"
grep -q "function hostPhysicalShiftHeld() { return hostShiftHeld; }" "$shadow" || \
  fail "hostPhysicalShiftHeld() is missing"

physicalBody=$(awk '/^function isPhysicalShiftHeld\(\)/{f=1} f{print; if(/^}/) exit}' "$shadow")
grep -q "shadow_get_shift_held" <<<"$physicalBody" || \
  fail "isPhysicalShiftHeld() no longer consults shadow_get_shift_held"
grep -qv "fineLockActive" <<<"$physicalBody" || \
  fail "isPhysicalShiftHeld() must not consult Fine Lock"

fineBody=$(awk '/^function isFineModifierActive\(\)/{f=1} f{print; if(/^}/) exit}' "$shadow")
grep -q "isPhysicalShiftHeld()" <<<"$fineBody" || \
  fail "isFineModifierActive() no longer includes physical Shift"
grep -q "isFineLockActive()" <<<"$fineBody" || \
  fail "isFineModifierActive() no longer includes Fine Lock"

grep -q "function syncFineLockScope()" "$shadow" || \
  fail "Fine Lock scope-clear helper is missing"
grep -q "if (fineLockActive && !isFineLockScopeView()) fineLockActive = false;" "$shadow" || \
  fail "Fine Lock no longer clears when the parameter-editing scope ends"
setViewBody=$(awk '/^function setView\(newView, customLabel\)/{f=1} f{print; if(/^}/) exit}' "$shadow")
grep -q "syncFineLockScope();" <<<"$setViewBody" || \
  fail "setView() must clear Fine Lock immediately when leaving scope"

grep -q "function handleJog(delta, shift = isPhysicalShiftHeld())" "$shadow" || \
  fail "handleJog must default to PHYSICAL Shift, not Fine Lock"
grep -q "hints: isPhysicalShiftHeld() ? shiftHintsFor(selectedComp)" "$shadow" || \
  fail "chain editor footer must follow PHYSICAL Shift"
grep -q "isPhysicalShiftHeld() ? shiftHintsFor(selectedComp)" "$mfx" || \
  fail "Master FX footer must follow PHYSICAL Shift"

for pattern in \
  'if (hostPhysicalShiftHeld() && hostVolumeKnobTouched)' \
  'if (hostPhysicalShiftHeld()) {' \
  'if (hostPhysicalShiftHeld() && view === VIEWS.CHAIN_EDIT && selectedChainComponent >= 0)' \
  'if (hostPhysicalShiftHeld() && view === VIEWS.MASTER_FX && masterFxSelectedIsModule())' \
  'if (isPhysicalShiftHeld() && view === VIEWS.CHAIN_EDIT && selectedChainComponent >= 0)' \
  'if (isPhysicalShiftHeld() && view === VIEWS.MASTER_FX && masterFxSelectedIsModule())'
do
  grep -qF "$pattern" "$shadow" || fail "missing physical-Shift call site: $pattern"
done

for stale in "shiftLocked" "hostEffectiveShiftHeld"; do
  if grep -q "$stale" "$shadow"; then
    fail "stale global-lock symbol still present: $stale"
  fi
done

shiftTrack=$(awk '/Always track shift state/,/Always track mute state/' "$shadow")
grep -q "hostShiftHeld = (d2 > 0);" <<<"$shiftTrack" || \
  fail "CC49 handler no longer tracks raw physical Shift state"
grep -q "hostPhysicalShiftHeld() && !wasDown" <<<"$shiftTrack" || \
  fail "double-tap toggle must stay on the physical rising edge"
grep -q "if (isFineLockScopeView()) {" <<<"$shiftTrack" || \
  fail "double-tap no longer checks the parameter-editing scope"
grep -q "fineLockActive = !fineLockActive;" <<<"$shiftTrack" || \
  fail "double-tap no longer toggles Fine Lock"
grep -q "showFineLockStatus(fineLockActive);" <<<"$shiftTrack" || \
  fail "double-tap no longer raises Fine Lock UI feedback"

grep -q 'drawStatusOverlay("FINE LOCK", fineLockStatusMessage);' "$shadow" || \
  fail "Fine Lock status overlay draw is missing"

grep -q "controller.setReveal(physicalShiftIsHeld());" "$pages" || \
  fail "param pages reveal must stay bound to PHYSICAL Shift"
grep -q "shift: physicalShiftIsHeld()," "$pages" || \
  fail "param pages decode must feed physical Shift separately"
grep -q "fine: fineModifierActive()," "$pages" || \
  fail "param pages decode must feed fine mode separately"
grep -q '\[\["KNB", "LOCK"\]\]' "$pages" || \
  fail "param pages footer no longer shows the persistent Fine Lock indicator"

echo "  ok  physical Shift and Fine Lock are split into explicit helpers"
echo "  ok  chain/master navigation reads physical Shift only"
echo "  ok  double-tap toggles Fine Lock only inside the parameter-editing scope"
echo "  ok  param pages keep reveal on physical Shift and precision on the fine modifier"
echo "PASS: Fine Lock is scoped to parameter editing instead of globally latching Shift"
