#!/usr/bin/env bash
# TEMPO LANDMARKS — an INFORMATION LAYER over a free time parameter.
#
# The load-bearing claim is what this is NOT: it is not tempo sync. The
# parameter stays completely free — no quantise, no pull, no snap, no block,
# and no change to knob motion. Tempo only decides whether the screen has a
# rhythmic landmark worth printing beside the value, so the user can sit
# before it, on it, or after it.
#
# So the tests pin the arithmetic hard (it is the part that can be wrong
# quietly) and then pin the absence of everything else: no writes, no snap,
# no second copy of the maths in a renderer.
set -euo pipefail
cd "$(dirname "$0")/../.."

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: node is required for the tempo-landmark tests" >&2
  exit 1
fi

static_failures=0

# ---------------------------------------------------------------------------
# ONE MODEL, and no renderer does its own musical arithmetic.
#
# The grid header and the list row must agree because they ask the same
# helper, not because two copies of a formula happen to match. A second
# "60000 / bpm" in a draw path is how they stop agreeing.
# ---------------------------------------------------------------------------
n=$( { command grep -rln "60000" src/shared/param_pages/ || true; } | wc -l | tr -d ' ')
if [ "$n" != "1" ]; then
  echo "FAIL: BPM arithmetic appears in ${n} files under src/shared/param_pages/, expected only tempo_landmarks.mjs"
  command grep -rln "60000" src/shared/param_pages/ || true
  static_failures=$((static_failures + 1))
fi

if ! command grep -q "withLandmark" src/shared/param_pages/page_controller.mjs; then
  echo "FAIL: page_controller.mjs does not use the shared withLandmark helper"
  static_failures=$((static_failures + 1))
fi

# The renderer receives a string; it must not compute one. (The bare word
# "tempo" legitimately appears there already, about drawing a BPM param as a
# number rather than a dial -- so this names the LANDMARK machinery, not the
# concept of tempo.)
if command grep -qi "landmark\|60000\|quarterMs\|beatMs" src/shared/param_pages/render_page_movy.mjs; then
  echo "FAIL: render_page_movy.mjs computes landmarks; it must render the string it is given"
  command grep -ni "landmark\|60000\|quarterMs\|beatMs" src/shared/param_pages/render_page_movy.mjs || true
  static_failures=$((static_failures + 1))
fi

# A landmark layer that can write is a snap waiting to be switched on.
if command grep -q "setParam\|set_param" src/shared/param_pages/tempo_landmarks.mjs; then
  echo "FAIL: tempo_landmarks.mjs can write; it is an information layer only"
  static_failures=$((static_failures + 1))
fi

if [ "$static_failures" != "0" ]; then
  echo "FAIL: ${static_failures} static tempo-landmark check(s) failed" >&2
  exit 1
fi

node -e '
import("./src/shared/param_pages/tempo_landmarks.mjs").then(async (m) => {
  const {
    landmarkSet, nearestLandmark, landmarkSuffix, withLandmark,
    formatLandmark, landmarkEnabled, quarterMs, LANDMARK_RELEVANCE,
    BAR_COUNTS, STRAIGHT_DENOMS,
  } = m;
  const { knobStep, knobInit } = await import("./src/shared/knob_engine.mjs");

  let checks = 0;
  const fail = (msg) => { console.log("FAIL: " + msg); process.exit(1); };
  const ok = (c, msg) => { checks++; if (!c) fail(msg); };
  const eq = (a, b, msg) => { checks++; if (a !== b) fail(msg + " (got " + JSON.stringify(a) + ", want " + JSON.stringify(b) + ")"); };
  const near = (a, b, tol, msg) => { checks++; if (!(Math.abs(a - b) <= tol)) fail(msg + " (got " + a + ", want " + b + ")"); };

  const MS = { type: "float", min: 0, max: 40000, step: 1, unit: "ms", tempo_landmarks: true };
  const hint = (v, bpm, meta) => landmarkSuffix(v, meta || MS, bpm);
  const full = (v, bpm, meta) => nearestLandmark(v, meta || MS, bpm);

  /* ---- 1. Canonical durations at 120 BPM. ---------------------------- */
  near(quarterMs(120), 500, 1e-9, "a quarter at 120 BPM is 500 ms");
  near(quarterMs(60), 1000, 1e-9, "a quarter at 60 BPM is 1000 ms");
  const at120 = {};
  for (const l of landmarkSet(120)) at120[l.label] = l.ms;
  near(at120["1/4"], 500, 1e-6, "1/4 at 120 BPM");
  near(at120["1/8"], 250, 1e-6, "1/8 at 120 BPM");
  near(at120["1/16"], 125, 1e-6, "1/16 at 120 BPM");
  near(at120["1/2"], 1000, 1e-6, "1/2 at 120 BPM");
  near(at120["1/8T"], 250 * 2 / 3, 1e-6, "1/8T is two thirds of 1/8");
  near(at120["1/8D"], 250 * 3 / 2, 1e-6, "1/8D is one and a half of 1/8");

  /* ---- 2. Triplet aliases are the SAME landmark, drawn once. ---------- *
   * 1/12 of a whole note IS 1/8T. Two markers for one point in time would
   * be two different labels claiming the same millisecond. */
  for (const [trip, alias] of [["1/2T", "1/3"], ["1/4T", "1/6"], ["1/8T", "1/12"], ["1/16T", "1/24"]]) {
    const t = landmarkSet(120).find((l) => l.label === trip);
    ok(!!t, trip + " must exist");
    ok(t.aliases.indexOf(alias) >= 0, trip + " must carry the rational alias " + alias);
    /* and the alias is not a second entry in the set */
    ok(!landmarkSet(120).some((l) => l.label === alias),
       alias + " must NOT be a separate landmark from " + trip);
    /* the alias names the same duration: whole/denominator */
    near(t.ms, 4 * 60000 / 120 / Number(alias.split("/")[1]), 1e-6,
         alias + " of a whole note must equal " + trip);
  }
  /* No two landmarks share a duration. */
  {
    const seen = new Map();
    for (const l of landmarkSet(120)) {
      const k = l.ms.toFixed(6);
      ok(!seen.has(k), "duplicate duration: " + l.label + " and " + seen.get(k) + " are the same point in time");
      seen.set(k, l.label);
    }
    /* 1 bar and the straight 1/1 are the same whole note; the BAR spelling
     * is the one that survives, because for a duration that long the phrase
     * is what is being counted. */
    ok(!landmarkSet(120).some((l) => l.label === "1/1"),
       "1/1 must be canonicalised to 1 bar, not drawn twice");
    near(at120["1 bar"], 2000, 1e-6, "1 bar at 120 BPM is one whole note");
  }

  /* ---- 3. Dotted is DIFFERENT from triplet. --------------------------- */
  ok(at120["1/8D"] !== at120["1/8T"], "dotted and triplet must not collapse");
  ok(at120["1/8D"] > at120["1/8"], "dotted must be LONGER than the straight value");
  ok(at120["1/8T"] < at120["1/8"], "triplet must be SHORTER than the straight value");
  /* 375 ms reads as 1/8D, not as anything else */
  eq(hint(375, 120), "1/8D", "375 ms at 120 BPM is exactly 1/8D");
  eq(hint(166.6667, 120), "1/8T", "166.67 ms at 120 BPM reads as 1/8T");

  /* ---- 4. Offsets: before, on, after. -------------------------------- */
  eq(hint(250, 120), "1/8", "exactly on a landmark shows it bare");
  eq(hint(247, 120), "1/8 -3", "before a landmark shows a negative offset");
  eq(hint(257, 120), "1/8 +7", "after a landmark shows a positive offset");
  {
    const before = full(247, 120), on = full(250, 120), after = full(257, 120);
    ok(before.offsetMs < 0, "a shorter value is a negative offset");
    ok(after.offsetMs > 0, "a longer value is a positive offset");
    eq(on.offsetMs, 0, "on the landmark the offset is zero");
    ok(on.exact === true, "on the landmark is exact");
    ok(before.exact === false && after.exact === false, "off the landmark is not exact");
    /* the sign must flip correctly either side */
    ok(full(249, 120).offsetMs === -1 && full(251, 120).offsetMs === 1,
       "offset sign must change correctly across the landmark");
  }

  /* ---- 5. Tempo moves the landmarks; the value does not. -------------- *
   * Same number, different musical meaning at a different tempo. */
  eq(hint(500, 120), "1/4", "500 ms is 1/4 at 120 BPM");
  eq(hint(500, 60), "1/8", "500 ms is 1/8 at 60 BPM");
  eq(hint(250, 120), "1/8", "250 ms is 1/8 at 120 BPM");
  eq(hint(250, 140), null, "250 ms is not near any landmark at 140 BPM");
  /* and the whole set scales with tempo */
  {
    const slow = landmarkSet(60).find((l) => l.label === "1/4").ms;
    const fast = landmarkSet(120).find((l) => l.label === "1/4").ms;
    near(slow, fast * 2, 1e-6, "halving the tempo doubles every duration");
  }

  /* ---- 6. Relevance is PROPORTIONAL, not a fixed tolerance. ----------- *
   * A flat +-10 ms would be most of a 1/64 and invisible on a 16-bar
   * phrase. The zone is a share of the landmark OWN length. */
  eq(hint(131, 120), "1/16 +6", "6 ms is inside a 125 ms landmark zone");
  eq(hint(132, 120), null, "7 ms is outside a 125 ms landmark zone");
  eq(hint(2100, 120), "1 bar +100", "100 ms is inside a 2000 ms landmark zone");
  eq(hint(2150, 120), null, "150 ms is outside a 2000 ms landmark zone");
  eq(hint(16, 120), "1/128", "a sub-millisecond offset on a 15.6 ms landmark reads as exact");
  eq(hint(17, 120), null, "1.4 ms is already outside a 15.6 ms landmark zone");
  eq(LANDMARK_RELEVANCE, 0.05, "the relevance share is pinned, so the table above stays true");

  /* ---- 7. Long-form bars, including the non-binary ones. -------------- */
  for (const n of [1, 2, 3, 4, 6, 8, 12, 16, 24, 32]) {
    const lab = n === 1 ? "1 bar" : n + " bars";
    ok(BAR_COUNTS.indexOf(n) >= 0, "bar count " + n + " must be in the set");
    const l = landmarkSet(120).find((x) => x.label === lab);
    ok(!!l, lab + " must exist");
    near(l.ms, n * 2000, 1e-6, lab + " at 120 BPM");
    eq(hint(n * 2000, 120), lab, "sitting exactly on " + lab);
  }
  /* the non-binary counts are the reason the set is not powers of two */
  for (const n of [3, 6, 12, 24]) {
    eq(hint(n * 2000, 120), n + " bars", n + " bars must be reachable as a landmark");
  }

  /* ---- 8. No tempo, no landmark. -------------------------------------- *
   * Unavailable is HIDDEN, never guessed and never defaulted to 120. */
  for (const bad of [null, undefined, 0, -1, NaN, Infinity, "120", ""]) {
    eq(hint(250, bad), null, "tempo " + String(bad) + " must hide the landmark");
  }
  ok(landmarkSet(null) === null, "no tempo means no landmark set");
  /* A STOPPED transport still has a tempo, and the landmark still means
   * something: 250 ms is an eighth whether or not anything is playing.
   * There is no transport concept in here at all -- only a number. */
  eq(hint(250, 120), "1/8", "a known tempo works regardless of transport state");

  /* ---- 9. Opt-in, and unit-aware. ------------------------------------- *
   * A unit of ms is NOT consent: most millisecond params are envelopes,
   * smoothing times and fades, and none of them are notes. */
  eq(landmarkEnabled({ tempo_landmarks: true }), true, "the flag opts in");
  eq(landmarkEnabled({ unit: "ms" }), false, "unit ms alone must NOT enable landmarks");
  eq(landmarkEnabled({}), false, "no flag means no landmarks");
  eq(landmarkEnabled(null), false, "absent metadata means no landmarks");
  eq(hint(250, 120, { unit: "ms" }), null, "a plain ms param shows nothing");
  /* seconds are converted, not read as milliseconds */
  {
    const sec = { type: "float", min: 0, max: 40, step: 0.001, unit: "sec", tempo_landmarks: true };
    eq(hint(0.25, 120, sec), "1/8", "0.25 sec is 1/8 at 120 BPM");
    eq(hint(0.247, 120, sec), "1/8 -3", "0.247 sec is 1/8 -3");
  }
  /* and a non-numeric value is not a landmark either */
  eq(hint("", 120), null, "an unread value shows nothing");
  eq(hint("--", 120), null, "the unread placeholder shows nothing");
  eq(hint(NaN, 120), null, "NaN shows nothing");
  eq(hint(null, 120), null, "null shows nothing");

  /* ---- 10. NO SNAP: the knob does not know landmarks exist. ----------- *
   * Identical detents with and without the flag. This is the whole
   * distinction from tempo sync. */
  {
    const plain = { type: "float", min: 0, max: 4000, step: 1 };
    const flagged = { type: "float", min: 0, max: 4000, step: 1, tempo_landmarks: true };
    for (const start of [0, 1, 247, 250, 253, 1000, 3999]) {
      for (const fine of [false, true]) {
        const a = knobInit(start), b = knobInit(start);
        for (let i = 0; i < 5; i++) {
          knobStep(a, plain, +1, 1000, fine);
          knobStep(b, flagged, +1, 1000, fine);
        }
        eq(b.value, a.value, "a landmark must not alter knob motion from " + start);
      }
    }
    /* and it certainly does not pull a value onto a landmark */
    eq(knobStep(knobInit(247), flagged, 0, 1000, false), 247, "no detent means no movement at all");
  }

  /* ---- 11. No writes, and metadata is never mutated. ------------------ *
   * Rendering a landmark must be a pure read of things already known. */
  {
    const frozen = Object.freeze({ type: "float", unit: "ms", min: 0, max: 4000,
                                   tempo_landmarks: true });
    const before = JSON.stringify(frozen);
    const r1 = nearestLandmark(247, frozen, 120);
    const r2 = nearestLandmark(247, frozen, 120);
    eq(JSON.stringify(frozen), before, "reading a landmark must not mutate metadata");
    eq(JSON.stringify(r1), JSON.stringify(r2), "reading a landmark must be pure");
    /* the result is inert data: no methods that could write later */
    for (const v of Object.values(r1)) {
      ok(typeof v !== "function", "a landmark result must be inert data, not a callback");
    }
    eq(Object.keys(r1).sort().join(","), "aliases,exact,label,landmarkMs,offsetMs,text",
       "the landmark result shape is pinned");
  }

  /* ---- 12. The suffix helper every surface shares. -------------------- */
  eq(withLandmark("247 ms", 247, MS, 120), "247 ms  1/8 -3", "grid and list compose the same way");
  eq(withLandmark("250 ms", 250, MS, 120), "250 ms  1/8", "exact landmark composes the same way");
  eq(withLandmark("17 ms", 17, MS, 120), "17 ms", "no landmark leaves the value alone");
  eq(withLandmark("17 ms", 17, MS, null), "17 ms", "no tempo leaves the value alone");
  eq(formatLandmark("1/8", 0), "1/8", "zero offset prints the label alone");
  eq(formatLandmark("1/8", -3), "1/8 -3", "negative offset");
  eq(formatLandmark("1/8", 7), "1/8 +7", "positive offset");
  eq(formatLandmark("1/8", -0.4), "1/8", "a sub-millisecond offset rounds away");

  /* ---- 13. Hostile input stays quiet. -------------------------------- */
  for (const v of [-500, 0, 1e9, Infinity, -Infinity]) {
    const r = nearestLandmark(v, MS, 120);
    ok(r === null || isFinite(r.offsetMs), "hostile value " + v + " must not produce a broken offset");
  }
  for (const bpm of [1, 20, 300, 1000]) {
    const set = landmarkSet(bpm);
    ok(Array.isArray(set) && set.length === 33, "a usable tempo always yields the full set");
    for (const l of set) ok(isFinite(l.ms) && l.ms > 0, "every landmark is a positive finite duration");
  }
  eq(landmarkSet(-5), null, "a negative tempo yields nothing");
  eq(landmarkSet(NaN), null, "NaN tempo yields nothing");

  /* ---- 14. The set is stable and complete. ---------------------------- */
  eq(landmarkSet(120).length, 33, "the landmark set size is pinned");
  eq(STRAIGHT_DENOMS.length, 8, "eight straight values");
  eq(BAR_COUNTS.length, 10, "ten bar landmarks");

  /* ---- 15. Sample-unit landmarks: generic, not module-specific. -------
   *
   * A param whose display value is a SAMPLE COUNT (unit: "smp") is landmark-
   * eligible exactly like an ms one -- matching happens in time regardless
   * of display unit -- but the printed OFFSET must be truthful in the
   * params own native unit (whole samples), not a rounded-to-the-nearest-
   * millisecond fiction. This is the mechanism any module can opt into by
   * declaring unit + tempo_landmarks (+ an optional sample_rate); nothing
   * here names a module. */
  {
    const SMP = { type: "int", min: 0, max: 176400, step: 1, unit: "smp", tempo_landmarks: true };
    /* 1/4 note at 120 BPM = 500 ms = 22050 samples at 44100 Hz, exactly. */
    const exact = nearestLandmark(22050, SMP, 120);
    ok(exact && exact.label === "1/4" && exact.offsetMs === 0 && exact.exact,
       "an exact sample-domain landmark reports zero offset, not a near-miss");
    eq(nearestLandmark(22045, SMP, 120).offsetMs, -5, "5 samples short reports -5, not -0 rounded from ms");
    eq(nearestLandmark(22055, SMP, 120).offsetMs, 5, "5 samples over reports +5, not 0 rounded from ms");
    /* The same 5 real samples is ~0.113 ms -- an ms-rounded offset would
     * have reported 0 here. This is the specific "do not lie" case: a
     * value 5 samples off the landmark must never format as if it sat ON
     * the landmark. */
    ok(nearestLandmark(22045, SMP, 120).text !== "1/4", "5 samples off must not print as exactly on the landmark");

    /* Explicit sample_rate is honoured over the 44100 Hz fallback: half the
     * rate means half as many samples for the same musical duration. */
    const SMP_HALF_RATE = { ...SMP, sample_rate: 22050 };
    eq(nearestLandmark(11025, SMP_HALF_RATE, 120).offsetMs, 0,
       "an explicit sample_rate is used, not the 44100 Hz fallback (11025 samples @ 22050 Hz = 500 ms = 1/4)");
    eq(nearestLandmark(11025, SMP, 120).label, "1/8",
       "the SAME raw count at the fallback 44100 Hz rate is a different musical duration (11025 samples = 250 ms)");

    /* Varying BPM moves the landmark set under a fixed sample count, same
     * as it already does for ms params. */
    const atSlow = nearestLandmark(22050, SMP, 60);   /* 1/4 @ 60bpm = 1000ms = 44100 smp -- 22050 is now 1/8 */
    ok(atSlow && atSlow.label === "1/8" && atSlow.exact,
       "BPM changes which landmark a fixed sample count lands on, exactly like ms params");

    /* Resolution absent (no tempo_landmarks:true) stays silent -- opt-in
     * still applies to the samples path, no special-casing bypasses it. */
    const SMP_NO_OPT = { type: "int", min: 0, max: 176400, step: 1, unit: "smp" };
    eq(nearestLandmark(22050, SMP_NO_OPT, 120), null, "samples without tempo_landmarks:true stays opted out");

    /* No BPM still hides landmarks cleanly for the samples path too. */
    eq(nearestLandmark(22050, SMP, null), null, "no tempo hides samples-domain landmarks too");

    /* Hostile input stays quiet here as well. */
    for (const v of [-500, 0, 1e9, Infinity, -Infinity]) {
      const r = nearestLandmark(v, SMP, 120);
      ok(r === null || isFinite(r.offsetMs), "hostile sample value " + v + " must not produce a broken offset");
    }

    /* withLandmark composes exactly like the ms path -- same helper, same
     * two-space join, so the grid and list cannot disagree here either. */
    eq(withLandmark("22045 smp", 22045, SMP, 120), "22045 smp  1/4 -5",
       "withLandmark composes truthfully for a samples-unit value");
  }

  console.log("tempo landmarks: " + checks + " checks passed");
}).catch((e) => { console.log("FAIL: " + (e && e.message ? e.message : e)); process.exit(1); });
'
