/**
 * tempo_landmarks.mjs — rhythmic landmarks for a FREE time parameter.
 *
 * THIS IS NOT TEMPO SYNC. It is an INFORMATION LAYER, and the distinction is
 * the whole design:
 *
 *     Tempo sync    the parameter is QUANTISED to the grid. It cannot sit
 *                   between two notes, and moving the tempo moves it.
 *     A landmark    the parameter is completely free. Tempo does not quantise
 *                   it, pull it, snap it, block it or move it. It only lets
 *                   the screen SAY where the nearest rhythmic value is, so
 *                   the user can deliberately sit before it, on it, or after
 *                   it — the three states that are musically different and
 *                   that a snapped control makes unreachable.
 *
 * Nothing here writes, clamps, rounds or stores. There is no magnetic detent,
 * no sticky region and no soft lock. A landmark is a distance measurement
 * rendered as text.
 *
 * Opt-in, because a unit of "ms" does not mean "is a note duration": most
 * millisecond parameters in the fleet are envelopes, smoothing times and
 * fade times, and showing "1/8 -3" next to a release time is noise.
 *
 *     { "key": "a_time", "unit": "ms", "tempo_landmarks": true }
 *
 * The unit is honoured so a param declared in seconds is not silently read
 * as milliseconds (`sec`/`s` are converted; anything else is ms).
 *
 * ALL durations below are fractions of a WHOLE note, because that is the one
 * representation where a triplet of a straight value is itself a clean
 * fraction — which is what makes the aliasing rule in the module doc
 * expressible at all.
 */

/** Straight note values, as 1/d of a whole note. */
export const STRAIGHT_DENOMS = [1, 2, 4, 8, 16, 32, 64, 128];

/**
 * Bar landmarks, in whole notes (4/4 assumed: one bar IS one whole note).
 *
 * The non-binary counts are the point. 3, 6, 12 and 24 bars are ordinary
 * electronic-music phrase lengths, and a set of only powers of two would
 * make them unreachable as landmarks.
 */
export const BAR_COUNTS = [1, 2, 3, 4, 6, 8, 12, 16, 24, 32];

/**
 * How near a value must be to a landmark before it is worth saying, as a
 * fraction of THAT landmark's own duration.
 *
 * RELATIVE, not a fixed number of milliseconds, because a fixed tolerance is
 * musically wrong at both ends: ±10 ms is two thirds of a 1/64 and a rounding
 * error on a 16-bar phrase. Proportional keeps the zone meaning "about this
 * note" everywhere.
 *
 * 5% keeps neighbouring zones from touching. The tightest pair in the set is
 * 1/4T against 1/8D (a ratio of 1.125), so at 5% they stay clear of each
 * other and "nearest" is never a coin toss.
 */
export const LANDMARK_RELEVANCE = 0.05;

/**
 * Milliseconds in one beat (a quarter note) at `bpm`, or null if there is no
 * usable tempo.
 *
 * Strict about being a NUMBER, not merely coercible to one: `isFinite` alone
 * accepts the string "120", and a tempo that arrived as text is a wiring bug
 * worth surfacing as "no landmarks" rather than silently dividing by it. The
 * callers that read it off a wire already convert with Number().
 */
export function quarterMs(bpm) {
    if (typeof bpm !== "number" || !isFinite(bpm) || bpm <= 0) return null;
    return 60000 / bpm;
}

function gcd(a, b) {
    while (b) { const t = a % b; a = b; b = t; }
    return a || 1;
}

/** A duration as a reduced fraction, so 2/4 and 1/2 are the same landmark. */
function frac(n, d) {
    const g = gcd(Math.abs(n), Math.abs(d));
    return { n: n / g, d: d / g };
}

/*
 * The set, built ONCE per tempo rather than per cell.
 *
 * Bars go in FIRST, and that ordering is load-bearing: in 4/4 one bar IS one
 * whole note, so `1 bar` and the straight value `1/1` are the SAME duration.
 * Canonical durations must not produce two markers for one point in time, so
 * the bar spelling wins — for a duration that long the phrase is what a user
 * is counting, not the note value.
 *
 * Triplets and dotted values are the two ways one straight value is
 * modified, and they are NOT the same thing:
 *
 *     1/8T  =  straight 1/8 * 2/3      shorter
 *     1/8D  =  straight 1/8 * 3/2      longer
 *
 * Neither collides with a straight value or with the other (3 is not a power
 * of two), so no dedup is needed beyond the bar/1-1 case above.
 */
function buildLandmarkFractions() {
    const out = [];
    const seen = new Set();
    const add = (f, label, aliases) => {
        const key = f.n + "/" + f.d;
        if (seen.has(key)) return;
        seen.add(key);
        out.push({ n: f.n, d: f.d, label, aliases: aliases || [] });
    };

    for (const n of BAR_COUNTS) {
        add(frac(n, 1), n === 1 ? "1 bar" : n + " bars");
    }
    for (const d of STRAIGHT_DENOMS) {
        add(frac(1, d), "1/" + d);
        /* triplet of 1/d is 1/d * 2/3 = 2/(3d) = 1/(3d/2) -- an exact
         * fraction only while d is even, hence the 2/3 form for d === 1. */
        const t = d === 1 ? frac(2, 3) : frac(1, (3 * d) / 2);
        add(t, "1/" + d + "T", ["1/" + t.d]);
        /* dotted is 1/d * 3/2 */
        add(frac(3, 2 * d), "1/" + d + "D");
    }
    return out;
}

const LANDMARK_FRACTIONS = buildLandmarkFractions();

/**
 * Every landmark as a millisecond duration at `bpm`, or null when there is no
 * usable tempo.
 */
export function landmarkSet(bpm) {
    const q = quarterMs(bpm);
    if (q === null) return null;
    const whole = q * 4;
    return LANDMARK_FRACTIONS.map((f) => ({
        ms: (f.n / f.d) * whole,
        label: f.label,
        aliases: f.aliases,
    }));
}

/**
 * Does this param ask for landmarks?
 *
 * Opt-in only. A `unit` of "ms" is NOT enough — envelope times, smoothing
 * times and fade times are all milliseconds and none of them are notes.
 */
export function landmarkEnabled(meta) {
    return !!(meta && meta.tempo_landmarks);
}

/**
 * The param's value in milliseconds, or null if it is not a readable number.
 *
 * Unit-aware so a param declared in seconds is not read as milliseconds.
 */
function valueMs(raw, meta) {
    const n = Number(raw);
    if (!isFinite(n)) return null;
    const u = meta && meta.unit;
    if (u === "sec" || u === "s" || u === "seconds") return n * 1000;
    return n;
}

/**
 * The nearest musical landmark to `raw`, or null if there is nothing useful
 * to say.
 *
 * Null is the common answer and it is the correct one: a landmark that is
 * always on screen stops being information and becomes furniture. It is null
 * when the param does not opt in, when the value is not a number, when there
 * is no usable tempo, and — most of the time — when the value is simply not
 * near any rhythmic duration.
 *
 * @returns {{label: string, aliases: string[], offsetMs: number, exact: boolean,
 *            landmarkMs: number, text: string}|null}
 */
export function nearestLandmark(raw, meta, bpm) {
    if (!landmarkEnabled(meta)) return null;
    const ms = valueMs(raw, meta);
    if (ms === null) return null;
    const set = landmarkSet(bpm);
    if (!set) return null;

    let best = null;
    let bestDist = Infinity;
    for (const l of set) {
        const d = Math.abs(ms - l.ms);
        if (d < bestDist) { bestDist = d; best = l; }
    }
    if (!best) return null;

    /* Proportional: the same 5% of the landmark's own length everywhere. */
    if (bestDist > best.ms * LANDMARK_RELEVANCE) return null;

    const offset = ms - best.ms;
    const rounded = Math.round(offset);
    return {
        label: best.label,
        aliases: best.aliases,
        landmarkMs: best.ms,
        offsetMs: rounded,
        exact: rounded === 0,
        text: formatLandmark(best.label, rounded),
    };
}

/**
 * "1/8", "1/8 -3", "1/8 +7".
 *
 * Text, not note glyphs: an explicit fraction is easier to reason about at a
 * glance than a symbol, and it fits the font the display actually has. The
 * offset carries no unit — the value beside it already said "ms".
 *
 * Presentation only. Which of a landmark's aliases gets shown is decided
 * here and nowhere else, so the grid and the list cannot disagree.
 */
export function formatLandmark(label, offsetMs) {
    const off = Math.round(offsetMs);
    if (!off) return label;
    return label + (off > 0 ? " +" : " -") + Math.abs(off);
}

/**
 * THE helper every surface calls. The knob-grid header, the list view and
 * the screen reader all go through this, so the musical arithmetic lives in
 * exactly one place and no renderer can drift from another.
 *
 * @returns {string|null} a short suffix to sit beside the value, or null to
 *          draw nothing.
 */
export function landmarkSuffix(raw, meta, bpm) {
    const l = nearestLandmark(raw, meta, bpm);
    return l ? l.text : null;
}

/**
 * "... 247 ms  1/8 -3", or just the value when there is nothing to say.
 *
 * Joining with two spaces and no separator glyph: the header and the list row
 * are both measured to fit, and a middot is a width the 4x5 face spends on
 * something that carries no information.
 */
export function withLandmark(valueText, raw, meta, bpm) {
    const suffix = landmarkSuffix(raw, meta, bpm);
    if (!suffix) return valueText;
    return valueText + "  " + suffix;
}
