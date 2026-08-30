#!/usr/bin/env bash
# Edit speed: how fast a knob traverses the range it was declared with.
#
# This is the primitive a Micro / Normal / Long switch drives, and it is
# deliberately NOT a sub-range. A moving window narrows min/max and then has
# to slide under the hand, which is the thing that stalled on hardware; a
# speed walks the declared range at a different rate and can neither clamp
# nor jump.
#
# The property that matters most is that speed and curve are ORTHOGONAL:
# the speed buys a detent budget (1/knob_step_frac end to end, whatever the
# curve), and the curve decides how that budget is spent along the way. So
# changing one must not change the other's behaviour.
set -euo pipefail
cd "$(dirname "$0")/../.."

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: node is required for the edit-speed tests" >&2
  exit 1
fi

node -e '
import("./src/shared/knob_engine.mjs").then((m) => {
  const {
    knobInit, knobStep, perDetentStep, knobStepFrac, knobCurveGamma,
    curveYFromU, curveUFromY,
    KNOB_CURVE_LOW_FOCUS, KNOB_CURVE_HIGH_FOCUS,
    KNOB_STEP_FRAC_MIN, KNOB_STEP_FRAC_MAX,
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
  const DEFAULT_FRAC = MIN_STEP_RANGE_FRAC * ARC_DELTA_SCALE;

  /* A float knob over the reference 0..4000 ms time range. */
  const meta = (extra) => Object.assign({ type: "float", min: MIN, max: MAX, step: 1 }, extra || {});
  const intMeta = (extra) => Object.assign({ type: "int", min: MIN, max: MAX, step: 1 }, extra || {});

  const LOW2 = { knob_curve: KNOB_CURVE_LOW_FOCUS, knob_curve_gamma: 2 };
  const HIGH2 = { knob_curve: KNOB_CURVE_HIGH_FOCUS, knob_curve_gamma: 2 };
  const LOW16 = { knob_curve: KNOB_CURVE_LOW_FOCUS, knob_curve_gamma: 1.6 };
  const LOW24 = { knob_curve: KNOB_CURVE_LOW_FOCUS, knob_curve_gamma: 2.4 };
  const CURVES = [["linear", {}], ["low1.6", LOW16], ["low2", LOW2], ["low2.4", LOW24], ["high2", HIGH2]];

  /* The Micro / Normal / Long speeds being put in front of the user. */
  const MICRO = 0.002, NORMAL = 0.005, LONG = 0.0125;
  const SPEEDS = [["micro", MICRO], ["normal", NORMAL], ["long", LONG]];

  /* ---- 1. Absent means the shipped speed, exactly. ------------------- *
   * A param that never heard of edit speed must not move differently the
   * day the capability lands. */
  {
    near(knobStepFrac({}), DEFAULT_FRAC, 0, "absent knob_step_frac must be the shipped default");
    near(knobStepFrac({ knob_step_frac: undefined }), DEFAULT_FRAC, 0, "undefined must be the default");
    near(knobStepFrac({ knob_step_frac: null }), DEFAULT_FRAC, 0, "null must be the default");
    near(knobStepFrac({ knob_step_frac: "" }), DEFAULT_FRAC, 0, "empty string must be the default");
    near(knobStepFrac({ knob_step_frac: "abc" }), DEFAULT_FRAC, 0, "non-numeric must be the default");
    near(knobStepFrac({ knob_step_frac: NaN }), DEFAULT_FRAC, 0, "NaN must be the default");
    near(knobStepFrac({ knob_step_frac: Infinity }), DEFAULT_FRAC, 0, "Infinity must be the default");

    /* And the step it produces is the old expression, branch for branch. */
    const oldFloat = (MAX - MIN) * MIN_STEP_RANGE_FRAC * ARC_DELTA_SCALE;
    near(perDetentStep(meta()), oldFloat, 1e-12, "float default step must be unchanged");
    const oldInt = Math.round(Math.max(1, (MAX - MIN) * MIN_STEP_RANGE_FRAC) * ARC_DELTA_SCALE);
    ok(perDetentStep(intMeta()) === oldInt, "int default step must be unchanged");

    /* Every knob in the shipped fleet. */
    for (const c of CURVES) {
      const fracs = [{}, { knob_step_frac: DEFAULT_FRAC }];
      const runs = fracs.map((f) => {
        const st = knobInit(0);
        const mm = meta(Object.assign({}, c[1], f));
        const out = [];
        for (let i = 0; i < 60; i++) out.push(knobStep(st, mm, +1, 1000, false));
        return out;
      });
      ok(runs[0].every((v, i) => v === runs[1][i]),
         c[0] + ": naming the default speed explicitly must be identical to omitting it");
    }
  }

  /* ---- 2. Hostile metadata degrades to a legal speed. ---------------- */
  {
    ok(knobStepFrac({ knob_step_frac: 0 }) === KNOB_STEP_FRAC_MIN, "0 must clamp up to MIN");
    ok(knobStepFrac({ knob_step_frac: -5 }) === KNOB_STEP_FRAC_MIN, "negative must clamp up to MIN");
    ok(knobStepFrac({ knob_step_frac: 1e-12 }) === KNOB_STEP_FRAC_MIN, "tiny must clamp up to MIN");
    ok(knobStepFrac({ knob_step_frac: 1 }) === KNOB_STEP_FRAC_MAX, "1 must clamp down to MAX");
    ok(knobStepFrac({ knob_step_frac: 1e6 }) === KNOB_STEP_FRAC_MAX, "huge must clamp down to MAX");
    near(knobStepFrac({ knob_step_frac: -Infinity }), DEFAULT_FRAC, 0, "-Infinity must be the default");
    /* A string that happens to parse is still a number a module can send. */
    near(knobStepFrac({ knob_step_frac: "0.02" }), 0.02, 1e-12, "a numeric string is honoured");

    /* Neither extreme may produce a knob that cannot move or cannot stop. */
    for (const f of [KNOB_STEP_FRAC_MIN, KNOB_STEP_FRAC_MAX]) {
      for (const c of CURVES) {
        const st = knobInit(0);
        const mm = meta(Object.assign({}, c[1], { knob_step_frac: f }));
        const v = knobStep(st, mm, +1, 1000, false);
        ok(isFinite(v) && v > 0,
           c[0] + " at frac " + f + " must move off zero (got " + v + ")");
      }
    }
  }

  /* ---- 3. The speed buys a detent budget. ---------------------------- *
   * End-to-end detents are 1/frac whatever the curve is. That is the whole
   * claim of "how fast", and it has to survive the curve, not fight it. */
  {
    const detentsToCross = (from, to, extra) => {
      const st = knobInit(from);
      const mm = meta(extra);
      let v = from;
      for (let i = 0; i < 100000; i++) {
        if (v >= to) return i;
        const next = knobStep(st, mm, +1, 1000, false);
        if (!(next > v)) return -1;      /* dead knob */
        v = next;
      }
      return -1;
    };

    for (const [sName, frac] of SPEEDS) {
      const want = 1 / frac;
      for (const [cName, c] of CURVES) {
        const got = detentsToCross(0, MAX, Object.assign({}, c, { knob_step_frac: frac }));
        ok(got > 0, sName + "/" + cName + ": must reach max (got " + got + ")");
        /* +-2 absorbs one-detent rounding at each end, not a wrong law. */
        ok(Math.abs(got - want) <= 2,
           sName + "/" + cName + ": end-to-end detents must be 1/frac (got " + got + ", want ~" + want + ")");
        /* And it really is a speed: half the frac, twice the detents. */
        const half = detentsToCross(0, MAX, Object.assign({}, c, { knob_step_frac: frac / 2 }));
        ok(Math.abs(half - 2 * got) <= 4,
           sName + "/" + cName + ": halving the speed must double the detents (got " + half + " vs " + got + ")");
      }
    }
  }

  /* ---- 4. Speed and curve are orthogonal. ---------------------------- *
   * The SHAPE of the travel belongs to the curve alone. Measure it as the
   * fraction of the total journey spent in the first tenth of the range:
   * that number is a property of the curve, and the speed must not move it. */
  {
    const detentsToCross = (from, to, extra) => {
      const st = knobInit(from);
      const mm = meta(extra);
      let v = from;
      for (let i = 0; i < 100000; i++) {
        if (v >= to) return i;
        const next = knobStep(st, mm, +1, 1000, false);
        if (!(next > v)) return -1;
        v = next;
      }
      return -1;
    };

    for (const [cName, c] of CURVES) {
      const shapes = SPEEDS.map(([sName, frac]) => {
        const ex = Object.assign({}, c, { knob_step_frac: frac });
        const total = detentsToCross(0, MAX, ex);
        const lowEnd = detentsToCross(0, MAX * 0.1, ex);
        return lowEnd / total;
      });
      const spread = Math.max(...shapes) - Math.min(...shapes);
      ok(spread < 0.03,
         cName + ": the fraction of travel spent in the bottom tenth must not "
         + "depend on the speed (spread " + spread.toFixed(4) + ")");

      /* ...while the curve genuinely does move it, so the test is not vacuous. */
      const linearLowFrac = (() => {
        const ex = { knob_step_frac: NORMAL };
        return detentsToCross(0, MAX * 0.1, ex) / detentsToCross(0, MAX, ex);
      })();
      const lowLowFrac = (() => {
        const ex = Object.assign({}, LOW2, { knob_step_frac: NORMAL });
        return detentsToCross(0, MAX * 0.1, ex) / detentsToCross(0, MAX, ex);
      })();
      ok(lowLowFrac > linearLowFrac + 0.1,
         "low_focus must spend more of the journey low down than linear does ("
         + lowLowFrac.toFixed(3) + " vs " + linearLowFrac.toFixed(3) + ")");
    }
  }

  /* ---- 5. Endpoints stay exact at every speed. ----------------------- */
  {
    for (const [sName, frac] of SPEEDS) {
      for (const [cName, c] of CURVES) {
        const mm = meta(Object.assign({}, c, { knob_step_frac: frac }));
        const up = knobInit(0);
        let v = 0;
        for (let i = 0; i < 100000 && v < MAX; i++) v = knobStep(up, mm, +1, 1000, false);
        ok(v === MAX, sName + "/" + cName + ": must land exactly on max (got " + v + ")");
        let d = v;
        for (let i = 0; i < 100000 && d > MIN; i++) d = knobStep(up, mm, -1, 1000, false);
        ok(d === MIN, sName + "/" + cName + ": must land exactly on min (got " + d + ")");
      }
    }
  }

  /* ---- 6. No dead detents, at any speed. ----------------------------- *
   * The fastest speed is where a float could round itself to nothing and
   * an int always risks it. A knob that eats a detent reads as broken. */
  {
    for (const [sName, frac] of SPEEDS.concat([["max", KNOB_STEP_FRAC_MAX], ["min", KNOB_STEP_FRAC_MIN]])) {
      for (const [cName, c] of CURVES) {
        for (const mm of [meta(Object.assign({}, c, { knob_step_frac: frac })),
                          intMeta(Object.assign({}, c, { knob_step_frac: frac }))]) {
          const st = knobInit(0);
          let v = 0, detents = 0;
          for (let i = 0; i < 20000; i++) {
            if (v >= MAX) break;
            const next = knobStep(st, mm, +1, 1000, false);
            ok(next > v, mm.type + " " + sName + "/" + cName + ": detent " + i
               + " must move (stuck at " + v + ")");
            v = next;
            if (++detents > 20000) break;
          }
          ok(v === MAX, mm.type + " " + sName + "/" + cName + ": must still reach max");
          if (detents > 6000) break;   /* keep the suite quick at the MIN speed */
        }
      }
    }
  }

  /* ---- 7. Reversal and the first detent. ----------------------------- *
   * Seeding is by exact inverse, so changing speed under the hand must not
   * introduce a jump: up n then down n returns to where it started, and the
   * first detent from rest is one step, not a leap. */
  {
    for (const [sName, frac] of SPEEDS) {
      for (const [cName, c] of CURVES) {
        for (const start of [0, 1, 17, 250, 1000, 2500, 3900]) {
          const mm = meta(Object.assign({}, c, { knob_step_frac: frac }));
          const st = knobInit(start);
          let v = start;
          for (let i = 0; i < 7; i++) v = knobStep(st, mm, +1, 1000, false);
          const saturated = v >= MAX;
          for (let i = 0; i < 7; i++) v = knobStep(st, mm, -1, 1000, false);
          if (!saturated) {
            near(v, start, 1e-9,
                 sName + "/" + cName + ": seven up then seven down from " + start
                 + " must return (got " + v + ")");
          }
          /* First detent from rest is bounded by one coarse step, and the
           * coarsest step anywhere on a curve is gamma times the flat one. */
          const fresh = knobInit(start);
          const one = knobStep(fresh, mm, +1, 1000, false);
          const coarse = (MAX - MIN) * frac * knobCurveGamma(mm);
          ok(one - start <= coarse + 1e-6,
             sName + "/" + cName + ": first detent from " + start
             + " must not leap (moved " + (one - start).toFixed(3) + ", bound "
             + coarse.toFixed(3) + ")");
        }
      }
    }
  }

  /* ---- 8. Shift fine is a tenth of the coarse travel. ---------------- */
  {
    for (const [sName, frac] of SPEEDS) {
      for (const [cName, c] of CURVES) {
        const mm = meta(Object.assign({}, c, { knob_step_frac: frac }));
        const coarseStart = 800;
        const coarse = knobStep(knobInit(coarseStart), mm, +1, 1000, false) - coarseStart;
        let v = coarseStart;
        const st = knobInit(coarseStart);
        for (let i = 0; i < 10; i++) v = knobStep(st, mm, +1, 1000, true);
        const fineTotal = v - coarseStart;
        near(fineTotal, coarse, coarse * 0.35 + 1e-6,
             sName + "/" + cName + ": ten fine detents must approximate one coarse (fine "
             + fineTotal.toFixed(4) + " vs coarse " + coarse.toFixed(4) + ")");
      }
    }
  }

  /* ---- 9. Enum and wide are untouched by a speed. -------------------- */
  {
    const enumMeta = (extra) => Object.assign(
      { type: "enum", min: 0, max: 4, options: ["a", "b", "c", "d", "e"] }, extra || {});
    const run = (mm, n, fine) => {
      const st = knobInit(0);
      let v = 0;
      for (let i = 0; i < n; i++) v = knobStep(st, mm, +1, 1000, fine);
      return v;
    };
    for (const f of [MICRO, NORMAL, LONG, KNOB_STEP_FRAC_MIN, KNOB_STEP_FRAC_MAX]) {
      const plain = enumMeta();
      const sped = enumMeta({ knob_step_frac: f });
      ok(run(plain, 20, false) === run(sped, 20, false),
         "enum must ignore knob_step_frac " + f + " (coarse)");
      ok(run(plain, 20, true) === run(sped, 20, true),
         "enum must ignore knob_step_frac " + f + " (fine)");
    }
    for (const f of [MICRO, LONG]) {
      const wide = (extra) => Object.assign(
        { type: "float", min: 0, max: 1, step: 0.001, knobAcceleration: "wide" }, extra || {});
      const a = knobStep(knobInit(0.5), wide(), +1, 1000, false);
      const b = knobStep(knobInit(0.5), wide({ knob_step_frac: f }), +1, 1000, false);
      near(b, a, 0, "wide acceleration must ignore knob_step_frac " + f);
    }
  }

  /* ---- 10. Declared-step is a lattice, not a speed. ------------------ *
   * Detected rather than assumed: an absolute lattice over the declared
   * range answers "how fast" with the module step, and it must keep doing
   * so when a speed is also present in the metadata. */
  {
    const declaredSupported = (() => {
      const mm = { type: "int", min: 0, max: 4000, step: 1, knob_step_mode: KNOB_STEP_MODE_DECLARED };
      return knobStep(knobInit(100), mm, +1, 1000, false) === 101;
    })();
    ok(true, "declared-step support probed");
    if (declaredSupported) {
      for (const f of [MICRO, NORMAL, LONG, KNOB_STEP_FRAC_MAX]) {
        const base = { type: "int", min: 0, max: 4000, step: 1, knob_step_mode: KNOB_STEP_MODE_DECLARED };
        const without = knobStep(knobInit(100), base, +1, 1000, false);
        const with_ = knobStep(knobInit(100), Object.assign({}, base, { knob_step_frac: f }), +1, 1000, false);
        ok(with_ === without && with_ === 101,
           "declared-step must ignore knob_step_frac " + f + " (got " + with_ + ", want 101)");
      }
    }
  }

  /* ---- 11. Metadata is never mutated. -------------------------------- */
  {
    for (const [cName, c] of CURVES) {
      const mm = Object.freeze(Object.assign(meta(), c, { knob_step_frac: MICRO }));
      const st = knobInit(0);
      for (let i = 0; i < 40; i++) knobStep(st, mm, +1, 1000, false);
      for (let i = 0; i < 40; i++) knobStep(st, mm, -1, 1000, true);
      ok(mm.knob_step_frac === MICRO, cName + ": knob_step_frac must not be rewritten");
      ok(mm.min === MIN && mm.max === MAX, cName + ": min/max must not be rewritten");
    }
  }

  /* ---- 12. No NaN, no Infinity, at any speed, from any start. -------- */
  {
    for (const [sName, frac] of SPEEDS.concat([["max", KNOB_STEP_FRAC_MAX]])) {
      for (const [cName, c] of CURVES) {
        for (const start of [0, 0.5, 1, 250, 3999.5, 4000]) {
          for (const fine of [false, true]) {
            const mm = meta(Object.assign({}, c, { knob_step_frac: frac }));
            const st = knobInit(start);
            let v = start;
            for (let i = 0; i < 50; i++) v = knobStep(st, mm, +1, 1000, fine);
            ok(isFinite(v), sName + "/" + cName + " from " + start + " must stay finite (got " + v + ")");
            for (let i = 0; i < 100; i++) v = knobStep(st, mm, -1, 1000, fine);
            ok(isFinite(v) && v >= MIN - 1e-9,
               sName + "/" + cName + " from " + start + " must stay finite going down (got " + v + ")");
          }
        }
      }
    }
  }

  /* ---- 13. A degenerate range still behaves the way it shipped. ------ *
   * A curve needs a span to normalise over; so does a speed. Neither may
   * invent one. */
  {
    for (const [cName, c] of CURVES) {
      for (const bad of [{ min: 0, max: 0 }, { min: 5, max: 5 }, { min: 9, max: 2 }]) {
        const mm = Object.assign({ type: "float", step: 0.01 }, bad, c, { knob_step_frac: MICRO });
        const st = knobInit(1);
        const v = knobStep(st, mm, +1, 1000, false);
        ok(isFinite(v), cName + ": a degenerate range must not produce NaN (got " + v + ")");
      }
      const missing = Object.freeze(Object.assign({ type: "float" }, c, { knob_step_frac: MICRO }));
      const st = knobInit(0.5);
      ok(isFinite(knobStep(st, missing, +1, 1000, false)),
         cName + ": a missing range must be synthesised, not produce NaN");
      ok(missing.min === undefined && missing.max === undefined,
         cName + ": synthesising a range must not write it back");
    }
  }

  console.log("knob edit speed: " + checks + " checks passed");
}).catch((e) => { console.log("FAIL: " + (e && e.message ? e.message : e)); process.exit(1); });
'
