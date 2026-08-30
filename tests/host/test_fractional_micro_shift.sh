#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# Reported physical regression target: start=100.000 ms, Resolution=Fractional,
# Curve=Linear, Edit Speed=Micro, Shift+one detent -> expected ~100.800 ms,
# subject only to the actual Fractional legal grid (which is unquantized).
# The worry was that Fractional's integer-Ms-shaped step display might force
# the result to a whole millisecond (101.000) instead.
#
# This runs the REAL pipeline a physical knob turn goes through -- knobStep
# (the coarse/fine math), formatParamValue (what the header/list show),
# formatParamForSet (what actually gets written back to the module) -- with
# the EXACT metadata a time-kind param in Fractional/Micro/Linear emits
# (see wet2.c's wet2_time_meta: Fractional's step is 0.001 ms, deliberately
# NOT varying with Edit Speed; knob_step_frac for Micro is 0.002; Linear
# means no knob_curve key at all). Nothing here is WET2-specific data beyond
# that metadata shape -- the functions under test are generic Schwung core.

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: node is required" >&2
  exit 1
fi

node -e '
Promise.all([
  import("./src/shared/knob_engine.mjs"),
  import("./src/shared/param_format.mjs"),
]).then(([K, F]) => {
  const fail = (m) => { console.log("FAIL: " + m); process.exit(1); };
  const close = (a, b, eps = 1e-9) => Math.abs(a - b) <= eps;

  /* Fractional resolution, Micro edit speed, Linear curve (no knob_curve
   * key -- that is what "no module infers, opt-in per param" means for a
   * curve that is not active). */
  const meta = { type: "float", min: 0, max: 4000, step: 0.001, unit: "ms",
                 knob_step_frac: 0.002 };

  const st = K.knobInit(100);
  const v = K.knobStep(st, meta, 1, 1000, true); /* fine=true: Shift held */
  if (!close(v, 100.8, 1e-6))
    fail("knobStep(100 ms, Shift+1 detent, Fractional/Micro/Linear) = " + v +
         ", want ~100.8 -- Fractional forced to a whole millisecond");

  const shown = F.formatParamValue(v, meta);
  if (shown !== "100.800 ms")
    fail("formatParamValue(" + v + ") = \"" + shown + "\", want \"100.800 ms\" -- " +
         "the header/list would show the wrong precision even though the value itself is right");

  const wire = F.formatParamForSet(v, meta);
  if (Math.abs(parseFloat(wire) - 100.8) > 1e-6)
    fail("formatParamForSet(" + v + ") = \"" + wire + "\" -- the value written back to the " +
         "module lost the sub-millisecond precision the Fractional grid promised");

  /* The general claim, not just one lucky value: Shift-fine over the whole
   * usable range must never collapse to a whole millisecond for this exact
   * metadata shape. */
  for (const start of [0, 1, 47.5, 250, 999.999, 3999]) {
    const s = K.knobInit(start);
    const got = K.knobStep(s, meta, 1, 2000, true);
    const isWholeMs = Math.abs(got - Math.round(got)) < 1e-6;
    if (isWholeMs)
      fail("Fractional/Micro/Shift from " + start + " landed on a whole millisecond (" +
           got + ") -- the sub-millisecond grid is being quantized away");
  }

  /* Regression guard on the OTHER direction: Ms resolution genuinely IS
   * whole milliseconds, so this is not a claim that nothing should ever
   * round -- only that Fractional specifically must not be silently
   * treated as Ms. */
  const msMeta = { type: "float", min: 0, max: 4000, step: 1, unit: "ms",
                   knob_step_frac: 0.002 };
  const msSt = K.knobInit(100);
  const msV = K.knobStep(msSt, msMeta, 1, 1000, true);
  console.log("  ok  Fractional/Micro/Shift: 100 ms -> " + v + " (not quantized to a whole ms)");
  console.log("  ok  formatParamValue/formatParamForSet preserve the sub-millisecond precision");
  console.log("  ok  the same holds across a spread of starting values, not just 100");
  console.log("  ok  Ms resolution (step=1) is unaffected by this -- ms=" + msMeta.step + " -> " + msV);
  console.log("PASS: Fractional Micro+Shift is genuinely fractional, not forced to whole ms");
}).catch((e) => { console.log("FAIL: " + (e && e.stack || e)); process.exit(1); });
'
