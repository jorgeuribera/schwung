#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

# SHIFT+JOG GOES TO AN END OF THE PAGE SET.
#
# Turn the jog right with Shift held and you land on the LAST page; left, on
# the FIRST. It replaces the old "jump a whole section" step: on a short module
# that step was the same as a plain jog, and on a long one the section picker
# (Shift+click) already reaches any section by name.
#
# The reason it exists: a chain component ends with the host's trailing pages
# ("My Presets", then "Module"), so the last page is the same place on every
# module and one notch gets you there. The module's OWN "Presets" browser is
# NOT a reliable target -- in the fleet fixtures it is the first page of its
# module 23 times in 26, the last twice and in the middle once (minijv) -- and
# part 5 pins that finding so nobody assumes otherwise.
#
# Driven through the real input path (decodeInput -> applyInput -> controller),
# with Shift as the gesture the hardware sends, not a call to a helper.
#
# NO APOSTROPHES inside the node script: single-quoted bash string.

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: node is required for the Shift+jog tests" >&2
  exit 1
fi

node -e '
Promise.all([
  import("./src/shared/param_pages/page_controller.mjs"),
  import("./src/shared/param_pages/page_input.mjs"),
  import("./src/shared/param_pages/page_nav.mjs"),
  import("./src/shared/param_pages/page_plan.mjs"),
  import("./tools/param-pages/fake_device.mjs"),
  import("node:fs"),
]).then(([C, I, N, P, D, fs]) => {
  let fail = 0;
  const ok = (c, m) => { console.log((c ? "  ok   " : "  FAIL ") + m); if (!c) fail++; };

  const cc = (d1, d2) => [0xb0, d1, d2];
  const JOG = 14;
  const RIGHT = 1, LEFT = 127;
  const TRAILING = [
    { name: "My Presets", entries: [{ label: "Preset", value: "(none)" }] },
    { name: "Module", entries: [{ label: "Swap" }, { label: "Remove" }] },
  ];

  const setup = (id, withTrailing) => {
    const dev = D.createFakeDevice({ id });
    const io = Object.assign({}, dev, withTrailing ? { trailingMenus: () => TRAILING } : {});
    const ctl = C.createController(io);
    ctl.load({ slot: 0, component: "synth" });
    return ctl;
  };
  /* One notch of the jog, as the hardware sends it, with Shift as given. */
  const turn = (ctl, dir, shift) => {
    const intent = I.decodeInput(cc(JOG, dir), { shift });
    I.applyInput(ctl, intent, { nowMs: Date.now(), reveal: false });
  };

  /* ---- 1. the pure rule ------------------------------------------------ */
  {
    const pages = [{}, {}, {}, {}, {}];
    ok(N.edgePage(pages, 1) === 4, "right goes to the last page");
    ok(N.edgePage(pages, -1) === 0, "left goes to the first page");
    ok(N.edgePage([], 1) === 0 && N.edgePage([], -1) === 0, "an empty set does not throw");
    ok(N.edgePage([{}], 1) === 0, "a single page is both ends");
    ok(N.edgePage(null, 1) === 0, "no page set does not throw");
  }

  /* ---- 2. the decode: Shift marks the jog coarse ----------------------- */
  {
    const plain = I.decodeInput(cc(JOG, RIGHT), { shift: false });
    const coarse = I.decodeInput(cc(JOG, RIGHT), { shift: true });
    ok(plain && plain.type === "page" && !plain.byLevel, "a plain jog is a one-page step");
    ok(coarse && coarse.type === "page" && coarse.byLevel === true && coarse.delta === 1,
       "Shift+jog right is the coarse gesture");
  }

  /* ---- 3. through the real controller, trailing pages and all ---------- */
  for (const id of ["obxd", "minijv", "granny"]) {
    const ctl = setup(id, true);
    const n = ctl.pages.length;
    const names = ctl.pages.map((p) => p.name);
    ok(n > 2, id + ": has pages (" + n + ")");
    ok(names[n - 1] === "Module" && names[n - 2] === "My Presets",
       id + ": the plan ends with My Presets, Module");
    turn(ctl, RIGHT, true);
    ok(ctl.pageIndex === n - 1 && ctl.page.name === "Module", id + ": Shift+jog right lands on the last page (Module)");
    turn(ctl, RIGHT, true);
    ok(ctl.pageIndex === n - 1, id + ": a second Shift+jog right stays on the last page (no wrap)");
    turn(ctl, LEFT, true);
    ok(ctl.pageIndex === 0, id + ": Shift+jog left lands on the first page");
    turn(ctl, LEFT, true);
    ok(ctl.pageIndex === 0, id + ": a second Shift+jog left stays on the first page (no wrap)");
    /* A plain jog is untouched: exactly one page. */
    turn(ctl, RIGHT, false);
    ok(ctl.pageIndex === 1, id + ": a plain jog still moves ONE page");
    turn(ctl, RIGHT, false);
    ok(ctl.pageIndex === 2, id + ": ...and again");
  }

  /* ---- 4. out of the middle of a long module, and out of a door -------- */
  {
    const ctl = setup("minijv", true);
    const n = ctl.pages.length;
    const start = ctl.pageIndex;
    for (let i = 0; i < 20; i++) turn(ctl, RIGHT, false);
    ok(ctl.pageIndex === start + 20, "minijv: twenty plain jogs move twenty pages (" + start + " -> " + ctl.pageIndex + ")");
    turn(ctl, RIGHT, true);
    ok(ctl.pageIndex === n - 1, "minijv: one Shift+jog from the middle reaches the last page of " + n);
    turn(ctl, LEFT, true);
    ok(ctl.pageIndex === 0, "minijv: one Shift+jog left from the end reaches page 0");

    /* An entered menu door keeps the plain jog for its list, and Shift+jog
       still pages out of it (the escape that must never go away). */
    const m = setup("obxd", true);
    turn(m, RIGHT, true);                       /* Module, the last page */
    const last = m.pageIndex;
    m.onClick(-1);                              /* enter the Module menu */
    ok(m.menuEntered() === true, "the Module menu is entered");
    turn(m, LEFT, true);
    ok(m.menuEntered() !== true && m.pageIndex === 0, "Shift+jog left pages out of an entered menu, to the first page");
    ok(last === m.pages.length - 1, "(and it was the last page)");
  }

  /* ---- 5. WHY the last page and not "the Presets page" ----------------- */
  {
    const fx = JSON.parse(fs.readFileSync("tests/fixtures/module-contracts.json", "utf8"));
    let first = 0, last = 0, middle = 0, withPreset = 0;
    for (const m of fx.modules) {
      const own = P.planPages({ hierarchy: m.ui_hierarchy, chainParams: m.chain_params }).pages;
      const k = own.findIndex((p) => p.kind === P.PAGE_PRESET);
      if (k < 0) continue;
      withPreset++;
      if (k === 0) first++; else if (k === own.length - 1) last++; else middle++;
    }
    ok(withPreset > 0, "some fixture modules have their own Presets page (" + withPreset + ")");
    ok(first > last + middle,
       "a module Presets page is usually the FIRST page, not the last (first " + first + ", last " + last + ", middle " + middle + ")");
    ok(last + middle > 0,
       "...and not always (so no gesture may promise to land on it)");
  }

  /* ---- 6. the footer says what the gesture does ------------------------ */
  {
    const src = fs.readFileSync("src/shadow/shadow_ui_param_pages.mjs", "utf8");
    ok(/jog = \(shift && controller\.pages[^)]*length > 1\) \? "ENDS" : "PAGE"/.test(src),
       "the footer advertises ENDS while Shift is down");
    ok(!/sectionsAreDistinct/.test(src), "the old SECT advertisement is gone");
  }

  process.exit(fail ? 1 : 0);
}).catch((e) => { console.log("FAIL: " + (e && e.stack || e)); process.exit(1); });
' && echo "PASS: shift+jog goes to the ends of the page set"
