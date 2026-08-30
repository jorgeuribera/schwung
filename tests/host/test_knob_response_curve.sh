#!/usr/bin/env bash
# Response curves: a knob may redistribute its physical travel through a range
# (low_focus / high_focus) while the range itself stays exactly as declared.
#
# The properties that matter are the ones that keep a relative encoder honest:
# the value never jumps, a detent is always reversible, min and max are
# reachable exactly, and the coarsest detent on the dial is bounded by the
# curve strength — so the top of a wide range cannot run away.
set -euo pipefail
cd "$(dirname "$0")/../.."

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: node is required for the response-curve tests" >&2
  exit 1
fi

node -e '
import("./src/shared/knob_engine.mjs").then((m) => {
  const {
    knobInit, knobStep,
    curveYFromU, curveUFromY, knobCurveMode, knobCurveGamma,
    KNOB_CURVE_LOW_FOCUS, KNOB_CURVE_HIGH_FOCUS, KNOB_CURVE_LINEAR,
    KNOB_STEP_MODE_DECLARED, MIN_STEP_RANGE_FRAC, ARC_DELTA_SCALE,
  } = m;

  let checks = 0;
  const fail = (msg) => { console.log("FAIL: " + msg); process.exit(1); };
  const ok = (cond, msg) => { checks++; if (!cond) fail(msg); };
  const near = (a, b, tol, msg) => {
    checks++;
    if (!(Math.abs(a - b) <= tol)) fail(msg + " (got " + a + ", want " + b + " +/-" + tol + ")");
  };

  const MIN = 0, MAX = 4000;
  const floatMeta = (extra) => Object.assign({ type: "float", min: MIN, max: MAX, step: 1 }, extra || {});
  const LOW = floatMeta({ knob_curve: KNOB_CURVE_LOW_FOCUS, knob_curve_gamma: 2 });
  const HIGH = floatMeta({ knob_curve: KNOB_CURVE_HIGH_FOCUS, knob_curve_gamma: 2 });
  const PLAIN = floatMeta();

  /* ---- 1. Linear is untouched. ---------------------------------------- *
   * A curve is opt-in. An undeclared knob, and one that explicitly says
   * linear, must take the range-normalised path exactly as before. */
  for (const start of [0, 1, 37, 347, 1234.5, 2500, 4000]) {
    for (const fine of [false, true]) {
      const a = knobStep(knobInit(start), PLAIN, +1, 1000, fine);
      const b = knobStep(knobInit(start), floatMeta({ knob_curve: KNOB_CURVE_LINEAR }), +1, 1000, fine);
      near(a, b, 0, "knob_curve:" + KNOB_CURVE_LINEAR + " must equal the plain path at " + start);
    }
  }
  /* ...and a gamma of 1 IS linear, for both families. */
  for (const mode of [KNOB_CURVE_LOW_FOCUS, KNOB_CURVE_HIGH_FOCUS]) {
    const g1 = floatMeta({ knob_curve: mode, knob_curve_gamma: 1 });
    for (const start of [0, 250, 1000, 2750]) {
      near(knobStep(knobInit(start), g1, +1, 1000, false),
           knobStep(knobInit(start), PLAIN, +1, 1000, false), 1e-9,
           "gamma 1 must be linear for " + mode + " at " + start);
    }
  }

  /* ---- 2. Exact inverse seeding at arbitrary values. ------------------- *
   * u is never stored, so it has to be recoverable from any value the
   * device might report. Round-tripping through the inverse must be exact. */
  for (const mode of [KNOB_CURVE_LOW_FOCUS, KNOB_CURVE_HIGH_FOCUS]) {
    for (const g of [1, 1.6, 2, 2.4, 8]) {
      for (let i = 0; i <= 100; i++) {
        const y = i / 100;
        near(curveYFromU(curveUFromY(y, mode, g), mode, g), y, 1e-12,
             "y->u->y round trip, " + mode + " g" + g + " at y=" + y);
      }
      /* Arbitrary, non-round values are the ones that actually arrive. */
      for (const y of [0.08675, 0.3333, 0.5, 0.6180339887, 0.99999]) {
        near(curveYFromU(curveUFromY(y, mode, g), mode, g), y, 1e-9,
             "y->u->y round trip, " + mode + " g" + g + " at y=" + y);
      }
    }
  }

  /* ---- 3. No first-detent jump. --------------------------------------- *
   * Seeding from a standing value must continue from it, not snap. The
   * first detent is bounded by the curve law: at most gamma times the
   * linear step. */
  for (const [name, meta] of [["low", LOW], ["high", HIGH]]) {
    for (const start of [0, 1, 5, 25, 100, 347, 1000, 2500, 3999]) {
      const st = knobInit(start);
      const next = knobStep(st, meta, +1, 1000, false);
      const linearStep = (MAX - MIN) * MIN_STEP_RANGE_FRAC * ARC_DELTA_SCALE;
      ok(next >= start, name + " first detent must not go backwards at " + start);
      ok(next - start <= linearStep * 2 + 1e-6,
         name + " first detent must not jump at " + start + " (moved " + (next - start) + ")");
      /* and it must actually move, unless parked on an endpoint */
      if (start > 0 && start < MAX) ok(next > start, name + " first detent must move at " + start);
    }
  }

  /* ---- 4. Exact endpoints. -------------------------------------------- */
  for (const [name, meta] of [["low", LOW], ["high", HIGH]]) {
    /* down to min */
    let st = knobInit(MAX);
    for (let i = 0; i < 4000 && st.value > MIN; i++) knobStep(st, meta, -1, 1000, false);
    near(st.value, MIN, 0, name + " must reach min exactly");
    /* up to max */
    st = knobInit(MIN);
    for (let i = 0; i < 4000 && st.value < MAX; i++) knobStep(st, meta, +1, 1000, false);
    near(st.value, MAX, 0, name + " must reach max exactly");
    /* and stay there */
    knobStep(st, meta, +1, 1000, false);
    near(st.value, MAX, 0, name + " must not overshoot max");
  }

  /* ---- 5. Monotonic, and no dead detents. ------------------------------ *
   * Every single detent must change the value. A curve that compresses the
   * bottom of the range is exactly where a detent can round to nothing and
   * read as a broken knob. */
  for (const [name, meta] of [["low", LOW], ["high", HIGH]]) {
    let st = knobInit(MIN);
    let prev = st.value, steps = 0;
    while (st.value < MAX && steps < 100000) {
      knobStep(st, meta, +1, 1000, false);
      steps++;
      ok(st.value > prev, name + " detent " + steps + " did not advance from " + prev);
      prev = st.value;
    }
    ok(steps >= 150 && steps <= 260,
       name + " must cross the range in roughly 200 detents, took " + steps);
    /* the coarsest detent is bounded by gamma -- the anti-runaway property */
    st = knobInit(MIN); prev = st.value; let worst = 0;
    while (st.value < MAX) {
      knobStep(st, meta, +1, 1000, false);
      worst = Math.max(worst, st.value - prev); prev = st.value;
    }
    const linearStep = (MAX - MIN) * MIN_STEP_RANGE_FRAC * ARC_DELTA_SCALE;
    ok(worst <= linearStep * 2 + 0.01,
       name + " coarsest detent " + worst.toFixed(2) + " exceeds gamma x linear");
  }

  /* ---- 6. Immediate reversal, with no discontinuity. ------------------- *
   * Move out and back the same number of detents and land where we began. */
  for (const [name, meta] of [["low", LOW], ["high", HIGH]]) {
    for (const start of [0, 3, 50, 347, 1000, 2500, 3990]) {
      const st = knobInit(start);
      /* A detent that lands ON an endpoint has clamped, and a clamp is
       * lossy by definition -- coming back cannot restore what was never
       * recorded. That is correct, so only an unsaturated run is asked to
       * be reversible. */
      let saturated = false;
      for (let i = 0; i < 7; i++) {
        if (knobStep(st, meta, +1, 1000, false) >= MAX) saturated = true;
      }
      const out = st.value;
      ok(out > start, name + " must move away from " + start);
      if (!saturated) {
        for (let i = 0; i < 7; i++) knobStep(st, meta, -1, 1000, false);
        near(st.value, start, 1e-6, name + " reversal must return to " + start + " from " + out);
      }
    }
    /* reversing mid-sweep costs exactly one detent -- no banking lag */
    const st = knobInit(1000);
    const up = knobStep(st, meta, +1, 1000, false);
    const back = knobStep(st, meta, -1, 1000, false);
    near(back, 1000, 1e-9, name + " reversal must be immediate");
  }

  /* ---- 7. Bipolar ranges. ---------------------------------------------- *
   * Normalisation is (v-min)/span, so a range that crosses zero must curve
   * about the declared centre, not about zero. */
  const bipolar = { type: "float", min: -100, max: 100, step: 0.1,
                    knob_curve: KNOB_CURVE_LOW_FOCUS, knob_curve_gamma: 2 };
  {
    let st = knobInit(-100);
    for (let i = 0; i < 4000 && st.value < 100; i++) knobStep(st, bipolar, +1, 1000, false);
    near(st.value, 100, 0, "bipolar must reach max exactly");
    st = knobInit(100);
    for (let i = 0; i < 4000 && st.value > -100; i++) knobStep(st, bipolar, -1, 1000, false);
    near(st.value, -100, 0, "bipolar must reach min exactly");
    /* a value either side of centre stays on its own side */
    ok(knobStep(knobInit(-1), bipolar, +1, 1000, false) > -1, "bipolar lower half must increase");
    ok(knobStep(knobInit(1), bipolar, -1, 1000, false) < 1, "bipolar upper half must decrease");
    /* and the fine end is the declared minimum, which is negative */
    near(curveYFromU(0, KNOB_CURVE_LOW_FOCUS, 2), 0, 0, "bipolar normalised floor is 0");
  }

  /* ---- 8. Shift fine. -------------------------------------------------- *
   * Fine is a predictable tenth of the coarse travel in control space, and
   * it must still move something. */
  for (const [name, meta] of [["low", LOW], ["high", HIGH]]) {
    for (const start of [0, 1, 50, 500, 2000, 3500]) {
      const coarse = knobStep(knobInit(start), meta, +1, 1000, false) - start;
      const fine = knobStep(knobInit(start), meta, +1, 1000, true) - start;
      ok(fine > 0, name + " fine must move at " + start);
      ok(fine < coarse + 1e-9, name + " fine must be finer than coarse at " + start);
    }
    /* ten fine detents travel about one coarse detent, near mid-range */
    const mid = 2000;
    let st = knobInit(mid);
    const oneCoarse = knobStep(knobInit(mid), meta, +1, 1000, false) - mid;
    for (let i = 0; i < 10; i++) knobStep(st, meta, +1, 1000, true);
    near(st.value - mid, oneCoarse, Math.max(0.02, oneCoarse * 0.25),
         name + " ten fine detents must approximate one coarse detent");
  }

  /* ---- 9. Nothing is NaN or infinite, ever. ---------------------------- *
   * Scoped to metadata that actually ENGAGES a curve: this is the new path,
   * and a curve is exactly where an out-of-range gamma or a NaN seed could
   * turn into a value written to the device. */
  const hostiles = [
    { type: "float", min: 0, max: 4000, knob_curve: KNOB_CURVE_LOW_FOCUS },
    { type: "float", min: 0, max: 4000, knob_curve: KNOB_CURVE_LOW_FOCUS, knob_curve_gamma: 0 },
    { type: "float", min: 0, max: 4000, knob_curve: KNOB_CURVE_LOW_FOCUS, knob_curve_gamma: -3 },
    { type: "float", min: 0, max: 4000, knob_curve: KNOB_CURVE_LOW_FOCUS, knob_curve_gamma: NaN },
    { type: "float", min: 0, max: 4000, knob_curve: KNOB_CURVE_LOW_FOCUS, knob_curve_gamma: 1e9 },
    { type: "float", min: 0, max: 4000, knob_curve: KNOB_CURVE_HIGH_FOCUS, knob_curve_gamma: Infinity },
    { type: "float", min: 0, max: 4000, knob_curve: KNOB_CURVE_LOW_FOCUS, knob_curve_gamma: "loud" },
  ];
  for (const meta of hostiles) {
    for (const start of [-1, 0, 2000, 4000, 4001, NaN]) {
      const st = knobInit(start);
      for (let i = 0; i < 5; i++) {
        knobStep(st, meta, +1, 1000, false);
        ok(isFinite(st.value), "value must stay finite for " + JSON.stringify(meta) + " from " + start);
        ok(st.value <= 4000.0000001 && st.value >= -0.0000001,
           "value must stay in range for " + JSON.stringify(meta) + " from " + start);
      }
      /* and back down again */
      const down = knobInit(start);
      for (let i = 0; i < 5; i++) {
        knobStep(down, meta, -1, 1000, false);
        ok(isFinite(down.value), "value must stay finite going down for " + JSON.stringify(meta));
      }
    }
  }
  /* An unrecognised curve name is not a curve: it must take the plain path
   * byte for byte, including the behaviour of the plain path itself on a
   * NaN seed (pre-existing, and out of scope to change here). */
  for (const start of [0, 500, 2000]) {
    near(knobStep(knobInit(start), floatMeta({ knob_curve: "nonsense", knob_curve_gamma: 2 }), +1, 1000, false),
         knobStep(knobInit(start), PLAIN, +1, 1000, false), 0,
         "an unrecognised curve name must behave exactly like no curve");
  }

  /* ---- 10. Invalid min/max falls back rather than misbehaving. -------- */
  const degenerate = [
    { type: "float", min: 0, max: 0, knob_curve: KNOB_CURVE_LOW_FOCUS },
    { type: "float", min: 10, max: 10, knob_curve: KNOB_CURVE_LOW_FOCUS },
    { type: "float", min: 100, max: 0, knob_curve: KNOB_CURVE_LOW_FOCUS },
    { type: "float", knob_curve: KNOB_CURVE_LOW_FOCUS },
  ];
  for (const meta of degenerate) {
    const st = knobInit(5);
    const v = knobStep(st, meta, +1, 1000, false);
    ok(isFinite(v), "degenerate range must stay finite: " + JSON.stringify(meta));
  }
  /* NaN gamma is treated as the default, not as linear */
  near(knobCurveGamma({ knob_curve_gamma: NaN }), 2, 0, "NaN gamma must fall back to the default");
  near(knobCurveGamma({}), 2, 0, "absent gamma must fall back to the default");
  near(knobCurveGamma({ knob_curve_gamma: 1e9 }), 8, 0, "absurd gamma must clamp to the max");
  near(knobCurveGamma({ knob_curve_gamma: -5 }), 1, 0, "negative gamma must clamp to the min");

  /* ---- 11. Enums and wide acceleration are untouched. ------------------ */
  const enumMeta = { kind: "enum", type: "enum", options: ["a", "b", "c", "d"],
                     knob_curve: KNOB_CURVE_LOW_FOCUS, knob_curve_gamma: 2 };
  {
    ok(knobStep(knobInit(0), enumMeta, +1, 1000, false) === 0, "enum gate is unchanged");
    let st = knobInit(0);
    for (let i = 0; i < 4; i++) knobStep(st, enumMeta, +1, 1000, false);
    ok(st.value === 1, "enum still needs four detents per option");
  }
  const wideMeta = { type: "float", min: 0, max: 4000, step: 1, knobAcceleration: "wide",
                     knob_curve: KNOB_CURVE_LOW_FOCUS, knob_curve_gamma: 2 };
  {
    const st = knobInit(100);
    const fast = knobStep(st, wideMeta, -1, 0, false);
    ok(fast <= 100, "wide acceleration keeps its own branch");
    const st2 = knobInit(100);
    for (let i = 0; i < 6; i++) knobStep(st2, wideMeta, -1, i * 10, false);
    ok(st2.value < 100 - 5 * 4, "wide acceleration still accelerates");
  }

  /* ---- 12. Declared-step and curves are mutually exclusive. ------------ */
  const both = floatMeta({ knob_step_mode: KNOB_STEP_MODE_DECLARED,
                           knob_curve: KNOB_CURVE_LOW_FOCUS, knob_curve_gamma: 2 });
  ok(knobCurveMode(both) === null,
     "declared-step must win outright over a curve, not blend with it");
  ok(knobCurveMode(floatMeta({ knob_curve: KNOB_CURVE_LOW_FOCUS })) === KNOB_CURVE_LOW_FOCUS,
     "a curve with no declared step is still a curve");
  ok(knobCurveMode(PLAIN) === null, "no curve declared means no curve");
  ok(knobCurveMode(null) === null, "absent metadata means no curve");

  /* ---- 13. Int knobs curve, but never go dead. ------------------------- */
  const intMeta = { type: "int", min: 0, max: 4000, step: 1,
                    knob_curve: KNOB_CURVE_LOW_FOCUS, knob_curve_gamma: 2 };
  {
    let st = knobInit(0), prev = st.value, steps = 0;
    while (st.value < 4000 && steps < 100000) {
      knobStep(st, intMeta, +1, 1000, false);
      steps++;
      ok(Number.isInteger(st.value), "int curve value must stay integral");
      ok(st.value > prev, "int curve detent " + steps + " went dead at " + prev);
      prev = st.value;
    }
    ok(st.value === 4000, "int curve must reach max exactly");
    /* and it can come all the way back */
    while (st.value > 0) knobStep(st, intMeta, -1, 1000, false);
    ok(st.value === 0, "int curve must reach min exactly");
  }

  /* ---- 14. Metadata is never mutated. ---------------------------------- *
   * knobStep synthesises a missing range on a COPY; the caller meta that
   * came off chain_params must come back out untouched. */
  {
    const frozen = Object.freeze({ type: "float", min: 0, max: 4000,
                                   knob_curve: KNOB_CURVE_LOW_FOCUS, knob_curve_gamma: 2 });
    const before = JSON.stringify(frozen);
    knobStep(knobInit(100), frozen, +1, 1000, false);
    knobStep(knobInit(100), frozen, +1, 1000, true);
    ok(JSON.stringify(frozen) === before, "knobStep must not mutate its metadata");
    /* and a missing range is filled in without touching the original */
    const partial = Object.freeze({ type: "float", knob_curve: KNOB_CURVE_HIGH_FOCUS });
    const st = knobInit(0.5);
    const v = knobStep(st, partial, +1, 1000, false);
    ok(isFinite(v), "missing min/max must be synthesised, not produce NaN");
    ok(partial.min === undefined && partial.max === undefined,
       "synthesising a range must not write it back to the caller");
  }

  console.log("knob response curves: " + checks + " checks passed");
}).catch((e) => { console.log("FAIL: " + (e && e.message ? e.message : e)); process.exit(1); });
'
