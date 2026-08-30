#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

# Reported from hardware: declared step 0.3 (fine 0.03) displayed at ONE
# decimal, so 0.03, 0.06, 0.09 ... all rendered as "0.0"/"0.1"/"0.2" -- several
# physically distinct fine-adjust values reading identically on the OLED. The
# CANONICAL values were always correct (formatParamForSet already keeps >=3
# decimals on the wire); this was a display-only bug in formatParamValue,
# which derived its decimal count from the COARSE declared step alone.
#
# Fix: `effectivePrecisionForStep` (param_format.mjs) also considers the
# param's own fine-adjust size, via `fineStepFor` (knob_engine.mjs) -- but
# ONLY for knob_step_mode: "declared". Extending it to the default
# range-normalised engine was measured and rejected: freeverb's room_size
# (declared step 0.05, ordinary fleet shape) has an actual fine-adjust size of
# 0.0005, and showing that would push nearly the whole existing float fleet to
# 4 decimals for a distinction the range-normalised engine was never designed
# to make individually visible. Declared mode is the one place that DOES
# promise exact values, so the fix is scoped to it.
#
# This file pins three things:
#   - fineStepFor never drifts from what knobStep's own fine branch actually
#     produces (the two are separate, deliberately duplicated one-liners --
#     see fineStepFor's own doc comment for why -- so nothing else catches it)
#   - declared-mode display now shows every canonical fine-adjust value
#     distinctly, matching the two hardware-reported cases exactly
#   - every OTHER param (no knob_step_mode, or an int, or an enum) renders
#     BYTE-IDENTICAL to before this fix -- zero fleet regression

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: node is required for the fine-step display tests" >&2
  exit 1
fi

node -e '
Promise.all([
  import("./src/shared/knob_engine.mjs"),
  import("./src/shared/param_format.mjs"),
]).then(([K, F]) => {
  const { knobInit, knobStep, fineStepFor } = K;
  const { formatParamValue, precisionForStep, effectivePrecisionForStep } = F;
  const fail = (msg) => { console.log("FAIL: " + msg); process.exit(1); };

  /* ---- fineStepFor must never drift from what knobStep actually does ---- */
  const CASES = [
    { type: "float", min: 0, max: 1,    step: 0.3, knob_step_mode: "declared" },
    { type: "float", min: 0, max: 4000, step: 5,   knob_step_mode: "declared" },
    { type: "int",   min: 0, max: 4000, step: 1,   knob_step_mode: "declared" },
    { type: "float", min: 0, max: 1,    step: 0.05 },              /* default engine */
    { type: "int",   min: 0, max: 127,  step: 1 },                 /* default engine */
  ];
  for (const meta of CASES) {
    const predicted = fineStepFor(meta);
    const st = knobInit(meta.min);
    const actual = knobStep(st, meta, 1, 1000, true) - meta.min;
    if (Math.abs(predicted - actual) > 1e-9)
      fail(`fineStepFor predicted ${predicted} for ${JSON.stringify(meta)}, ` +
           `but knobStep actually produced ${actual} on the first fine detent`);
  }
  if (fineStepFor({ type: "enum", options: ["a", "b"] }) !== null)
    fail("fineStepFor returned a numeric size for an enum, which has none");
  if (fineStepFor({ type: "float", min: 0, max: 1, step: 0.1, knobAcceleration: "wide" }) !== null)
    fail("fineStepFor returned a size for knobAcceleration:\"wide\", which has no fine multiplier");

  /* ---- the two hardware-reported cases, now distinguishable -------------- */
  {
    const meta = { type: "float", min: 0, max: 1, step: 0.3, unit: "u", knob_step_mode: "declared" };
    const shown = [0.03, 0.06, 0.09, 0.12, 0.15].map((v) => formatParamValue(v, meta));
    if (new Set(shown).size !== shown.length)
      fail("declared_short-style fine values still collide on display: " + JSON.stringify(shown));
    if (effectivePrecisionForStep(meta) < 2)
      fail(`declared step 0.3 (fine 0.03) must display at least 2 decimals, got ${effectivePrecisionForStep(meta)}`);
  }
  {
    const meta = { type: "float", min: 0, max: 4000, step: 5, unit: "u", knob_step_mode: "declared" };
    const shown = [0.5, 1.0, 1.5, 2.0, 2.5].map((v) => formatParamValue(v, meta));
    if (new Set(shown).size !== shown.length)
      fail("declared_long-style fine values still collide on display: " + JSON.stringify(shown));
    if (effectivePrecisionForStep(meta) < 1)
      fail(`declared step 5 (fine 0.5) must display at least 1 decimal, got ${effectivePrecisionForStep(meta)}`);
  }

  /* ---- shift is NOT a display mode: precision never depends on it -------- */
  {
    const meta = { type: "float", min: 0, max: 1, step: 0.3, unit: "u", knob_step_mode: "declared" };
    if (effectivePrecisionForStep(meta) !== effectivePrecisionForStep(meta))
      fail("effectivePrecisionForStep is not even deterministic");
    /* There is no `fine` argument to the function at all -- this is a
     * structural guarantee, not just a repeated-call check: precision comes
     * only from meta, so it cannot differ between a coarse and a fine read
     * of the very same parameter. */
    if (F.effectivePrecisionForStep.length > 2)
      fail("effectivePrecisionForStep grew a third argument -- precision must not be conditioned on the gesture");
  }

  /* ---- zero regression: every OTHER param renders EXACTLY as before ------ */
  {
    const before = precisionForStep;
    const cases = [
      { type: "float", min: 0, max: 1, step: 0.05, unit: "u" },       /* freeverb-shaped */
      { type: "float", min: 0, max: 1, step: 0.01, unit: "%" },
      { type: "float", min: 20, max: 20000, step: 1, unit: "Hz" },
      { type: "float", min: -60, max: 6, step: 0.5, unit: "dB" },
      { type: "int", min: 0, max: 127, step: 1 },
    ];
    for (const meta of cases) {
      const got = effectivePrecisionForStep(meta, 2);
      const want = before(meta.step, 2);
      if (got !== want)
        fail(`a param with no knob_step_mode changed precision: ${JSON.stringify(meta)} -> ` +
             `got ${got}, want ${want} (unchanged from precisionForStep)`);
    }
    /* And the concrete freeverb-shaped example: showing its ACTUAL fine size
     * (0.0005) would be 4 decimals -- confirm the fix does NOT do that. */
    const roomSize = { type: "float", min: 0, max: 1, step: 0.05, unit: "u" };
    if (effectivePrecisionForStep(roomSize) !== 2)
      fail(`a non-declared float must not gain gratuitous decimals: got ` +
           `${effectivePrecisionForStep(roomSize)}, want 2 (unchanged)`);
  }

  console.log("PASS fine-step display precision: declared mode distinguishable, fleet unaffected");
}).catch((e) => { console.log("FAIL import:", e); process.exit(1); });
'
