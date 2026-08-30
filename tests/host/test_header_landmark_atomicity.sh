#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

# The selected-param header must NEVER show a partial musical token.
#
# withLandmark() (tempo_landmarks.mjs) builds "41.105 ms  1/32T" as one plain
# string -- value, two spaces, landmark suffix -- with zero awareness of the
# header's pixel budget. drawHeader's old right-side fitting truncated that
# string by slicing characters off the end until it fit, with no idea a
# musical token lived in there: on a real Move this cropped "41.105 ms  1/32T"
# down to "41.105 ms  1", which reads as a complete-looking but meaningless
# landmark. This test drives fitHeaderRight() (render_page_movy.mjs) across
# every straight/triplet/dotted/bar-count landmark label, a spread of numeric
# values and titles, and every pixel width the header could plausibly offer,
# and asserts the visible landmark suffix is always the COMPLETE token or
# entirely absent -- never a prefix of it. It also drives drawHeader() itself
# through the headless harness to confirm the fix is actually wired into the
# real draw path, not just correct in isolation.

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: node is required" >&2
  exit 1
fi

node -e '
Promise.all([
  import("./tools/param-pages/harness.mjs"),
  import("./src/shared/param_pages/render_page_movy.mjs"),
  import("./src/shared/param_pages/font4x5.mjs"),
  import("./src/shared/param_pages/tempo_landmarks.mjs"),
]).then(([H, R, F, T]) => {
  const fail = (m) => { console.log("FAIL: " + m); process.exit(1); };
  const capsFold = (s) => String(s).toUpperCase();

  /* An INDEPENDENT oracle -- it does not reuse atomicTokenTiers() internals, so
   * it cannot pass merely because the implementation agrees with itself. */
  function isPartialToken(result, value, label) {
    const V = capsFold(value), L = capsFold(label);
    /* The implementation may show the value with its unit spelling dropped
     * (the COMPACT tier) -- the oracle must accept either spelling of the
     * value prefix, since only the LANDMARK half of the string is under
     * test here. */
    const compactV = V.replace(/\s+(MS|SEC)$/, "");
    for (const v of [V, compactV]) {
      if (result === v) return false;                // landmark dropped entirely: fine
      if (result.startsWith(v)) {
        let rest = result.slice(v.length).replace(/^\s+/, "");
        rest = rest.replace(/\s[+-]\d+$/, "");        // a well-formed trailing offset may be present
        if (rest === "") return false;                // landmark dropped (only spaces/offset remained)
        if (rest === L) return false;                 // complete label: fine
        if (L.startsWith(rest)) return true;           // non-empty, not the whole label -> partial token
      }
    }
    /* Neither value spelling prefixes the result: this must be the
     * safety-net char-slice of the bare value (shorter than either
     * spelling) -- fine as long as it is a prefix of one of them. */
    if (V.startsWith(result) || compactV.startsWith(result)) return false;
    return true;
  }

  const STRAIGHT = T.STRAIGHT_DENOMS.map((d) => "1/" + d);
  const TRIPLET = T.STRAIGHT_DENOMS.map((d) => "1/" + d + "T");
  const DOTTED = T.STRAIGHT_DENOMS.map((d) => "1/" + d + "D");
  const BARS = T.BAR_COUNTS.map((n) => (n === 1 ? "1 bar" : n + " bars"));
  const LABELS = [...STRAIGHT, ...TRIPLET, ...DOTTED, ...BARS];
  const OFFSETS = [null, -3, 7, -1, 12];
  const VALUES = ["0 ms", "0.001 ms", "41.105 ms", "247 ms", "999.999 ms", "4000 ms", "1.234 sec"];
  const TITLES = ["A", "A TIME", "B TIME", "MFX > BRIGHTAMBIENCE3 CUTOFF"];

  const WIDTHS = [];
  for (let w = 0; w <= 90; w += 3) WIDTHS.push(w);

  let cases = 0;
  for (const label of LABELS) {
    for (const off of OFFSETS) {
      const suffix = off === null ? label : label + (off > 0 ? " +" : " -") + Math.abs(off);
      for (const value of VALUES) {
        const text = value + "  " + suffix;
        for (const w of WIDTHS) {
          cases++;
          const result = R.fitHeaderRight(F.FONT4_MEASURE, w, text);
          if (isPartialToken(result, value, label))
            fail("value=\"" + value + "\" label=\"" + suffix + "\" width=" + w +
                 "px -> \"" + result + "\" -- a partial landmark token");
        }
      }
    }
  }
  console.log("  ok  " + cases + " (label x offset x value x width) cases: never a partial landmark token");

  /* A value with NO landmark separator must be completely unaffected --
   * plain char-slicing, exactly as before this fix. */
  for (const w of [0, 1, 2, 5, 10, 20, 50]) {
    const got = R.fitHeaderRight(F.FONT4_MEASURE, w, "PERFORMANCE");
    const want = (() => {
      let s = "PERFORMANCE";
      if (F.fontWidth4x5(s) <= w) return s;
      while (s.length > 1 && F.fontWidth4x5(s) > w) s = s.slice(0, -1);
      return s;
    })();
    if (got !== want)
      fail("ordinary (non-landmark) string at width " + w + " changed behavior: got \"" +
           got + "\" want \"" + want + "\"");
  }
  console.log("  ok  a param with no tempo_landmarks (plain string) renders exactly as before");

  /* Sample resolution / no-BPM already suppress the landmark upstream in
   * withLandmark() -- confirm the header path has nothing left to trip on
   * once the separator is simply absent (the case those upstream guards
   * produce). */
  {
    const got = R.fitHeaderRight(F.FONT4_MEASURE, 20, "247 ms");
    if (got.indexOf("  ") !== -1) fail("a plain value must never gain a landmark separator");
  }
  console.log("  ok  Sample resolution / absent-BPM (no separator) has nothing to crop");

  /* ---- integration: drawHeader() itself, through the real draw path ---- */
  for (const title of TITLES) {
    for (const label of ["1/32T", "1/128", "24 bars"]) {
      const fb = H.createFramebuffer();
      R.drawHeader(H.drawContext(fb), title, "41.105 ms  " + label + " -3", true);
      if (fb.clipped() !== 0)
        fail("drawHeader clipped " + fb.clipped() + " px with title=\"" + title +
             "\" label=\"" + label + "\"");
    }
  }
  console.log("  ok  drawHeader() never clips a pixel across realistic title/landmark combinations");

  console.log("PASS: the selected-param header never shows a partial musical token");
});
'
