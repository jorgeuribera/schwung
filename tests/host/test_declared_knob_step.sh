#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

# knob_step_mode: "declared" -- an opt-in per-param axis, orthogonal to the
# unified range-normalised knob model in shared/knob_engine.mjs.
#
# The unified engine (see test_knob_engine_single.sh and
# tests/shadow/test_knob_engine.sh) steps every knob by a fraction of its own
# RANGE, which is right for a knob whose job is a fast, even sweep. It is
# wrong for a parameter whose declared `step` IS the meaningful unit -- a
# module that says "step: .1" over a 0..4000 range means the value is meant to
# land on clean tenths, not on an arbitrary 1%-of-range fraction. Declaring
# `knob_step_mode: "declared"` opts a param out of range-normalisation and
# into moving by exactly its own step, one detent at a time.
#
# This file pins three things declared mode must do, and one thing it must
# never do:
#
#   - an ordinary detent moves exactly the declared step (float and int)
#   - min and max are always EXACTLY reachable -- never a float neighbour of
#     them that a detent can approach but never land on
#   - reversing off either endpoint moves immediately, one step, never a
#     skipped or partial one
#   - a param that does NOT opt in is completely unaffected -- this is an
#     additive branch in knobStep, and every other case in
#     tests/shadow/test_knob_engine.sh must still pass unmodified

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: node is required for the declared-step tests" >&2
  exit 1
fi

node -e '
import("./src/shared/knob_engine.mjs").then((m) => {
  const { knobInit, knobStep, KNOB_STEP_MODE_DECLARED, isDeclaredStepMode } = m;
  const fail = (msg) => { console.log("FAIL: " + msg); process.exit(1); };
  const close = (a, b, eps = 1e-9) => Math.abs(a - b) <= eps;

  if (!isDeclaredStepMode({ knob_step_mode: KNOB_STEP_MODE_DECLARED }))
    fail("isDeclaredStepMode does not recognise its own exported constant");
  if (isDeclaredStepMode({ knob_step_mode: "wide" }) || isDeclaredStepMode(null))
    fail("isDeclaredStepMode is true for something other than the declared mode");

  /* ---- ordinary movement: exactly the declared step, every detent ------ */
  {
    const meta = { type: "float", min: 0, max: 4000, step: 0.1, knob_step_mode: "declared" };
    const st = knobInit(0);
    const want = [0.1, 0.2, 0.3, 0.4, 0.5];
    for (const w of want) {
      const v = knobStep(st, meta, 1, 1000);
      if (!close(v, w)) fail(`declared float step: got ${v}, want ${w}`);
    }
  }

  /* ---- an int keeps an int step, and BYPASSES the narrow-range gate ----
   *
   * The default engine treats a 2..16-wide int range as enum-like and gates
   * it at ENUM_DELTA_DIV (4) detents per unit -- see NARROW_RANGE_MAX in
   * knob_engine.mjs. Declared mode is "what you turn is what you get", so
   * for a param that opts in, one detent is one declared step even in that
   * narrow band. This is the one case where declared mode is REQUIRED to
   * disagree with the default, and the disagreement is the point. */
  {
    const declared = { type: "int", min: 0, max: 16, step: 1, knob_step_mode: "declared" };
    const st = knobInit(0);
    const v = knobStep(st, declared, 1, 1000);
    if (v !== 1) fail(`declared int in a narrow range moved ${v} on one detent, want 1`);

    const withoutMode = { type: "int", min: 0, max: 16, step: 1 };
    const st2 = knobInit(0);
    const v2 = knobStep(st2, withoutMode, 1, 1000);
    if (v2 !== 0)
      fail("the narrow-range gate no longer applies to the DEFAULT engine -- " +
           "this test'"'"'s contrast with declared mode has stopped proving anything " +
           "(expected the default int to need more than one detent to move)");
  }

  /* ---- exact endpoints: reachable, pinned, and immediate to reverse off - */
  {
    /* min=0 max=1 step=.3: 0, .3, .6, .9, then MAX EXACTLY -- never 1.2, never
     * a float neighbour of 1 that compares unequal to it. */
    const meta = { type: "float", min: 0, max: 1, step: 0.3, knob_step_mode: "declared" };
    const st = knobInit(0);
    const upSeq = [0.3, 0.6, 0.9];
    for (const w of upSeq) {
      const v = knobStep(st, meta, 1, 1000);
      if (!close(v, w)) fail(`endpoint approach: got ${v}, want ${w}`);
    }
    const atMax = knobStep(st, meta, 1, 1000);
    if (atMax !== 1) fail(`max is not EXACTLY reachable: got ${atMax}, want exactly 1`);
    /* One more detent past max must not run away past it. */
    const stillMax = knobStep(st, meta, 1, 1000);
    if (stillMax !== 1) fail(`a detent past max moved off the ceiling: ${stillMax}`);
    /* Reversing off the endpoint drops exactly one step, immediately -- not a
     * skipped step (straight to .6) and not a stuck one (still at 1). */
    const backOne = knobStep(st, meta, -1, 2000);
    if (!close(backOne, 0.9)) fail(`reversing off max did not land one step below it: ${backOne}`);
    /* And forward again lands exactly back on max, immediately. */
    const backToMax = knobStep(st, meta, 1, 3000);
    if (backToMax !== 1) fail(`re-approaching max after a reversal did not land exactly on it: ${backToMax}`);

    /* The min side needs no virtual pin -- index 0 is exactly min by
     * construction -- but must still clamp and reverse immediately. */
    const st2 = knobInit(0);
    const atMin = knobStep(st2, meta, -1, 1000);
    if (atMin !== 0) fail(`a detent below min moved off it: ${atMin}`);
    const offMin = knobStep(st2, meta, 1, 2000);
    if (!close(offMin, 0.3)) fail(`reversing off min did not move exactly one step: ${offMin}`);
  }

  /* ---- max already ON the lattice needs no virtual ceiling -------------- */
  {
    const meta = { type: "float", min: 0, max: 1, step: 0.25, knob_step_mode: "declared" };
    const st = knobInit(0);
    let last;
    for (let i = 0; i < 4; i++) last = knobStep(st, meta, 1, 1000 + i * 10);
    if (last !== 1) fail(`a step that evenly divides the range did not reach exactly max: ${last}`);
    const back = knobStep(st, meta, -1, 2000);
    if (!close(back, 0.75)) fail(`reversing off an evenly-divided max skipped a step: ${back}`);
  }

  /* ---- shift-fine: a tenth of the DECLARED step, not of a range fraction */
  {
    const meta = { type: "float", min: 0, max: 4000, step: 1, knob_step_mode: "declared" };
    const st = knobInit(0);
    const v = knobStep(st, meta, 1, 1000, true);
    if (!close(v, 0.1)) fail(`declared fine step: got ${v}, want 0.1 (a tenth of the declared step 1)`);
  }
  {
    /* An int floors fine at one whole unit, same rule as the default engine. */
    const meta = { type: "int", min: 0, max: 4000, step: 1, knob_step_mode: "declared" };
    const st = knobInit(0);
    const v = knobStep(st, meta, 1, 1000, true);
    if (v !== 1) fail(`declared int fine step floored below 1: ${v}`);
  }

  /* ---- a real fleet shape: a very FINE declared step over a wide range --
   *
   * WET2/TUNNEL'"'"'s Unit edit speed reuses Fractional resolution'"'"'s own
   * already-declared display precision (0.001 ms) as its legal grid over a
   * 0..4000 range -- ~4,000,000 lattice points end to end. This is not a
   * hypothetical: it is the exact shape that mode emits. Pin that it behaves
   * exactly like any other declared step, not a special case that happens to
   * work for round numbers.
   */
  {
    const meta = { type: "float", min: 0, max: 4000, step: 0.001, knob_step_mode: "declared" };
    const st = knobInit(0);
    let v;
    for (let i = 0; i < 5; i++) v = knobStep(st, meta, 1, 1000 + i);
    if (!close(v, 0.005)) fail(`fine declared step over a wide range: got ${v}, want 0.005`);
    const back = knobStep(st, meta, -1, 2000);
    if (!close(back, 0.004)) fail(`reversing a fine declared step: got ${back}, want 0.004`);
    /* Shift-fine is a tenth of THIS step (0.0001), not of the range. */
    const fine = knobStep(st, meta, 1, 3000, true);
    if (!close(fine, 0.004 + 0.0001)) fail(`fine declared step under Shift: got ${fine}`);
  }
  /* Endpoints of that same wide/fine shape are still exact -- the lattice
   * model does not lose precision walking from one end to the other. */
  {
    const meta = { type: "float", min: 0, max: 4000, step: 0.001, knob_step_mode: "declared" };
    const st = knobInit(4000);
    const v = knobStep(st, meta, -1, 1000);
    if (!close(v, 3999.999)) fail(`stepping down from max with a fine declared step: got ${v}`);
  }

  /* ---- absent knob_step_mode is completely unaffected ------------------- */
  {
    const meta = { type: "float", min: 0, max: 1, step: 0.3 };
    const st = knobInit(0);
    const v = knobStep(st, meta, 1, 1000);
    /* The default engine steps by MIN_STEP_RANGE_FRAC of the range * 0.5
     * (ARC_DELTA_SCALE), i.e. (1-0)*0.01*0.5 = 0.005 -- nothing like the
     * declared step of 0.3. This is not a claim about what that number ought
     * to be (tests/shadow/test_knob_engine.sh owns that); it is a guard that
     * this file'"'"'s new branch is not silently reached for a param that never
     * asked for it. */
    if (close(v, 0.3)) fail("a param with no knob_step_mode moved by the DECLARED step -- " +
                            "the new branch is leaking into the default path");
  }

  console.log("PASS declared knob-step mode: exact step, exact endpoints, immediate reversal");
}).catch((e) => { console.log("FAIL import:", e); process.exit(1); });
'
