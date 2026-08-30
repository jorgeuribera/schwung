#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

# A module may derive one param's KNOB CONTROL LAW from another param -- an
# Edit Speed or a Time Curve enum that republishes `knob_step_frac` /
# `knob_curve` / `knob_curve_gamma` on the time params. Turning that enum
# therefore republishes the contract, exactly as picking a soundfont does.
#
# Nothing re-read the contract for it, because the only paths that do are
# `selectionChanged` (a list/preset pick) and a full page re-entry. So on
# real hardware you could turn Time Curve from Linear to Low Medium, walk
# over to the time knob, and still be turning the LINEAR law until you left
# the parameter pages entirely and came back. The curve would look broken.
#
# This is deliberately NOT the moving-window refresh that stalled on
# hardware, and the difference is the point:
#
#   that one re-read WHILE THE TIME KNOB WAS MOVING, continuously, per
#   gesture, because the metadata depended on that knob's own current
#   value -- so the window had to be re-anchored under the hand and every
#   re-anchor was a chance to clamp or to jump;
#
#   this re-reads because a DIFFERENT, discrete control was turned, once,
#   after the hand stops (maybeSettleContract defers while a finger is
#   down and requires two agreeing readings). The time value itself never
#   enters metadata, so there is nothing to re-anchor and nothing that can
#   move a value.
#
# A module that declares no control law must pay nothing at all -- the gate
# is per contract, not per gesture.

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: node is required for the knob-law refresh tests" >&2
  exit 1
fi

node -e '
Promise.all([
  import("./src/shared/param_pages/page_controller.mjs"),
  import("./src/shared/param_pages/param_meta.mjs"),
  import("./tools/param-pages/fake_device.mjs"),
]).then(([C, M, D]) => {
  const fail = (msg) => { console.log("FAIL: " + msg); process.exit(1); };
  /* Comfortably past the deadline and every one of its bounded retries. */
  const SETTLED_MS = C.CONTRACT_SETTLE_MS * (C.CONTRACT_SETTLE_RETRIES + 2);
  const settle = (ctl, dev, ms) => {
    for (let t = 0; t < ms; t += 10) { dev.advance(10); ctl.tick(); }
  };

  const CURVE_OPTIONS = ["Linear", "Low Soft", "Low Medium", "Low Strong",
                         "High Soft", "High Medium", "High Strong"];
  /* Index 0 is Linear, which ships as the ABSENCE of knob_curve. */
  const lawFor = (i) => {
    if (i === 0) return null;
    return { mode: i <= 3 ? "low_focus" : "high_focus",
             gamma: [1.6, 2.0, 2.4][(i - 1) % 3] };
  };

  /*
   * A contract in the shape the time modules actually publish: one time
   * param whose control law is derived from one enum. Keys are the
   * fixture'"'"'s own, so the captured ui_hierarchy places them on a real page.
   */
  const buildContract = (withLaw) => ([
    { key: "param_0", name: "Boundary", type: "float", min: 0, max: 4000, step: 1,
      ...(withLaw ? { knob_step_frac: 0.005 } : {}) },
    { key: "param_1", name: "Time Curve", type: "enum", options: CURVE_OPTIONS },
    { key: "param_2", name: "Open", type: "float", min: 0, max: 1 },
  ]);

  /* The controller captured getParam by value in the spread above, so the
     derived contract stays live for the controller while `dev.getParam`
     (used only by the assertions) is the raw one. Re-point both at the
     derived implementation so the two never disagree mid-test. */
  const openDevice = (withLaw) => {
    const dev = D.createFakeDevice({ id: "clap", prefix: "fx1" });
    dev.setServesIsLoading(false);
    dev.store.param_1 = "0";
    const derived = (key) => {
      const inner = dev.__inner;
      if (key !== "fx1:chain_params") return inner(key);
      const i = Math.max(0, Math.min(CURVE_OPTIONS.length - 1,
                                     parseInt(dev.store.param_1 ?? "0", 10) || 0));
      const law = withLaw ? lawFor(i) : null;
      const cp = buildContract(withLaw).map((p) => {
        if (p.key !== "param_0" || !withLaw || !law) return p;
        return { ...p, knob_curve: law.mode, knob_curve_gamma: law.gamma };
      });
      return JSON.stringify(cp);
    };
    dev.__inner = dev.getParam;
    dev.getParam = derived;
    const ctl = C.createController({ ...dev, now: dev.now });
    return { dev, ctl };
  };

  const metaOf = (ctl, key) => ctl.state.metaIndex.getOrGuess(key);
  const lawOf = (ctl) => {
    const m = metaOf(ctl, "param_0");
    return m.knob_curve ? `${m.knob_curve}@${m.knob_curve_gamma}` : "linear";
  };
  /* Slot 1 is whichever key sits second on the knobs page. Asserted, not
     assumed: reading a curve off the wrong cell would pass by accident. */
  const slotOf = (ctl, key) => {
    const p = (ctl.pages || []).find((q) => q.kind === "knobs");
    if (!p) fail("no knobs page was planned");
    const i = p.keys.indexOf(key);
    if (i < 0) fail(`contract key ${key} is not on the knobs page`);
    return i;
  };

  /* ---- 0. declaresKnobLaw: the gate, on its own ------------------------ */
  {
    if (typeof M.declaresKnobLaw !== "function")
      fail("param_meta.mjs exports no declaresKnobLaw");
    if (M.declaresKnobLaw(null) !== false) fail("declaresKnobLaw(null) must be false");
    if (M.declaresKnobLaw({}) !== false) fail("declaresKnobLaw({}) must be false");
    /* keys is the real metaIndex shape: a plain ARRAY, not callable. A helper
       written against a callable `keys()` would read every contract as
       declaring nothing, and the gate would silently never open. */
    const flat = { keys: ["a"], get: () => ({ type: "float", min: 0, max: 1 }) };
    if (M.declaresKnobLaw(flat) !== false)
      fail("a contract with no knob_step_frac and no knob_curve declares no law");
    const speed = { keys: ["a", "b"],
                    get: (k) => (k === "a" ? { knob_step_frac: 0.005 } : null) };
    if (M.declaresKnobLaw(speed) !== true)
      fail("knob_step_frac alone declares a law");
    const curve = { keys: ["a"], get: () => ({ knob_curve: "low_focus" }) };
    if (M.declaresKnobLaw(curve) !== true)
      fail("knob_curve alone declares a law");
    /* An exact-declared-unit edit speed republishes knob_step_mode instead
       of knob_step_frac/knob_curve -- dropping the range-fraction law
       entirely, not merely changing its value, is exactly as much a law
       change and must re-arm the settle just the same. */
    const unit = { keys: ["a"], get: () => ({ knob_step_mode: "declared" }) };
    if (M.declaresKnobLaw(unit) !== true)
      fail("knob_step_mode alone declares a law");
  }

  /* ---- 1. THE BUG: turning the curve enum republishes the law ---------- */
  {
    const { dev, ctl } = openDevice(true);
    ctl.load({ slot: 0, component: "fx1", prefix: "fx1" });
    if (slotOf(ctl, "param_1") < 0) fail("Time Curve is not on the page");
    if (lawOf(ctl) !== "linear")
      fail("expected the linear law at load, got " + lawOf(ctl));

    const slot = slotOf(ctl, "param_1");
    /* An enum is gated at four detents per option (ENUM_DELTA_DIV), so a
       single turn is not a step -- turning one detent and expecting the
       option to change would assert nothing at all. */
    const DETENTS_PER_OPTION = 4;
    const spin = (ctl, dev, slot, steps) => {
      for (let d = 0; d < Math.abs(steps) * DETENTS_PER_OPTION; d++) {
        ctl.onKnobTurn(slot, steps > 0 ? 1 : -1, dev.now());
        dev.advance(20);
        ctl.tick();
      }
    };
    /* Three consecutive changes, because one step can be right by luck. */
    let cur = 0;
    for (const step of [1, 4, 2]) {
      spin(ctl, dev, slot, step - cur);
      cur = step;
      settle(ctl, dev, SETTLED_MS);
      const i = parseInt(dev.store.param_1, 10);
      const law = lawFor(i);
      const want = law ? `${law.mode}@${law.gamma}` : "linear";
      if (lawOf(ctl) !== want)
        fail(`THE BUG: after ${step} turn(s) the enum reads ${i} but the ` +
             `knob law is "${lawOf(ctl)}", want "${want}"`);
      if (i !== step)
        fail(`the enum did not land on ${step}, store says ${dev.store.param_1}`);
    }
  }

  /* ---- 2. commitEnum (the picker path) republishes it too -------------- */
  {
    const { dev, ctl } = openDevice(true);
    ctl.load({ slot: 0, component: "fx1", prefix: "fx1" });
    ctl.commitEnum("param_1", 6);          /* High Strong */
    settle(ctl, dev, SETTLED_MS);
    if (lawOf(ctl) !== "high_focus@2.4")
      fail("commitEnum did not republish the law, got " + lawOf(ctl));
  }

  /* ---- 3. a contract with NO control law pays nothing ------------------ */
  {
    const { dev, ctl } = openDevice(false);
    ctl.load({ slot: 0, component: "fx1", prefix: "fx1" });
    const slot = slotOf(ctl, "param_1");
    const before = dev.readsFor("chain_params");
    for (let i = 0; i < 6; i++) {
      for (let d = 0; d < 4; d++) { ctl.onKnobTurn(slot, 1, dev.now()); dev.advance(20); ctl.tick(); }
      settle(ctl, dev, SETTLED_MS);
    }
    const spent = dev.readsFor("chain_params") - before;
    if (spent !== 0)
      fail(`a contract with no knob law cost ${spent} extra chain_params ` +
           "reads on six enum turns; the gate is not per-contract");
  }

  /* ---- 4. a fast spin costs O(1) reads, not one per detent ------------- */
  {
    const { dev, ctl } = openDevice(true);
    ctl.load({ slot: 0, component: "fx1", prefix: "fx1" });
    const slot = slotOf(ctl, "param_1");
    const before = dev.readsFor("chain_params");
    /* 40 detents inside one settle window, as a spin down the curve list. */
    for (let i = 0; i < 40; i++) {
      ctl.onKnobTurn(slot, 1, dev.now());
      dev.advance(30);            /* a brisk 33 detents a second */
      ctl.tick();
    }
    settle(ctl, dev, SETTLED_MS);
    const spent = dev.readsFor("chain_params") - before;
    if (spent > 4)
      fail(`a 40-detent jog cost ${spent} contract reads; the deadline is not ` +
           "being re-armed per detent");
    const i = parseInt(dev.store.param_1, 10);
    const law = lawFor(i);
    if (lawOf(ctl) !== (law ? `${law.mode}@${law.gamma}` : "linear"))
      fail("the settle after a fast jog did not land: " + lawOf(ctl));
  }

  /* ---- 5. switching the curve never moves the value -------------------- */
  {
    const { dev, ctl } = openDevice(true);
    ctl.load({ slot: 0, component: "fx1", prefix: "fx1" });
    const slot = slotOf(ctl, "param_1");
    /* Boundary at 347 ms: the canonical value the whole exercise exists to
       protect. A curve that is metadata must leave it alone. */
    dev.store.param_0 = "347";
    const written = () => (dev.writes.filter((w) => w[0] === "fx1:param_0")
                                     .map((w) => w[1]));
    /* 8 detents = two whole options, so the curve really did change. */
    for (let d = 0; d < 8; d++) { ctl.onKnobTurn(slot, 1, dev.now()); dev.advance(20); ctl.tick(); }
    settle(ctl, dev, SETTLED_MS);
    if (parseInt(dev.store.param_1, 10) !== 2)
      fail("the curve enum did not move (store says " + dev.store.param_1 +
           "), so the assertion below would pass for the wrong reason");
    if (written().length)
      fail("switching Time Curve wrote the time param: " + written().join(","));
  }

  /* ---- 6. the settle defers under a finger ----------------------------- */
  {
    const { dev, ctl } = openDevice(true);
    ctl.load({ slot: 0, component: "fx1", prefix: "fx1" });
    const slot = slotOf(ctl, "param_1");
    for (let d = 0; d < 4; d++) { ctl.onKnobTurn(slot, 1, dev.now()); dev.advance(20); ctl.tick(); }
    /* A hand still on the knob: the rebuild must wait, not blank the cell. */
    ctl.onKnobTouch(slot, true);
    settle(ctl, dev, SETTLED_MS);
    if (lawOf(ctl) !== "linear")
      fail("the contract was rebuilt while a finger was down");
    ctl.onKnobTouch(slot, false);
    settle(ctl, dev, SETTLED_MS);
    const i = parseInt(dev.store.param_1, 10);
    const law = lawFor(i);
    if (lawOf(ctl) !== (law ? `${law.mode}@${law.gamma}` : "linear"))
      fail("the deferred settle never landed after release: " + lawOf(ctl));
  }

  console.log("PASS knob-law contract refresh: an enum that republishes knob_step_frac/knob_curve re-arms the settle");
}).catch((e) => { console.log("FAIL: " + (e && e.stack ? e.stack : e)); process.exit(1); });
'
