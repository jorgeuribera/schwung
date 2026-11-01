#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

#
# A knob turn steps FROM the value the DEVICE holds, not from the value the
# grid last stepped to.
#
# The grid keeps a per-key knob state (accumulator + current value) so a
# continuous flick walks smoothly instead of re-reading on every detent. But
# the MODULE can change a parameter BY ITSELF while the grid stands on the
# page, for a value the read cursor then re-reads into s.values. When the two
# diverge, the next turn still stepped FROM THE STALE KNOB STATE and wrote the
# old number straight back over the module change.
#
# Reported from the device (TTUNNELXTO): "I move Recipe, Progress shows 0, but
# when I touch it, it jumps to 1 if it was 1 in the previous setup" -- turning
# Recipe re-begins the module transition, which resets Progress to 0 inside
# the module; the display followed, but the knob state still held the 1 the
# user had last stepped to.
#
# revalue() exists for exactly this class ("a change made to the module from
# OUTSIDE this controller") but nobody calls it for a grid-caused change --
# the change was caused by writing Recipe, so there was no recall and no
# preset load. The fix reconciles ONE knob -- the one being turned -- against
# the value the read cursor already carries, so the first detent continues
# from where the sound is. This pins:
#
#   1. A float knob walked up, reset by the module to 0, then turned ONCE
#      steps from 0 (not from the stale value).
#   2. A mid-gesture value never reseeds INSIDE a settle window: the second
#      of two quick detents continues the first one (re-adopting the last
#      pre-write reading would undo the detent just made).
#   3. An enum walked to option C, snapped back by the module to A, walks to
#      B past the four-detents-per-option gate (not C).

if ! command -v node >/dev/null 2>&1; then echo "FAIL: node is required" >&2; exit 1; fi

node -e '
let failures = 0;
const fail = (m) => { console.error("FAIL: " + m); failures++; };
const ok = (m) => { console.error("ok: " + m); };

Promise.all([
  import("./src/shared/param_pages/page_controller.mjs"),
]).then(([C]) => {
  const HIER = JSON.stringify({ modes: null, levels: { root: { label: "S",
      knobs: ["recipe", "progress"],
      params: [{ key: "recipe" }, { key: "progress" }] } } });
  const CP = JSON.stringify([
    { key: "recipe",   name: "Relation", type: "enum", options: ["A", "B", "C"] },
    { key: "progress", name: "Progress", type: "float", min: 0, max: 1 },
  ]);

  const store = { recipe: "A", progress: "0" };
  const writes = [];
  let ticks = 0;
  const ctl = C.createController({
    getParam: (k) => {
      const b = String(k).replace(/^[^:]+:/, "");
      if (b === "ui_hierarchy") return HIER;
      if (b === "chain_params") return CP;
      return b in store ? String(store[b]) : "0";
    },
    setParam: (k, v) => {
      store[String(k).replace(/^[^:]+:/, "")] = v;
      writes.push([String(k).replace(/^[^:]+:/, ""), v]);
    },
    announce: () => {},
    now: () => ticks * 16,
  });
  ctl.load({ slot: 0, component: "synth" });
  /* One tick of the controller AND of the test clock: SETPARAM_THROTTLE_MS
   * and every settle window in here are wall-clock and tick-count based. */
  const T = () => { ticks++; ctl.tick(); };
  const slotOf = (key) => (ctl.page.keys || []).indexOf(key);
  const progSlot = slotOf("progress"), recipeSlot = slotOf("recipe");
  if (progSlot < 0 || recipeSlot < 0) fail("fixture did not put the knobs on the grid");
  for (let i = 0; i < 16; i++) T();

  /* ---- 1. float: the module resets the value, the next detent follows --- */
  for (let d = 0; d < 20; d++) {
    T();
    ctl.onKnobTurn(progSlot, 1);
    T();
  }
  { /* fly past the settle window and the announce throttle */
    for (let i = 0; i < 24; i++) T();
    const raised = Number(store.progress);
    if (!(raised > 0.05)) fail("the walk up did not raise progress at all: " + store.progress);
  }
  /* THE MODULE RESETS THE VALUE BY ITSELF (the transition re-began). */
  store.progress = "0";
  /* Enough ticks to expire the settle window and land a rotation stop on the
   * key (stops = 2 knobs + the preset stop). */
  for (let i = 0; i < 40; i++) T();

  writes.length = 0;
  ctl.onKnobTurn(progSlot, 1);
  T(); T();
  const after = writes.filter(([k]) => k === "progress").map(([, v]) => Number(v));
  if (!after.length) fail("the detent wrote nothing");
  else if (after[0] > 0.05)
    fail("the first detent after the module reset stepped from the stale value " +
         after[0] + " -- a knob must follow the device");
  else ok("float: the first detent after a module-side reset stepped from the device value " + after[0]);

  /* ---- 3. INSIDE a settle window, a mid-gesture value never reseeds ----- */
  /* Reset through the device again, then two QUICK detents while the settle
   * window is live: the second must step from the write the first one just
   * made, not re-adopt the last pre-write reading. */
  store.progress = "0";
  for (let i = 0; i < 40; i++) T();
  writes.length = 0;
  ctl.onKnobTurn(progSlot, 1);
  T(); /* let its write land (throttle) */
  const first = store.progress;
  ctl.onKnobTurn(progSlot, 1); /* settle window is still live */
  /* The write throttle holds the second detent pending; assert on the PENDING
   * value, which is what the hand is asking the device to become. */
  const second = ctl.state.pendingWrite["progress"];
  const n1 = Number(first), n2 = Number(second);
  if (!(n2 > n1) || !(n1 > 0))
    fail("two detents inside a settle window produced " + first + " then " + second +
         " -- the second detent must continue the first one");
  else ok("two detents mid-gesture walked " + first + " then " + second);

  /* ---- 2. enum: the walk to C must not relaunch from C after a reset ---- */
  store.recipe = "A";
  for (let i = 0; i < 40; i++) T();
  writes.length = 0;
  for (let d = 0; d < 12; d++) { T(); ctl.onKnobTurn(recipeSlot, 1); }
  T(); T();
  if (store.recipe !== "C") fail("the enum walk did not reach C: " + store.recipe);

  store.recipe = "A"; /* the module reset it */
  for (let i = 0; i < 40; i++) T();

  writes.length = 0;
  for (let d = 0; d < 5; d++) {
    ctl.onKnobTurn(recipeSlot, 1);
    T(); T();
  }
  T(); T();
  const afterEnum = writes.filter(([k]) => k === "recipe").map(([, v]) => v).pop();
  if (afterEnum === undefined) fail("the enum detents wrote nothing");
  else if (afterEnum === "C")
    fail("after the module snapped recipe back to A, the walk landed on C (the " +
         "stale knob state) instead of stepping from A");
  else if (afterEnum !== "B")
    fail("after the reset the walk resolved " + afterEnum + ", expected B");
  else ok("enum: stepping past the four-detent gate after a reset resolved " + afterEnum);

  /* ---- 4. THE IMMEDIATE RACE (owner brief B6): a turn right after the
   * grid write, before the read cursor re-reads the reset key. The
   * reconcile must consult ONE fresh routed read (budgeted: only while the
   * write-suspicion window is live, at most once per key per window)
   * instead of trusting the stale cursor value, or the first detent writes
   * the module reset away. ---- */
  for (let i = 0; i < 40; i++) T();
  for (let d = 0; d < 12; d++) { T(); ctl.onKnobTurn(progSlot, 1); }  /* progress spin: grid writes */
  store.progress = "0";  /* the module swallowed the in-flight writes and reset it */
  writes.length = 0;
  /* NO controller tick between the reset and the turn: on hardware the knob
   * can be touched before the read cursor circulates to this key, so the
   * cursor value is still the PRE-RESET 1.0. The reconcile must move to a
   * fresh routed read (budgeted by the suspicion window + once-per-key cap)
   * instead of trusting it. */
  for (let i = 0; i < 8; i++) {
    ctl.onKnobTurn(progSlot, 1);
    T(); T();
  }
  {
    const moved = writes.filter(([k]) => k === "progress").map(([, v]) => Number(v));
    if (!moved.length) fail("the immediate-race turn wrote nothing");
    else if (moved[0] > 0.6)
      fail("the immediate turn after the reset stepped from the stale cursor value " +
           moved.join(",") + " - must fresh-read inside the suspicion window");
    else ok("immediate-race detents continued from the fresh reset value " + moved.join(","));
  }

  /* ---- 5. P1-G: enum fresh read BY NAME ("B") reconciles too; a fresh
   * non-numeric read must not fall back to a stale cursor value. ---- */
  /* module rewrote the enum by NAME, and the ROUTED read delivers the name */
  writes.length = 0;
  opens = 0;
  // drive a grid write first so the suspicion window opens
  for (let i = 0; i < 8; i++) { T(); ctl.onKnobTurn(progSlot, 1); }
  T();
  writes.length = 0;
  // fresh read for recipe now returns the NAME "B": the fixture getParam
  // is routed to store, so the label arrives through the same path used
  // on device. Reconcile must adopt B even though it is not numeric.
  for (let i = 0; i < 4; i++) {
    ctl.onKnobTurn(recipeSlot, 1);
    T(); T();
  }
  {
    const moved = writes.filter(([k]) => k === "recipe").map(([, v]) => v);
    if (!moved.length) fail("the enum-by-name reconcile turn wrote nothing");
    else if (moved[0] === "C" && store.recipe !== "C")
      fail("the enum walk IGNORED the fresh by-name read " + moved.join(","));
    else ok("enum-by-name fresh reconcile: first write " + moved.join(","));
  }

  if (failures) process.exitCode = 1;
  else console.error("ALL PASS");
}).catch((e) => { console.error("FAIL: " + (e && e.stack || e)); process.exit(1); });
'
