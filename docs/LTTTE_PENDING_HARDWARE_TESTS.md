# LTTTE pending hardware tests — v1.7.3 port

First-class record of every feature carried ACTIVE in
`integration/lttte-schwung-v1.7.3` that has not received physical Move
validation since being ported onto the v1.7.3 baseline (the same list was first
written for `integration/lttte-schwung-v1.3.1`; see `docs/LTTTE_PORT_TO_V1.7.3.md`
for what changed in the port, and read the source commit hashes below as the
v1.3.1-branch hashes — the v1.7.3 cherry-picks carry `(cherry picked from ...)`
trailers). Cross-references
`docs/LTTTE_CUSTOM_SCHWUNG_INVENTORY.md` for full commit/file detail; this
document is the test plan, that one is the provenance record.

**v1.7.3 port, items that need extra attention on hardware** (all else is as
originally written): item 5 (the contract-refresh hook now sits in `commitEnum`
after upstream refactored the cache-write path), item 7 (re-check every
Shift+Click gesture, upstream added new Shift gestures between v1.3.1 and
v1.7.3), item 8 (`CONTROL_BUFFER_SIZE` is now 512, so the shim and shadow_ui
must be deployed together; the capture-ring log has new fields).

**Do not remove any of this code because a physical test has not happened.**
Every item below is `ACTIVE_SW_VERIFIED_PENDING_HW` in the reconciled
baseline, software-tested, and carried forward deliberately.

---

## 1. Declared knob-step mode

- **Source**: `feature/declared-knob-step` (`30223387`, `1221c7e2`), ported
  as `9204c9ce`/`8dd91261` on `integration/lttte-schwung-v1.3.1`.
- **Why it exists**: a delay/time parameter whose musically-meaningful unit
  IS its declared `step` (not a range-normalised fraction) needs the knob to
  move by exactly that step, with exact endpoints.
- **Software evidence**: 156 checks (`test_declared_knob_step.sh`) + 125
  checks (`test_fine_step_display_precision.sh`), both re-run green on the
  reconciled branch.
- **Physical setup required**: any Move running the reconciled package, one
  chain slot loaded with a module that declares `knob_step_mode: "declared"`
  on at least one float param with a non-trivial `step` (e.g. `step: 0.3`).
  If no shipped module declares it yet, a throwaway test module (mirroring
  `contract-probe/`) declaring one such param is the fastest path.
- **Exact test procedure**:
  1. Open the param page for the declared-step param.
  2. Turn the knob one detent in each direction; confirm the value moves by
     exactly `step` each time (read via the on-screen value, cross-checked if
     possible against the module's own log).
  3. Turn continuously toward `max`; confirm the value lands exactly on `max`
     rather than stopping a fraction short.
  4. Shift+turn (fine); confirm the fine increment is `step`/10, floored to
     one whole unit for an int param.
  5. If the param uses a non-integer step like `0.3`, confirm the on-screen
     display distinguishes 0.03/0.06/0.09 fine-adjust steps (the bug
     `1221c7e2` fixed) rather than all rendering as "0.0"/"0.1"/"0.1".
- **Expected success**: exact-step motion, exact endpoint reachability,
  distinguishable fine-adjust display.
- **Expected failure**: any acceleration/narrow-range gating bleeding in
  (would indicate the declared-step branch isn't fully bypassing the
  range-normalised path), or the display bug recurring.
- **Rollback procedure**: the feature is fully opt-in (`knob_step_mode`
  metadata field) — no rollback needed beyond not declaring the field; the
  reconciled branch's default (undeclared) behavior is byte-identical to
  v1.3.1 stock, per the commit's own design note.
- **Status**: not yet attempted. **Date last attempted**: never (new to this
  baseline as of 2026-09-08).

## 2. Response curves (`knob_curve`)

- **Source**: `feature/knob-response-curves` (`72d6f9ac`), ported as
  `6af2a7b8`.
- **Why it exists**: redistributes a wide range's fixed ~200-detent travel
  toward one end (e.g. the 0-20ms comb/flanger region of a 4000ms delay time)
  without narrowing the declared range.
- **Software evidence**: 2654 checks (`test_knob_response_curve.sh`),
  re-run green.
- **Physical setup required**: a module/param declaring `knob_curve:
  "low_focus"` (or `"high_focus"`) with `knob_curve_gamma` set to something
  visibly non-1 (e.g. 2.4) on a wide-range float, e.g. a delay time 0..4000ms.
- **Exact test procedure**:
  1. Set the value near the focused end (e.g. near 0 for `low_focus`);
     confirm each detent moves the value by a visibly SMALL amount.
  2. Set the value near the far end; confirm each detent moves by a visibly
     LARGER amount, bounded — per the design doc — at roughly `gamma`× the
     unfocused (linear) per-detent step, not runaway.
  3. Switch curve direction or turn off the curve mid-session (if the test
     module allows); confirm the value itself does not jump (only the
     per-detent behavior changes) — this is the "u recovered from the current
     value" guarantee.
  4. Turn continuously to both `min` and `max`; confirm both are exactly
     reachable, not merely approached.
- **Expected success**: smoothly variable per-detent resolution matching the
  gamma/direction, no value jump on curve change, exact endpoints.
- **Expected failure**: a value jump when the curve is applied/changed (would
  indicate the inverse-recovery math is wrong), or an unbounded/runaway
  detent size at the coarse end.
- **Rollback procedure**: opt-in metadata field; undeclared behavior is
  byte-identical to stock.
- **Status**: not yet attempted. **Date last attempted**: never.

## 3. Knob edit-speed (`knob_step_frac`)

- **Source**: `feature/knob-step-frac` (`a0824966`), ported as `90b931c8`.
- **Why it exists**: a Micro/Normal/Long sensitivity switch that does NOT
  narrow `min`/`max` (the approach that caused the archived moving-window
  mechanism's hardware stall — see item 6 below) — instead it's a fixed
  detent-budget over the SAME declared range.
- **Software evidence**: 58692 checks (`test_knob_step_frac.sh`), re-run
  green.
- **Physical setup required**: a module/param exposing a switchable
  `knob_step_frac` (e.g. via an Edit Speed enum, see item 5) on a wide-range
  float.
- **Exact test procedure**:
  1. At the default/Normal speed, count roughly how many detents cross the
     full range (spot-check against the documented ~200).
  2. Switch to a Micro speed (smaller `knob_step_frac`, e.g. 0.002); confirm
     visibly MORE detents are needed to cross the same range, at the SAME
     relative shape as before (same curve, if any, is still applied).
  3. Switch to Long (larger `knob_step_frac`, e.g. 0.0125); confirm visibly
     FEWER detents cross the range.
  4. Confirm switching speed mid-session does not move the current value.
- **Expected success**: detent count scales inversely with `knob_step_frac`,
  value stable across a speed switch.
- **Expected failure**: any range-narrowing behavior recurring (the
  moving-window symptom), or a value jump on speed switch.
- **Rollback procedure**: opt-in; undeclared default is stock ~200 detents.
- **Status**: not yet attempted. **Date last attempted**: never.

## 4. Tempo landmarks + header-crop fix

- **Source**: `feature/tempo-landmarks` (`bd8f6bbe`),
  `feature/tempo-landmark-header-layout` (`280eafe0`), ported as `8ce1a38b`/
  `dcc9920d`.
- **Why it exists**: prints the nearest rhythmic value beside a free
  (non-quantised) time parameter, as pure information — never snaps/pulls the
  actual value. `280eafe0` specifically fixes a **hardware-reported** header
  truncation bug.
- **Software evidence**: 343 checks (`test_tempo_landmarks.sh`, including the
  sample-count cases added by item 5) + 133 checks
  (`test_header_landmark_atomicity.sh`), re-run green.
- **Physical setup required**: any module/param declaring
  `tempo_landmarks: true` on a free `ms` (or `sec`/`smp`) time param, with
  Move transport running at a known BPM.
- **Exact test procedure**:
  1. Hold the param at a value near a straight note (e.g. 250ms at 120 BPM,
     an eighth note); confirm the header/list shows the landmark label
     ("1/8") with a signed offset when slightly off, and no label when
     exactly on it.
  2. Sweep the value continuously through several landmarks; confirm the
     shown label updates and the KNOB MOTION is completely unaffected — no
     detent, no snap, no hesitation at a landmark.
  3. **Specifically re-check the header-crop bug**: set a value whose full
     label string is long (a triplet/dotted label with a large offset, e.g.
     "41.105 ms  1/32T -12"), on a page where the header is tight (a long
     module/page title). Confirm the full landmark token is either shown
     whole or dropped entirely — never truncated mid-token (the exact
     hardware-reported symptom: "41.105 ms  1" was the old bug shape).
  4. Stop the transport; confirm landmarks still show against the last known
     tempo (not hidden just because playback stopped).
- **Expected success**: accurate, motion-unaffecting landmark display; no
  mid-token truncation under any header width.
- **Expected failure**: any detent/snap coupling to a landmark (would be a
  serious regression against the design's core promise), or truncation
  recurring.
- **Rollback procedure**: opt-in metadata field; undeclared default is stock.
- **Status**: not yet attempted (the header-crop fix specifically needs
  re-confirmation post-port, since the merge with upstream's new `padIcon`
  right-edge budget changed the exact width arithmetic — see inventory item
  5's conflict detail). **Date last attempted**: never on this baseline.

## 5. Knob-law contract refresh + exact-unit edit-speed composition

- **Source**: `53eee201`/`ed1da083`, `6fffbff7`, ported as `a4d3db0f`/
  `ed90d1b4`/`635789b7`.
- **Why it exists**: an "Edit Speed"/"Time Curve" enum that rewrites another
  param's `knob_step_frac`/`knob_curve` needs the CHANGE to take effect
  immediately, without exiting and re-entering the page.
- **Software evidence**: 260+7 checks (`test_knob_law_contract_refresh.sh`),
  re-run green. The companion Fractional+Micro+Shift-fine guard
  (`test_fractional_micro_shift.sh`) protects behavior **`6fffbff7`'s own
  message records as already physically re-confirmed** (100.000→100.800ms
  observed on hardware) — the one item in this whole reconciliation with a
  post-fix hardware confirmation on record.
- **Physical setup required**: a module exposing an Edit-Speed/Time-Curve
  enum alongside the time param(s) it governs.
- **Exact test procedure**:
  1. With the enum at one setting, turn the governed knob; note its feel
     (speed/curve).
  2. Turn the enum to a different setting; WITHOUT leaving the page, turn the
     governed knob again; confirm the NEW feel applies immediately.
  3. Repeat rapidly (spin the enum through several options quickly); confirm
     each turn re-arms correctly and the final feel matches the final enum
     setting (not a stale one).
  4. Re-confirm the Fractional/Micro/Shift-fine case specifically: set
     Fractional resolution + Micro edit speed, hold Shift, turn one detent;
     confirm the value moves by a genuine fraction (e.g. 100.000→100.800ms),
     not rounded to a whole ms.
- **Expected success**: immediate feel change on enum turn, correct
  fractional shift behavior.
- **Expected failure**: feel only updating after page exit/re-entry (the
  original bug), or a return to whole-ms rounding.
- **Rollback procedure**: purely additive re-arm call; no metadata opt-out
  needed since it only fires when `declaresKnobLaw()` is true.
- **Status**: not yet attempted on THIS baseline (the fractional-shift
  guard's own PRIOR hardware confirmation was on the pre-reconciliation
  build, not re-verified post-port). **Date last attempted**: the fractional
  guard was confirmed on hardware prior to 2026-08-30 (exact date not
  recorded in the commit); not re-attempted since.

## 6. `live_params`/`changes_contract` moving-window — ARCHIVED, do not retest without new evidence

- **Source**: `archive/live-params-moving-window-hardware-failed-2026-08-30`
  — NOT ported, NOT active.
- **Why it exists (historically)**: an attempt to live-refresh a param whose
  own contract (min/max) moves with its current value, under continuous
  touch.
- **Software evidence**: full synthetic suite + a realistic stale/lag
  regression passed.
- **Physical setup that was used**: continuous touch on a real encoder,
  multiple generations retried.
- **Result**: **FAILED, repeatedly, and worsened across retries** — the
  archive commit's own words: "the final [`1cc1536a`] generation stalled
  earlier than the previous physical test." This is not a case of
  insufficient testing; it is a case of testing revealing the approach itself
  doesn't work.
- **Do NOT re-attempt this mechanism** without a genuinely new, concrete
  hardware-level root-cause finding — per the explicit instruction governing
  this special case. If a future need for a moving-contract window
  re-emerges, start from `EXPERIMENTAL_LIVE_PARAMS.md` on the archive branch
  for the full prior analysis rather than re-deriving it.
- **Status**: archived, intentionally not scheduled.

## 7. Delete+JogClick device removal / Fine Lock

- **Source**: `feature/chain-editor-shortcuts` (`cf0a6790`),
  `integration/fine-lock-scope-2026-08-30` (`b9ed7cb3`), ported as
  `c3ac069e`/`c81f820c`.
- **Why it exists**: two independent performance-surface additions — a
  direct device-removal gesture, and a double-tap Fine Lock latch scoped
  strictly to parameter-fine-adjust paths (not general Shift navigation).
- **Software evidence**: `test_delete_jogclick_remove.sh` (5 checks),
  `test_shift_lock.sh` (5 groups, rewritten by `b9ed7cb3` to pin the
  corrected physical/Fine split), both re-run green — including after this
  pass's OWN fix extending the physical-Shift invariant to upstream's new
  `BUS_CHAIN` module-select gesture (see inventory item 7's conflict detail).
- **Physical setup required**: any Move with the reconciled package, both a
  slot chain and a Master FX/Send bus chain each with at least 2-3 modules
  loaded (to have something removable/reorderable without emptying the whole
  chain).
- **Exact test procedure**:
  1. **Delete+JogClick**: select a populated module in the slot chain, hold
     Delete(X), click the jog; confirm it's removed exactly as "Remove
     Module" from the grid menu would do (same resulting chain shape), and a
     screen-reader/announce fires "Removed &lt;label&gt;". Repeat on a Master FX
     slot.
  2. Confirm the pre-existing Mute+JogClick bypass-toggle gesture still works
     unchanged, on the same slot.
  2a. **Delete footer** (added after the gesture was confirmed on hardware):
     on a populated device in the slot chain, HOLD Delete without clicking;
     the footer must change at once from `JOG SEL / CLK OPEN / BACK EXIT` to
     `JOG SEL / CLK DELETE`, and go back when Delete is released. Same on the
     synth box. On a `+`, on the chain/patch box and on Settings, holding
     Delete must NOT change the footer (the click does the normal thing
     there). Repeat on Master FX (resting footer ends in `BACK BUS`). With
     Shift AND Delete held, the footer must be the Shift one (`JOG MOVE /
     CLK SWAP`).
  2b. **Removal confirmation**: Delete+click a device; the footer row must
     show `REMOVED <MODULE NAME>` (a single centred pill) while the boxes,
     label and info line above stay fully visible (nothing drawn over them).
     It must disappear on its own after ~1.5 s; repeat and check it also
     disappears AT ONCE on a jog turn, on Back, and on a step press; and that
     letting go of Delete, or just resting a finger on the jog, does NOT
     dismiss it. Check that the name is the module's (not "FX 1"). Repeat on
     Master FX. Check a long module name is cut, not run off the screen.
     Also check that a fresh Delete PRESS dismisses it (Delete no longer
     arrives as MIDI; the UI follows the shim's `delete_held` byte).
  2c. **Delete released with the UI hidden** (the bug Charles reproduced on
     #662's first revision, fixed by reading `shadow_get_delete_held()`
     instead of a JS flag fed by CC 119, and reverting the shim forward of
     `8588435c`): open a slot chain editor with a module on FX1, cursor on
     it; press and HOLD Delete; tap Menu to dismiss the shadow UI; release
     Delete on Move's screen; reopen the chain editor and do a PLAIN jog
     click on that module. It must OPEN the module (no removal, no
     `REMOVED` notice). Repeat on Master FX. Then re-confirm step 1 (the
     gesture still fires with the forward gone) and that a module that does
     not claim the edit CCs (e.g. mrdrums with child levels) does NOT arm
     "Clear: pick a target" when Delete is held in its knob grid.
  3. **Fine Lock**: double-tap Shift; confirm the on-screen `FINE LOCK / ON`
     panel appears and a persistent `KNB LOCK` footer indicator shows.
  4. With Fine Lock latched, enter a parameter-fine-adjust path (e.g. a knob
     card / declared-step fine adjust) WITHOUT holding Shift; confirm fine
     precision is active from the latch alone.
  5. With Fine Lock latched, test a NAVIGATION gesture that used to read
     general Shift (Shift+Click to enter Master FX module select, Shift+Click
     to enter Bus module select, Shift+Click in chain edit) — confirm these
     do NOT fire from the latch alone; they must still require physically
     holding Shift. This is the exact invariant `b9ed7cb3` establishes and
     this pass extended to the Bus case.
  6. Leave the parameter-editing scope (back out to chain edit, say); confirm
     Fine Lock clears automatically.
  7. Double-tap Shift again to unlatch manually; confirm it clears
     immediately.
- **Expected success**: device removal matches the menu path exactly; Fine
  Lock affects only fine-adjust paths, never navigation; auto-clears on scope
  exit.
- **Expected failure**: Fine Lock leaking into a navigation gesture (would
  indicate a missed call site — check any OTHER Shift+Click branch added by a
  future upstream feature the same way the Bus case was caught here), or
  device removal producing a different chain shape than the menu path.
- **Rollback procedure**: both gestures are purely additive input bindings;
  no config flag exists to disable them short of reverting the commits. If a
  physical issue is found, the two features can be reverted independently
  (they're separate commits) without affecting the rest of the reconciled
  branch.
- **Status**: not yet attempted. **Date last attempted**: never.

## 8. Native button LED ownership

- **Source**: `feature/native-button-led-ownership` (`52faecab`, `262b7dd8`),
  ported as `0123c7c6`/`f65cbd88`.
- **Why it exists**: lets a plain Shadow UI temporarily own a native button's
  LED and get deterministic restore of Move's own state on release — the gap
  `52faecab`'s own research doc calls out as blocking "physical Shift LED
  pulse" and similar per-button LED feedback.
- **Software evidence**: `test_button_led_ownership.c` (C, linked against the
  real `shadow_led_queue.c`) passed in the full `make -C tests/host test`
  run, before AND after porting.
- **Physical setup required**: any Move with the reconciled package; needs a
  Shadow UI code path that actually calls the new ownership request (this
  feature ships the mechanism — `button_led_owned_mask`,
  `button_led_release_mask`, `release_all_owned_button_leds` in
  `shadow_control_t` plus the audio-side consumer in `shadow_led_queue.c` —
  but per `52faecab`'s own note, actually wiring a visible feature like a
  physical Shift LED pulse on top of it is future work, not included here).
- **Exact test procedure** (mechanism-level, since no consumer feature is
  wired yet):
  1. Confirm the build boots cleanly with the grown `shadow_control_t` (256
     bytes in v1.7.3 including these fields; `CONTROL_BUFFER_SIZE` was raised to
     512 so there is headroom) — i.e., schwung-manager and the shim agree on the shared-memory
     layout (no SIGBUS on attach, no `shadow_shm_map()` refusal logged).
  2. If a minimal test harness or module can be pointed at the new fields
     directly (setting `owned_mask` bits, `release_mask` bits), confirm: (a)
     requesting ownership of an eligible button CC suppresses Move's own LED
     writes to it; (b) requesting release restores the LAST NATIVE state Move
     itself would show, not an arbitrary default; (c) `release_all` sweeps
     every currently-owned button in one call.
  3. Confirm pads/steps (note LEDs) and encoder rings (CC 71-78) are
     UNAFFECTED by any of the above — this feature is explicitly scoped to
     buttons only.
- **Expected success**: clean shared-memory boot, correct suppress/restore
  semantics scoped exactly to buttons.
- **Expected failure**: a SIGBUS or refused mapping (would indicate a real
  struct-layout mismatch, not caught by the syntax-level check already done),
  or LED restore showing something other than Move's actual last state.
- **Rollback procedure**: the struct grew by ~36 bytes with headroom to
  spare; no field was inserted or reordered, so schwung-manager built against
  the OLD 84-byte (pre-v1.3.1) or 256-byte (v1.3.1-stock) layout would simply
  not read the new fields — not a corruption risk, but confirm
  schwung-manager itself is rebuilt/redeployed alongside the shim, per this
  struct's own repeated warning about deploying the two together.
- **Status**: not yet attempted — this is genuinely new code with no wired
  consumer feature yet. **Date last attempted**: never.

## 9. Local toolchain compatibility fix (not a feature — build-environment note)

- **Source**: one-line explicit cast in `shim_handle_param_bulk()`
  (`src/schwung_shim.c`), applied during this pass's own AArch64 build
  verification, on top of `f65cbd88`.
- **Why it exists**: `aarch64-linux-gnu-gcc` 15.2.0 (Homebrew, this
  environment) refuses a pre-existing implicit `audio_fx_api_v2_t*` →
  `plugin_api_v2_t*` assignment as a hard error under GCC 14+'s C23-default
  strictness. Verified pre-existing and byte-identical on pure `v1.3.1` via
  an isolated `git worktree` (that worktree failed to build for an unrelated
  missing-`clang` reason before reaching this line, but the source line
  itself matches exactly).
- **Physical/hardware relevance**: NONE — this is a local dev-environment
  toolchain difference, not a functional change. The cast makes explicit what
  the code already relies on: `audio_fx_api_v2_t` and `plugin_api_v2_t` share
  the `get_param`/`set_param` shape this function actually calls through.
- **Not proposed upstream** — no push to `charlesvestal/schwung` was made or
  is planned as part of this pass; recorded here purely so a future rebuild
  in a different toolchain environment isn't surprised by its presence.
- **Status**: N/A (not a hardware test item).

---

## 10. My Presets on Send A / Send B

- **Source**: branch `feat/send-fx-user-presets` (from
  `integration/lttte-schwung-v1.7.3-b`). Guide (Spanish, with the full list):
  `docs/LTTTE_SEND_FX_USER_PRESETS.md`.
- **Why it exists**: the Master FX "My Presets" page (A2, PR #661) extended to
  the 8 positions of each send bus, through the same code parametrised by bus.
- **Software evidence**: `test_send_fx_user_presets.sh` (new, fails without
  the change), `test_trailing_pages_wiring.sh` (send exclusion inverted), the
  master/chain-UI/save/shape-verb/record-from-device lifts, all green; no C
  change.
- **Exact test procedure** (short form; 13 steps in the guide): round-trip
  Save As / Load on Send A and Send B; `*` after a knob turn and after Save;
  Delete No/Yes; reboot keeps sound and name; set A→B→A keeps each set's name;
  reorder/remove (Shift+jog, Delete+click) moves names with their effects;
  swap shows `(none)`; same module on Master FX / Send A / Send B keeps three
  separate names; slot focus untouched; Back lands on My Presets of the same
  send; Audition On does not audition on a send list; return level and A→B
  feed unchanged by a load; scene-armed save stores the knob value.
- **Expected failure modes**: a name surviving onto another module or set; a
  Send A reorder moving Master FX or Send B names; the grid not coming back to
  My Presets after Load/Delete; the `*` showing right after a reboot with no
  knob touched (module normalising its state on reload — note the module).
- **Rollback procedure**: do not merge the branch (it is not in any
  integration branch yet).
- **Status**: not yet attempted. **Date last attempted**: never.

---

## Summary table

| # | Feature | Status | Last attempted |
|---|---|---|---|
| 1 | Declared knob-step mode | Pending | Never |
| 2 | Response curves | Pending | Never |
| 3 | Knob edit-speed | Pending | Never |
| 4 | Tempo landmarks + header fix | Pending (re-verify post-merge) | Never on this baseline |
| 5 | Knob-law contract refresh | Pending (fractional guard previously HW-confirmed) | Fractional guard: before 2026-08-30 |
| 6 | `live_params` moving-window | **Archived — do not retest** | Failed repeatedly, pre-2026-08-30 |
| 7 | Delete+JogClick / Fine Lock | Gesture confirmed 2026-10-22 with shim `8588435c`; that forward is now reverted and Delete is read from the shim's `delete_held` byte, so steps 1, 2a, 2b and **2c** (Delete released with the UI hidden) must be re-run on the new build; Fine Lock pending | 2026-10-22 (gesture, previous build) |
| 8 | Native button LED ownership | Pending (no consumer feature wired yet) | Never |
| 9 | Toolchain cast (not a HW item) | N/A | N/A |
| 10 | My Presets on Send A / Send B (`feat/send-fx-user-presets`) | Pending | Never |

## 11. Shift+jog goes to the first / last page (v1.8.2 port)

On any module's grid in a slot: hold Shift and turn the jog once right -> last
page (the host's trailing "Module" page; "My Presets" is the one before it).
Once left -> first page. Neither wraps. A plain jog still moves one page.
The footer shows `JOG ENDS` while Shift is down. Shift+click still opens the
section picker (that is now the way to a section in between). Not tested on
the Move.
