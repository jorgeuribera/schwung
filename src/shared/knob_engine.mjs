/**
 * knob_engine.mjs — THE knob model. One implementation, one file.
 *
 * Every physical knob turn in the UI comes through here: the Movy knob grid,
 * the hierarchy list editor and its overlay, the patch editor, the waveform
 * zoom and marker knobs.
 *
 * There used to be two. This file held a time-based divisor curve (16 / 8 / 4
 * by how fast you turned) stepping by the module's DECLARED step, while
 * param_pages/movy_knob.mjs held the ported Movy model, which normalises a
 * step to a fraction of the parameter's own RANGE. A knob therefore behaved
 * differently depending on which screen you touched it from, reported from
 * the device as knobs being "super slow in the overlay". The gap was not
 * subtle:
 *
 *     float 20..20000 step 1      overlay 79,917 detents      grid 200
 *     int   0..127                overlay    505 detents      grid 127
 *
 * ...and shift-fine, which is meant to work everywhere, was honoured for
 * floats in one and ignored for ints and enums, while in the other it could
 * not move an int at all.
 *
 * The Movy model won: it is the one the knob grid ships with, so it is the
 * feel already in people's hands, and normalising to the range is what makes
 * every knob cross in about the same wrist movement whatever its units. What
 * was lost is the time-based acceleration — the range normalisation replaces
 * what it existed to paper over.
 *
 * An intermediate version kept both files, with this one delegating to the
 * other. That is still two places to look and two things to keep in step, so
 * the model was moved here and movy_knob.mjs deleted. There is also only one
 * ENTRY POINT: knobStep, taking metadata. The config-shaped knobTick /
 * knobConfigFromMeta pair the older call sites used is gone rather than
 * aliased -- an alias is a second name for the next reader to wire something
 * up to, which is how the two models drifted apart to begin with.
 *
 * ORIGIN: the model below is ported from schwung-movy
 * (`src/model/{knob-step,store,constants}.ts`, (c) 2026 megadake, MIT —
 * https://github.com/DimaDake/schwung-movy).
 *
 * The core idea: a float/int knob's per-detent step is a fixed FRACTION of
 * its own range (~1%, MIN_STEP_RANGE_FRAC) rather than the module's declared
 * `step`, which is a statement about precision and not about sweep. That is
 * what fixes both a wide-range knob crawling and a narrow one being a hair
 * trigger.
 */

import { isBooleanMeta } from "./param_pages/viz.mjs";

/*
 * The type tags the older call sites build their configs with. They name the
 * same three kinds the metadata does.
 */
export const KNOB_TYPE_FLOAT = "float";
export const KNOB_TYPE_INT = "int";
export const KNOB_TYPE_ENUM = "enum";

/** Physical clicks per value step for a narrow int range, and for every enum. */
export const ENUM_DELTA_DIV = 4;
/** Sensitivity multiplier for a continuous arc-rendered knob — every knob in
 * the Movy layout is one, so this always applies to float/int. */
export const ARC_DELTA_SCALE = 0.5;
/** A float/int knob's per-detent step, as a fraction of its own range. */
export const MIN_STEP_RANGE_FRAC = 0.01;

/**
 * Opt-in value for `meta.knob_step_mode`: an ordinary detent moves the
 * module's own DECLARED `step`, not a fraction of the range.
 *
 * Range-normalised stepping (the default above) is right for a knob whose
 * whole point is a fast, roughly-even sweep across whatever range the module
 * picked. It is wrong for a module that declares a step because the step
 * itself is the unit the value is meant to be read and set in — a delay time
 * in exact tenths of a millisecond, say, where "0.1" is a meaningful value and
 * "23.7194" (an arbitrary 1%-of-range fraction) is not one the module or its
 * author ever intended a user to land on. Declaring `knob_step_mode:
 * "declared"` opts a param OUT of range-normalisation and into moving exactly
 * by its own step, one detent at a time, with no acceleration curve and no
 * narrow-range gating layered on: the whole feature is "what you turn is what
 * you get."
 *
 * Absent (or any other value) leaves every existing param exactly as it
 * behaved before this mode existed — see MIN_STEP_RANGE_FRAC above, untouched
 * by this file. Nothing in the fleet is expected to declare this on day one;
 * it exists for a module whose parameter is precision- rather than sweep-
 * shaped and says so.
 */
export const KNOB_STEP_MODE_DECLARED = "declared";

/** True when a param opted into declared-step mode. See KNOB_STEP_MODE_DECLARED. */
export function isDeclaredStepMode(meta) {
    return !!meta && meta.knob_step_mode === KNOB_STEP_MODE_DECLARED;
}

/**
 * DISPLAY-ONLY query: the per-detent size a SHIFT-held gesture actually
 * produces for this meta. Deliberately does not call, and is not called by,
 * knobStep -- this file's own promise is "fix the display, never the knob
 * math," so the real fine arithmetic stays exactly where it already is
 * (declaredLatticeStep's fine branch, and knobStep's default-path fine
 * branch) and this is a second, read-only statement of the same rule for a
 * caller that only wants the NUMBER, not a value that moves anything.
 *
 * A duplicated one-line formula, on purpose, in preference to importing
 * knob_engine into the display layer's hot path or exporting knobStep's
 * internals: `tests/host/test_fine_step_display_precision.sh` pins this
 * against a live knobStep call for a matrix of metas, so drift between the
 * two is a CI failure the moment either changes, not a silent mismatch.
 *
 * Returns null where "fine" has no distinct numeric size to show: an enum or
 * two-way steps in whole OPTIONS, not a decimal value, and
 * `knobAcceleration: "wide"` has no fine multiplier of its own today (see
 * wideStepCount -- it never reads `fine` at all).
 */
export function fineStepFor(meta) {
    if (!meta || (meta.type !== "float" && meta.type !== "int")) return null;
    if (!(meta.max > meta.min)) return null;
    if (meta.knobAcceleration === "wide") return null;
    const isInt = meta.type === "int";
    const coarse = isDeclaredStepMode(meta)
        ? (meta.step > 0 ? meta.step : (isInt ? 1 : 0.01))
        : perDetentStep(meta);
    return isInt ? Math.max(1, Math.round(coarse * 0.1)) : coarse * 0.1;
}
/**
 * An int range this narrow or narrower is stepped like an enum.
 *
 * SIXTEEN, because that is where "which one of N things" stops and "a sweep"
 * begins on this hardware. It was 8, which left every 1..16 selector at one
 * value per detent -- and one flick of an encoder is a dozen detents, so a pad
 * index or a MIDI channel flew past its whole range before you could read it.
 * Reported from the device against mrdrums` Current Pad: "these numbers move
 * crazy fast on a single detent".
 *
 * Measured over the fleet, the 9..16 band is 72 params and is ENTIRELY
 * discrete identities -- `midi_ch[1..16]`, `ui_current_pad[1..16]`,
 * `choke_group[0..16]`. The next band up (17..24, 17 params) is
 * `pb_range[0..24]`, `pitch_env_depth[0..24]`: quantities you sweep, where
 * four detents per unit would be an obstacle. So the boundary is evidence,
 * not a round number.
 *
 * Deliberately NOT a second detent count. ENUM_DELTA_DIV stays 4 and is shared,
 * for the reason the two-way latch pins its constant equal to the trigger`s: an
 * enum and a pad index are the same gesture over the same kind of choice, and a
 * user cannot learn two feels for controls that look alike.
 *
 * Note this does NOT align with shouldDrawBigNumber`s span of 24, and should
 * not: how a value is DRAWN and how it STEPS are different questions, and the
 * 17..24 band answers them differently on purpose.
 */
export const NARROW_RANGE_MAX = 16;

/** schwung-movy model/knob-step.ts detentsPerStep, ported. */
export function detentsPerStep(meta) {
    if (meta.type !== "int" || meta.knobAcceleration === "wide") return 1;
    const range = meta.max - meta.min;
    return (range >= 2 && range <= NARROW_RANGE_MAX) ? ENUM_DELTA_DIV : 1;
}

/*
 * EDIT SPEED — how much of the range one coarse detent covers.
 *
 * A SEPARATE QUESTION FROM A CURVE, and deliberately not conflated with one:
 *
 *     knob_step_frac   HOW FAST the knob traverses the range
 *                      (what fraction of min..max one detent moves)
 *     knob_curve       WHERE IN the range that travel is concentrated
 *
 * Micro / Normal / Long on a delay time are speeds, not sub-ranges: the
 * sensitivity changes and the range does not. Declaring a narrower min/max
 * instead is what a moving window did, and it is the thing that stalled on
 * hardware — a window has to be refreshed under the hand, and it clamps or
 * jumps when it is not. A speed cannot do either, because the range it walks
 * is the one that was declared, always.
 *
 * Absent, it is exactly MIN_STEP_RANGE_FRAC * ARC_DELTA_SCALE — the shipped
 * ~200 detents end to end, unchanged.
 */
export const KNOB_STEP_FRAC_MIN = 0.0001;   /* 10000 detents end to end */
export const KNOB_STEP_FRAC_MAX = 0.25;     /* 4 detents end to end */

/**
 * The fraction of the range one coarse detent moves, for this knob.
 *
 * Clamped, so hostile metadata degrades to a legal speed rather than to a
 * knob that cannot move or one that crosses its whole range in one click.
 */
export function knobStepFrac(meta) {
    const raw = meta ? meta.knob_step_frac : undefined;
    /*
     * "Not set" and "set to nothing" are the same thing, and neither is a
     * request for the slowest speed on the dial: Number(null) is 0, and a 0
     * clamped up is KNOB_STEP_FRAC_MIN, a knob that takes ten thousand
     * detents to cross its range.
     */
    if (raw === null || raw === undefined || raw === "") return MIN_STEP_RANGE_FRAC * ARC_DELTA_SCALE;
    const f = typeof raw === "number" ? raw : Number(raw);
    if (!isFinite(f)) return MIN_STEP_RANGE_FRAC * ARC_DELTA_SCALE;
    return Math.min(KNOB_STEP_FRAC_MAX, Math.max(KNOB_STEP_FRAC_MIN, f));
}

/** schwung-movy model/knob-step.ts perDetentStep, ported. */
export function perDetentStep(meta) {
    const arcScale = ARC_DELTA_SCALE;
    if (!(meta.max > meta.min)) return (meta.step > 0 ? meta.step : 0.01) * arcScale;
    /*
     * knobStepFrac is the fraction of the range a detent covers AFTER arc
     * scaling, so divide it back out here and let both branches below scale
     * it exactly as they did. The DEFAULT therefore lands on the old
     * expression: range * 0.005 / 0.5 == range * MIN_STEP_RANGE_FRAC. An
     * int's step floor and its rounding are untouched.
     */
    const preScale = (meta.max - meta.min) * (knobStepFrac(meta) / arcScale);
    if (meta.type === "int") return Math.round(Math.max(meta.step > 0 ? meta.step : 1, preScale) * arcScale);
    return preScale * arcScale;   // float
}

/**
 * schwung-movy model/store.ts wideStepCount, ported. Velocity multiplier for
 * a param that opts into `knobAcceleration: "wide"` — see the module doc:
 * nothing in the fleet declares this today.
 */
function wideStepCount(state, direction, nowMs) {
    let multiplier = 1;
    const elapsed = state.lastTurnMs > 0 ? nowMs - state.lastTurnMs : Infinity;
    if (direction === state.lastDirection) {
        if (elapsed <= 35) multiplier = 250;
        else if (elapsed <= 90) multiplier = 50;
        else if (elapsed <= 180) multiplier = 10;
    }
    state.lastTurnMs = nowMs;
    state.lastDirection = direction;
    return direction * multiplier;
}

/**
 * A two-state boolean, i.e. exactly what viz.mjs `detectSwitch` draws as a
 * switch. Kept on the same BOOL_OPTION test so a control cannot be drawn as a
 * switch but turned like a list (or the reverse) — and since the PICTURE is
 * what tells you which way is on (see knobStep), the two must be the same set
 * or the promise the graphic makes is one the knob does not keep.
 */
function isSwitchMeta(meta) {
    return isBooleanMeta(meta);
}

/** The words BOOL_OPTION accepts that mean ON. */
const BOOL_ON_WORD = /^(on|yes|1|true|enabled)$/i;

/**
 * Which of a switch's two values is ON.
 *
 * Almost always index 1, but an author is free to declare `["On", "Off"]` and
 * a few do. A direction-absolute switch that assumed 1 would then turn OFF
 * clockwise, which is the exact complaint this rule exists to fix — so the
 * direction is resolved against the WORDS, not the position. An int 0..1 has
 * no words and 1 is on by construction.
 *
 * This also keeps the knob agreeing with the picture: the switch graphic draws
 * its knob at the ON end, resolved the same way.
 */
function switchOnValue(meta) {
    const opts = Array.isArray(meta.options) ? meta.options.map(String) : null;
    if (!opts || opts.length !== 2) return 1;
    const i = opts.findIndex((o) => BOOL_ON_WORD.test(o.trim()));
    return i >= 0 ? i : 1;
}

/**
 * Minimum still time before a knob can flip a two-way control again.
 *
 * The same number and the same rule as `TRIGGER_KNOB_GESTURE_GAP_MS` in
 * page_controller.mjs: ONE FLICK IS ONE GESTURE. A trigger fires once per
 * flick; a two-way flips once per flick. Both would otherwise act a dozen
 * times across a single twist of the encoder.
 *
 * It is a LATCH, not a rate limit, and that is the distinction the trigger
 * shipped wrong first: the stamp is the last DETENT, so every detent extends
 * the gesture and the clock only runs while the knob is STILL.
 */
export const TWO_WAY_GESTURE_GAP_MS = 270;

/**
 * A control with exactly TWO values and no travel between them.
 *
 * Both spellings count — an Off/On (or int 0..1) boolean, which is drawn as a
 * switch, and a two-way CHOICE like Mix/Reverb or Saw/Square, which is drawn
 * as an enum square. They are the same control under the click and the dive.
 *
 * They part company on the KNOB, and only there, on the strength of how they
 * are DRAWN: a switch has a track and its knob sits at one end of it, so the
 * form names the direction and the turn is direction-absolute (clockwise on).
 * An enum square is a boxed value that shows a state and no direction, so it
 * TOGGLES on a detent whichever way it went. knobStep takes the switch first
 * for that reason; this predicate still answers true for both, because every
 * other caller wants the shared answer.
 *
 * A TRIGGER is excluded. It is a two-option enum on the wire (["—","Rnd!"])
 * and toggling it would write "do nothing" on every other flick — which for
 * euclidrum's rnd_preset is the write that destroys a kit. Callers that route
 * triggers away before reaching here (page_controller does) are unaffected;
 * this is for the ones that do not.
 */
function isTwoWayMeta(meta) {
    if (!meta) return false;
    if (meta.writeOnly || meta.access === "write") return false;
    if (isSwitchMeta(meta)) return true;
    return (meta.kind === "enum" || meta.type === "enum")
        && Array.isArray(meta.options) && meta.options.length === 2;
}

/**
 * Reversing direction drops whatever partial turn was banked the other way.
 * Without it the residue is spent cancelling the new direction first, so a
 * reversal costs up to div + (div - 1) detents — 7 at ENUM_DELTA_DIV 4 — and
 * how many depends on where the previous turn happened to stop, which is why
 * the same knob feels inconsistent from one reversal to the next.
 */
function clearOnReversal(state, delta) {
    if (state.detentAccum !== 0 && Math.sign(state.detentAccum) !== Math.sign(delta))
        state.detentAccum = 0;
}

export function knobInit(initialValue) {
    return { value: initialValue, detentAccum: 0, lastTurnMs: 0, lastDirection: 0 };
}

/* ------------------------------------------------------------------ *
 * RESPONSE CURVES
 * ------------------------------------------------------------------ *
 * A wide range and a fine one ask the opposite things of the same wrist
 * movement. Range-normalised stepping (MIN_STEP_RANGE_FRAC) answers "make
 * every knob cross in about the same movement", which is right for a sweep
 * and wrong for a delay time: 0.5% of 4000 ms is 20 ms a detent, so the
 * whole flanger/comb region below ~20 ms is a single click, while 3-second
 * atmospheric times get the same 20 ms.
 *
 * A curve redistributes that travel WITHOUT changing how much of it there
 * is. The knob keeps a hidden control coordinate u in [0,1] that a detent
 * moves by a fixed amount, and the parameter is y = f(u) laid over the
 * declared range:
 *
 *     linear       y = u
 *     low_focus    y = u^gamma                  more travel near MINIMUM
 *     high_focus   y = 1 - (1-u)^gamma          more travel near MAXIMUM
 *
 * So the range is always 1/du ~= 200 detents end to end whatever gamma is;
 * the curve only decides where those detents are spent. That is the whole
 * point, and it is also the safety property: because dy/du = gamma * u^
 * (gamma-1) is bounded by gamma over [0,1], the COARSEST detent anywhere on
 * the dial is at most gamma times the linear one. The high end cannot run
 * away. (A moving min/max window had no such bound, which is why it kept
 * stalling on hardware — see EXPERIMENTAL_LIVE_PARAMS.md.)
 *
 * u is never stored. It is recovered from state.value on every call with the
 * exact inverse (u = y^(1/gamma), or 1-(1-y)^(1/gamma)), the same trick
 * declaredLatticeStep uses to avoid a second source of truth. That is what
 * makes it reversible and jump-free:
 *
 *   - seeding from an arbitrary existing value is exact, so the first
 *     detent continues from where the sound already is;
 *   - reversing just moves u the other way;
 *   - u in [0,1] means min and max are hit EXACTLY and clamped, not
 *     approached;
 *   - switching curve at a standing value keeps that value, because the new
 *     curve seeds from the value rather than from the old u.
 *
 * Module metadata opts in. Nothing here knows what a delay is:
 *
 *     "knob_curve": "low_focus"        linear | low_focus | high_focus
 *     "knob_curve_gamma": 2.0          optional strength; default 2
 *
 * Calling it "gamma" rather than "angle" or "log" is deliberate: the mapping
 * is a power law, and it is not logarithmic.
 */

export const KNOB_CURVE_LINEAR = "linear";
export const KNOB_CURVE_LOW_FOCUS = "low_focus";
export const KNOB_CURVE_HIGH_FOCUS = "high_focus";

/** Optional strength. 1 is exactly linear, which is the honest floor. */
export const KNOB_CURVE_DEFAULT_GAMMA = 2;
export const KNOB_CURVE_MIN_GAMMA = 1;
export const KNOB_CURVE_MAX_GAMMA = 8;

/*
 * KNOB_STEP_MODE_DECLARED (declared above, near isDeclaredStepMode) is reused
 * below: a curve and a declared step are mutually exclusive, so knobCurveMode
 * defers to the same constant rather than a second spelling of "declared".
 */

function clamp01(x) {
    if (!(x > 0)) return 0;   /* also catches NaN */
    return x < 1 ? x : 1;
}

/**
 * The strength a curved knob actually runs at: the declared gamma, clamped
 * into [MIN, MAX] so bad metadata degrades to a legal curve instead of to a
 * knob that flies off the end of its range. Absent or non-numeric means the
 * default, not linear — a param that asked for a curve and forgot the number
 * still gets the curve it named.
 */
export function knobCurveGamma(meta) {
    const g = Number(meta && meta.knob_curve_gamma);
    if (!isFinite(g)) return KNOB_CURVE_DEFAULT_GAMMA;
    return Math.min(KNOB_CURVE_MAX_GAMMA, Math.max(KNOB_CURVE_MIN_GAMMA, g));
}

/**
 * The curve a knob runs, or null for "step as the range normalises it".
 *
 * Declared-step wins outright. A curve is a redistribution of normalised
 * travel and a declared step is an absolute lattice over the same range;
 * composing the two asks which of them an ordinary detent of "1" means, and
 * there is no answer that is not a hidden surprise. So the param is
 * declared-step and its curve is ignored, rather than silently blended.
 */
export function knobCurveMode(meta) {
    if (!meta) return null;
    if (meta.knob_step_mode === KNOB_STEP_MODE_DECLARED) return null;
    const c = meta.knob_curve;
    if (c === KNOB_CURVE_LOW_FOCUS || c === KNOB_CURVE_HIGH_FOCUS) return c;
    return null;
}

/** Normalised value y from control coordinate u. Exact at both ends. */
export function curveYFromU(u, mode, gamma) {
    const c = clamp01(u);
    if (mode === KNOB_CURVE_HIGH_FOCUS) return 1 - Math.pow(1 - c, gamma);
    return Math.pow(c, gamma);
}

/** Exact inverse of curveYFromU — the seeding and reversal guarantee. */
export function curveUFromY(y, mode, gamma) {
    const c = clamp01(y);
    if (mode === KNOB_CURVE_HIGH_FOCUS) return 1 - Math.pow(1 - c, 1 / gamma);
    return Math.pow(c, 1 / gamma);
}

/**
 * One curved detent run: `steps` whole steps of du in control space.
 *
 * Mirrors the shape of the range-normalised path it replaces — same detent
 * gate, same fine multiplier, same clamp, same int rounding — so the only
 * thing that differs is that the step is taken in u and warped back.
 *
 * `du` is the SAME knobStepFrac the flat path uses, so speed and curve
 * compose instead of competing: du decides how fast u is walked end to end,
 * gamma decides where along the way the value moves most. Changing one
 * leaves the other's feel intact.
 */
function curvedKnobStep(state, meta, steps, fine) {
    const mode = knobCurveMode(meta);
    const gamma = knobCurveGamma(meta);
    const min = meta.min;
    const max = meta.max;
    const span = max - min;
    const base = knobStepFrac(meta);
    const du = fine ? base * 0.1 : base;

    const y0 = clamp01((state.value - min) / span);
    let u = curveUFromY(y0, mode, gamma) + steps * du;
    if (!(u >= 0)) u = 0;          /* NaN, or a span that refused to divide */
    if (u > 1) u = 1;

    let value = min + curveYFromU(u, mode, gamma) * span;
    value = Math.max(min, Math.min(max, value));

    if (meta.type === "int") {
        const rounded = Math.round(value);
        /*
         * A detent that rounds back onto the value it started from is a dead
         * knob, and the compressed end of a curve moves less than one whole
         * unit per detent by design. Take one unit the way the hand was
         * going rather than let the knob sit there.
         */
        if (steps !== 0 && rounded === Math.round(state.value)) {
            value = Math.max(min, Math.min(max, Math.round(state.value) + Math.sign(steps)));
        } else {
            value = rounded;
        }
    }
    state.value = value;
    return value;
}

/**
 * Declared-step stepping: an ordinary detent moves exactly one module-declared
 * `step`, and min/max are always EXACTLY reachable — never a float neighbour
 * of them a detent can approach but never land on.
 *
 * Iterating `value += step` and clamping afterwards (which is what the
 * default range-normalised path below does, and is fine there) does not give
 * that guarantee: repeated float addition drifts, and when the range is not
 * an exact multiple of the step (min=0, max=1, step=0.3: 0, .3, .6, .9, and
 * then a fourth detent would overshoot to 1.2) a plain clamp either overshoots
 * past a meaningful ceiling or, after enough drift, can sit a few ULPs under
 * `max` forever without ever comparing equal to it.
 *
 * So this steps an INTEGER lattice index (`round((value-min)/step)`) rather
 * than the float value itself, and treats `max` as one extra, virtual grid
 * point past the last clean multiple of `step` when the two do not coincide.
 * Landing on that point always reads back as the exact `max` the module
 * declared, and turning back from it drops to the last clean step below it —
 * one detent, immediately, never a partial or a skipped step. `min` never
 * needs the same treatment: index 0 times any step is exactly 0, so `min + 0`
 * is `min` with no floating-point error possible.
 */
function declaredLatticeStep(state, meta, delta, fine) {
    const min = meta.min, max = meta.max;
    const isInt = meta.type === "int";
    const declared = meta.step > 0 ? meta.step : (isInt ? 1 : 0.01);
    /* Same FINE rule as the range-normalised path: a tenth of the coarse
     * step, floored at one whole unit for an int so shift can still move it. */
    const stepSize = !fine ? declared
        : (isInt ? Math.max(1, Math.round(declared * 0.1)) : declared * 0.1);

    const range = max - min;
    const EPS = Math.max(1e-9, Math.abs(stepSize) * 1e-6);
    /* How many clean steps fit under max without going over it. */
    const maxIndex = Math.max(0, Math.floor((range + EPS) / stepSize));
    const latticeMax = min + maxIndex * stepSize;
    /* max sits past the last clean multiple -- it needs its own virtual index. */
    const hasCeiling = latticeMax < max - EPS;
    const topIndex = maxIndex + (hasCeiling ? 1 : 0);

    /* Recover where the lattice we are already at, from the value alone --
     * this function keeps no index of its own between calls, so a value
     * sitting exactly on the virtual ceiling must be recognised as such
     * rather than rounded back onto the ordinary grid one step short of it. */
    let index = (hasCeiling && Math.abs(state.value - max) <= EPS)
        ? topIndex
        : Math.max(0, Math.min(maxIndex, Math.round((state.value - min) / stepSize)));

    index = Math.max(0, Math.min(topIndex, index + delta));

    let next = (hasCeiling && index === topIndex) ? max : min + index * stepSize;
    if (Math.abs(next - min) <= EPS) next = min;
    if (Math.abs(next - max) <= EPS) next = max;
    if (isInt) next = Math.round(next);
    state.value = next;
    return next;
}

/**
 * @param {object} state   from movyKnobInit, mutated in place
 * @param {object} meta    param_meta.mjs metadata (min/max/step/type/options)
 * @param {number} delta   ±1 per physical detent (this library always decodes
 *                         one CC message to one detent — see page_input.mjs)
 * @param {number} nowMs
 * @param {boolean} [fine] Shift-held precision mode. Not part of Movy's own
 *                 model (no equivalent was found in its source); grafted on
 *                 so the gesture works everywhere.
 *
 *                 THE RULE, in two clauses, both of which matter:
 *
 *                   1. the step becomes a TENTH of the coarse step, floored
 *                      at one whole unit for an int (a tenth of a 1-unit step
 *                      is 0.1, which rounds straight back — that was an int
 *                      knob that could not be moved at all under shift); and
 *                   2. the detent GATE is lifted, so every detent moves
 *                      something.
 *
 *                 Clause 2 is why shift can make a control FASTER rather than
 *                 slower, which looks contradictory on a stopwatch: an enum
 *                 and a narrow int are gated at ENUM_DELTA_DIV detents per
 *                 option in the coarse feel, so lifting the gate is a
 *                 fourfold speed-up. It is still precision — with shift held
 *                 one click is exactly one option, instead of four clicks
 *                 being one option and a partial turn being nothing at all.
 *                 That is what you want when placing a value rather than
 *                 sweeping to one.
 * @returns {number} the new value
 */
export function knobStep(state, meta, delta, nowMs, fine = false) {
    if (!state || !delta) return state ? state.value : 0;

    /*
     * Fill in a missing range. Call sites hand us metadata straight off
     * chain_params, and a module is not obliged to declare min/max -- an
     * absent one used to arrive as undefined, and the clamp at the bottom
     * turned the value into NaN, which is then written to the device as the
     * string "NaN". The old config-shaped entry point defaulted these on the
     * way in; now that there is only one entry point, it has to do it here.
     */
    if (typeof meta.min !== "number" || typeof meta.max !== "number") {
        const isInt = meta.type === "int";
        meta = {
            ...meta,
            min: typeof meta.min === "number" ? meta.min : 0,
            max: typeof meta.max === "number" ? meta.max : (isInt ? 127 : 1),
        };
    }

    /*
     * A BOXED TWO-WAY TOGGLES, WHICHEVER WAY THE DETENT WENT.
     *
     * This is the enum-square spelling only — Mix/Reverb, Saw/Square. Anything
     * drawn as a SWITCH was taken by the branch above and is
     * direction-absolute. A boxed two-way used to fall through to the enum
     * branch below and CLAMP behind a four-detent gate, so it had a dead
     * direction:
     *
     *   Mix/Reverb at Mix, turned left nothing, forever
     *
     * Reported from the device: "if there are only two, why not let it wrap
     * otherwise you have to know which way is off and which way is on, in
     * which case you need some knowledge you dont have." There is no way to
     * acquire that knowledge from a boxed value — it shows a state, and the two
     * options sit in the same place whichever one is current — so half of every
     * reach for the knob reads as a dead control. That is the same argument
     * that makes a trigger fire in either direction. And it is exactly why it
     * stops at the switch: a track with a knob on it is a picture of a
     * direction, so there the knowledge IS on the screen.
     *
     * WRAPPING ALONE WOULD NOT DO, and this is the part worth keeping. With
     * two values, "wrap" and "toggle on every detent" are the same thing, and
     * one flick of an encoder is a dozen detents — so a flick would land on
     * whichever value the detent count happened to be even or odd about. The
     * LATCH is what makes the gesture legible: one flick, one flip, and the
     * clock runs on STILLNESS because the stamp is the last detent rather than
     * the last flip.
     *
     * Hoisted above the enum branch for the reason it always was: an int 0..1
     * never enters that branch and would accumulate on the numeric path (the
     * switch branch above it exists for the same reason).
     */
    /*
     * A SWITCH IS DIRECTION-ABSOLUTE: clockwise is ON, anticlockwise is OFF.
     *
     * THE SPLIT IS THE WIDGET, NOT THE SEMANTICS. The toggle rule below exists
     * because "the cell shows a STATE, not a direction" — true of the boxed
     * value an enum square draws, where Mix and Reverb sit in the same box in
     * the same place and nothing on screen says which way the knob reaches
     * which. It is NOT true of a switch: a switch has a TRACK, and its knob
     * sits at one end of it. The form itself names the direction, and it is the
     * same direction every physical switch has ever had. So the picture makes a
     * promise here that the boxed value never makes, and the toggle broke it —
     * clockwise on an already-on switch turned it OFF. Reported from the
     * device: "if it's on it should stay on when turning it on."
     *
     * Which is why the test is isSwitchMeta and not "is this a boolean":
     * detectSwitch draws VIZ_SWITCH for exactly isBooleanMeta && !isTrigger,
     * and this branch guards on exactly that pair. Whatever WEARS the track
     * gets the direction; everything else keeps the toggle. If the two ever
     * drift apart, a control will make a promise with its shape that the knob
     * does not keep.
     *
     * There is no latch because it does not need one: the write is IDEMPOTENT,
     * so a dozen detents of one flick all say the same thing, and a flick that
     * lands where it already was is the intended no-op rather than a parity
     * accident. That is also why this returns without stamping lastTwoWayMs.
     */
    if (isSwitchMeta(meta) && !(meta.writeOnly || meta.access === "write")) {
        const on = switchOnValue(meta);
        state.detentAccum = 0;
        state.value = delta > 0 ? on : (on === 1 ? 0 : 1);
        return state.value;
    }

    if (isTwoWayMeta(meta)) {
        const t = typeof nowMs === "number" ? nowMs : 0;
        const last = state.lastTwoWayMs;
        const startsGesture = last === undefined
            || (t - last) >= TWO_WAY_GESTURE_GAP_MS;
        state.lastTwoWayMs = t;
        state.detentAccum = 0;
        if (!startsGesture) return state.value;
        state.value = Math.round(Number(state.value)) === 0 ? 1 : 0;
        return state.value;
    }

    if (meta.kind === "enum" || meta.type === "enum") {
        /* THREE OR MORE options only — anything with exactly two was taken by
         * the branch above. That is what the four-detent gate is for: a long
         * list wants a sweep, and a two-way has nothing to sweep through, so
         * running one through this gate cost 4 detents to move at all (and up
         * to 7 to come back), which reads as a dead control — the drawn knob
         * simply does not move when you turn it. */
        const div = fine ? 1 : ENUM_DELTA_DIV;
        clearOnReversal(state, delta);
        state.detentAccum += delta;
        const steps = Math.trunc(state.detentAccum / div);
        if (steps === 0) return state.value;
        state.detentAccum -= steps * div;
        const count = Array.isArray(meta.options) ? meta.options.length : (meta.max - meta.min + 1);
        let iv = Math.round(state.value) + steps;
        iv = Math.max(0, Math.min(Math.max(0, count - 1), iv));
        state.value = iv;
        return state.value;
    }

    if (meta.knobAcceleration === "wide") {
        const scaled = wideStepCount(state, delta > 0 ? 1 : -1, nowMs) * (meta.step > 0 ? meta.step : 1);
        let next = state.value + scaled;
        next = Math.max(meta.min, Math.min(meta.max, next));
        if (meta.type === "int") next = Math.round(next);
        state.value = next;
        return next;
    }

    /*
     * DECLARED STEP MODE, entirely separate from the range-normalised path
     * below it. See KNOB_STEP_MODE_DECLARED and declaredLatticeStep -- this
     * branch never touches MIN_STEP_RANGE_FRAC, perDetentStep or
     * detentsPerStep, so opting a param in cannot change how any other
     * param's default knob feel is computed.
     */
    if (isDeclaredStepMode(meta) && meta.max > meta.min) {
        return declaredLatticeStep(state, meta, delta, fine);
    }

    const div = fine ? 1 : detentsPerStep(meta);
    let steps = delta;
    if (div > 1) {
        clearOnReversal(state, delta);
        state.detentAccum += delta;
        steps = Math.trunc(state.detentAccum / div);
        if (steps === 0) return state.value;
        state.detentAccum -= steps * div;
    }
    /*
     * A CURVED knob takes its step in control space instead. Reached after
     * declared-step (which returns) and after the enum/wide branches above,
     * so those keep their behaviour exactly; the gate and the fine
     * multiplier are the same ones the path below uses.
     *
     * A curve needs a range it can normalise over. An inverted or empty one
     * (min == max) has no span to divide by, so it falls through to the
     * path below rather than inventing one: degenerate metadata keeps the
     * behaviour it already had, which is the tested one.
     */
    if (meta.max > meta.min && knobCurveMode(meta))
        return curvedKnobStep(state, meta, steps, fine);

    /*
     * FINE is a tenth of the coarse step -- except an int, where a tenth of a
     * 1-unit step is 0.1 and Math.round below puts it straight back. That was
     * not "fine is subtle", it was an int knob that could not be moved AT ALL
     * with shift held: measured at 400,000 detents without crossing 0..127.
     * An int's finest meaningful move is 1.
     */
    const coarseStep = perDetentStep(meta);
    const stepSize = !fine ? coarseStep
        : (meta.type === "int" ? Math.max(1, Math.round(coarseStep * 0.1))
                               : coarseStep * 0.1);
    let next = state.value + steps * stepSize;
    next = Math.max(meta.min, Math.min(meta.max, next));
    if (meta.type === "int") next = Math.round(next);
    state.value = next;
    return next;
}

