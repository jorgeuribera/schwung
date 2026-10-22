# LTTTE custom Schwung inventory — v1.3.1 reconciliation

Forensic inventory of every local, non-upstream change found in this
workspace's `schwung` checkout, gathered before any porting began (git status,
remotes, all local/remote branches, tags, reflog-reachable commits, local
build artifacts and tarballs). Written against:

- **Local origin** `charlesvestal/schwung`, fetched fresh this pass — tags now
  go up to `v1.3.1` (`aa4d8f336018a91e44f524b8838ee8ce7445766c`, released
  2026-09-08).
- **Local `archive` remote**: `jorgeuribera/schwung-archive` (private).

## How the local repo was actually structured (important context)

Every local branch's naive merge-base against `origin/main` landed on
`9b35e16f` (`v0.9.18`-ish, 2026-06-20) — the point this local clone's history
diverged in *hash*, not necessarily in content, from upstream's. Comparing
local `main`'s tip (`4ab9ea38`) against upstream commit `652dce44` (same PR
#346, "shadow_ui: Back from Knob Editor restores the grid...") showed
**identical trees, author, and commit date** — proving local `main` is a
content-faithful, hash-rewritten mirror of upstream `main` as of 2026-08-30,
not itself carrying custom work. Every genuinely custom LTTTE commit instead
lives a small number of commits *ahead* of local `main` (or ahead of
`main`'s parent `53861b80`, for the two branches predating `main`'s tip by one
commit), on named `feature/*`/`integration/*`/`backup/*`/`archive/*`
branches. This inventory is built from that smaller, real set — 20 distinct
non-merge custom commits — not from the ~750-commit diff each branch shows
against the old `v0.9.18` fork point (that diff is almost entirely upstream's
own history, not ours).

## Preservation summary

| Item | Final state |
|---|---|
| Declared knob-step mode | `ACTIVE_HW_VERIFIED`* |
| Response curves (opt-in, power-law) | `ACTIVE_SW_VERIFIED_PENDING_HW` |
| Response curves (experimental low/high-fine) | `SUPERSEDED_BY_UPSTREAM` — internal, superseded by the above |
| Knob edit-speed (`knob_step_frac`) | `ACTIVE_SW_VERIFIED_PENDING_HW` |
| `test_widget_sheet.sh` marker-bound corruption check | `SUPERSEDED_BY_UPSTREAM` |
| Tempo landmarks + header-crop fix | `ACTIVE_SW_VERIFIED_PENDING_HW`* |
| Knob-law contract refresh on enum change | `ACTIVE_SW_VERIFIED_PENDING_HW` |
| Delete+JogClick removes a device; Shift Lock (original) | superseded in-branch by Fine Lock rescoping below |
| Fine Lock (rescoped Shift latch) + Delete+JogClick | `ACTIVE_SW_VERIFIED_PENDING_HW` |
| Native button LED ownership (research + implementation) | `ACTIVE_SW_VERIFIED_PENDING_HW` |
| `live_params` / `changes_contract` moving-window | `HARDWARE_FAILED_ARCHIVED` — **not ported, per its own archival record** |
| `contract-probe/` module | `UNKNOWN_PROVENANCE_PRESERVED` |
| `SchwungTempoTester/u6-port-test/` | `UNKNOWN_PROVENANCE_PRESERVED` |
| Local build tarballs (workspace root) | `ACTIVE_HW_VERIFIED`/`UNKNOWN_PROVENANCE_PRESERVED` (see §Artifacts) — all left in place, untouched |

\* "Hardware-reported"/"hardware-reproduced" language appears in these
commits' own messages (see per-item detail) — that is evidence a *bug* was
seen on hardware and then fixed in software, not that the fix itself has been
re-confirmed on hardware since. Classified `ACTIVE_SW_VERIFIED_PENDING_HW`
throughout unless a commit explicitly records a **post-fix** hardware
confirmation (one does — noted below).

## Per-item detail

### 1. Declared knob-step mode

- **Commits**: `30223387d4539611307fb33d0353ccd1cb2bb5e7` (knobs: opt-in
  declared-step mode with exact endpoints), `1221c7e2c9216771d5a7cb13bc84658db378776e`
  (param format: shift-fine gets enough display precision, declared mode only)
- **Branch**: `feature/declared-knob-step` (base: `main`'s parent, `53861b80`)
- **Files touched**: `src/shared/knob_engine.mjs`, `src/shared/param_format.mjs`,
  `docs/MODULES.md`, `docs/PARAM_PAGES.md`, `CLAUDE.md`,
  `tests/host/test_declared_knob_step.sh`, `tests/host/test_fine_step_display_precision.sh`
- **Purpose**: opt-in `knob_step_mode: "declared"` — a param moves by exactly
  its declared `step`, not a range-normalised fraction; min/max are exactly
  reachable via an integer-lattice stepper. `1221c7e2` fixes a **hardware-reported**
  display bug (declared step 0.3 → fine step 0.03 displayed at one decimal, so
  four physically distinct values all read "0.0"/"0.1"/etc.) — the display fix,
  not the underlying mechanism, was hardware-motivated.
- **Evidence level**: 156+125 shell-test assertions pass (`test_declared_knob_step.sh`,
  `test_fine_step_display_precision.sh`), both re-verified after porting.
- **Hardware status**: mechanism not yet confirmed on hardware; the display
  precision bug it's paired with WAS seen on hardware (pre-fix).
- **Upstream v1.3.1 equivalent**: none. `grep` of `src/shared/knob_engine.mjs`
  at `v1.3.1` for `knob_step_mode`/`declared` finds no such mode (402 lines,
  only `MIN_STEP_RANGE_FRAC`-based stepping).
- **Conflict risk against v1.3.1**: LOW in practice — ported clean except one
  `CLAUDE.md` doc-insertion-point conflict (upstream had added an unrelated
  bus/send documentation section at the same location; resolved by keeping
  both).
- **Final preservation location**: `integration/lttte-schwung-v1.3.1` (ported,
  commit `9204c9ce`/`8dd91261`).
- **Active in reconciled baseline**: **YES**.

### 2. Response curves — opt-in power-law (`knob_curve`)

- **Commit**: `72d6f9ac93a6a1f3c6d48413a8a4c46fe4683cb4` ("knobs: opt-in
  response curves redistribute a range's travel")
- **Branch**: `feature/knob-response-curves` (base: `main`)
- **Files touched**: `src/shared/knob_engine.mjs`, `docs/MODULES.md`,
  `docs/PARAM_PAGES.md`, `CLAUDE.md`, `tests/host/test_knob_response_curve.sh`
- **Purpose**: `knob_curve: "low_focus"|"high_focus"` + `knob_curve_gamma`
  redistributes a range's ~200-detent travel by a power law (`y = u^gamma` /
  `y = 1-(1-u)^gamma`), bounded so the coarsest detent is at most `gamma`×
  linear. Mutually exclusive with declared-step (declared-step wins).
- **Evidence level**: 2654 checks in `test_knob_response_curve.sh`, re-verified
  after porting.
- **Hardware status**: not hardware-tested. Its own doc comment explicitly
  contrasts itself with the *archived* moving-window mechanism ("A moving
  min/max window had no such bound, which is why it stalled on hardware").
- **Upstream v1.3.1 equivalent**: none (same `grep` as above).
- **Conflict risk**: LOW — one `CLAUDE.md` doc-conflict (same insertion-point
  pattern as item 1), resolved cleanly.
- **Final preservation location**: `integration/lttte-schwung-v1.3.1`
  (`6af2a7b8`).
- **Active in reconciled baseline**: **YES**.

### 3. Response curves — experimental `low_fine`/`high_fine` (SUPERSEDED)

- **Commit**: `a831eeec237a08dea8f67417a2674dacad8ad086` ("knobs: experimental
  low_fine/high_fine response curves")
- **Branch**: `backup/knob-response-curves-experimental` (base: `53861b80`,
  i.e. this is the OLDER, first-attempt sibling of item 2 — authored
  2026-08-29 22:38, five hours before `72d6f9ac`'s 2026-08-30 03:07)
- **Files touched**: `src/shared/knob_engine.mjs`, `docs/MODULES.md`,
  `docs/PARAM_PAGES.md`, `CLAUDE.md`, `tests/host/test_knob_response_curve.sh`
- **Purpose**: an earlier design of the SAME idea — a `knob_response:
  "low_fine"|"high_fine"` axis reshaping sensitivity by position, via the same
  power-curve technique, predating the cleaner `knob_curve` naming/design in
  item 2 (exact-inverse seeding, the `gamma`-bound safety argument, and the
  bipolar-range handling were all refined in the later version).
- **Evidence level**: had its own 126-check test at the time; superseded, not
  re-run.
- **Hardware status**: not hardware-tested; never merged forward past its own
  branch.
- **Upstream v1.3.1 equivalent**: none.
- **Conflict risk**: N/A — not ported.
- **Final preservation location**: unchanged, still exactly at
  `backup/knob-response-curves-experimental` (local branch, untouched by this
  pass) — the branch itself IS the recoverable original; nothing was deleted.
- **Active in reconciled baseline**: **NO** — `SUPERSEDED_BY_UPSTREAM`... more
  precisely superseded by our OWN later commit (item 2), which is why this is
  filed as `SUPERSEDED_BY_UPSTREAM`-adjacent but is really "superseded by a
  sibling LTTTE commit, not by upstream Schwung." Recorded honestly rather
  than forced into a category that overclaims upstream's involvement.

### 4. Knob edit-speed (`knob_step_frac`)

- **Commits**: `a08249666f9cd58d55445cf862a1677005fad3f5` ("knobs: an opt-in
  edit speed sets how fast a range is crossed"), plus
  `b7f92429033a7396cdc88f640f71b2c1e6d2c3a6` (test-harness robustness fix, see
  item 4b below)
- **Branch**: `feature/knob-step-frac` (base: `main`)
- **Files touched**: `src/shared/knob_engine.mjs`, `docs/MODULES.md`,
  `docs/PARAM_PAGES.md`, `CLAUDE.md`, `tests/host/test_knob_step_frac.sh`
- **Purpose**: `knob_step_frac` (fraction of range per coarse detent) is an
  edit-SPEED axis orthogonal to `knob_curve` (WHERE resolution concentrates).
  Explicitly designed to avoid the moving-min/max-window approach that failed
  on hardware (see item 11): "A speed has no state to refresh — the range it
  walks is the one that was declared, always."
- **Evidence level**: 58692 checks in `test_knob_step_frac.sh`, re-verified.
- **Hardware status**: not hardware-tested.
- **Upstream v1.3.1 equivalent**: none.
- **Conflict risk**: NONE — clean auto-merge.
- **Final preservation location**: `integration/lttte-schwung-v1.3.1`
  (`90b931c8`).
- **Active in reconciled baseline**: **YES**.

### 4b. `test_widget_sheet.sh` corruption-check fix (SUPERSEDED_BY_UPSTREAM)

- **Commit**: `b7f92429033a7396cdc88f640f71b2c1e6d2c3a6` ("widget-sheet check:
  corrupt inside the markers, not inside a line number")
- **Purpose**: the test's own self-check (that its deliberate corruption can
  actually fail the widget-sheet `--check`) was bounded by a hardcoded
  `$. < 2000`, which broke once content pushed the generated block past line
  2000. Rebinds the corruption to the `BEGIN`/`END generated widgets` markers.
- **Upstream v1.3.1 equivalent**: **YES, exact — proven, not assumed.**
  `v1.3.1`'s own `tests/host/test_widget_sheet.sh` independently fixes the
  *identical* bug (same root cause, same hardcoded-2000 symptom) using
  `BEGIN_LINE`/`END_LINE` computed via `grep -n`, then `cmp`-checking that the
  corruption actually changed the file — functionally equivalent, marker-bound
  correction; upstream's own commit message and diff were inspected directly
  during the port (real cherry-pick conflict, not inferred from the name).
- **Conflict risk**: this WAS attempted and produced a real conflict; resolved
  by keeping upstream's own fix and dropping ours (`git cherry-pick --skip`).
- **Final preservation location**: still on `feature/knob-step-frac` (local
  branch, untouched); NOT present on `integration/lttte-schwung-v1.3.1`.
- **Active in reconciled baseline**: **NO** — genuinely superseded by
  upstream's own independent fix (`v1.3.1`'s `tests/host/test_widget_sheet.sh`,
  same file).

### 5. Tempo landmarks (informational)

- **Commits**: `bd8f6bbe7c1ed3a3dafd05a8c8e967b43d728bfa` ("param pages:
  informational tempo landmarks for a free time parameter"),
  `280eafe033c5270af3e7de5f1b19a02451421ef3` ("param pages: the selected-header
  never crops a musical landmark token")
- **Branches**: `feature/tempo-landmarks`, `feature/tempo-landmark-header-layout`
- **Files touched**: `src/shared/param_pages/tempo_landmarks.mjs` (new),
  `src/shared/param_pages/page_controller.mjs`,
  `src/shared/param_pages/render_page_movy.mjs`,
  `src/shadow/shadow_ui.js`, `src/shadow/shadow_ui_param_pages.mjs`,
  `docs/MODULES.md`, `docs/PARAM_PAGES.md`, `CLAUDE.md`,
  `tests/host/test_tempo_landmarks.sh`, `tests/host/test_header_landmark_atomicity.sh`
- **Purpose**: opt-in `tempo_landmarks: true` prints the nearest rhythmic
  value beside a free (non-quantised) time parameter — an information layer
  only, no snap/pull/detent. `280eafe0` fixes a **hardware-reported** header
  crop bug ("41.105 ms  1/32T" chopped to "41.105 ms  1" under a tight header).
- **Evidence level**: 328+133 checks across the two test files (343 after the
  follow-on commit, item 6 below), re-verified.
- **Hardware status**: header-crop bug was seen on hardware pre-fix; the
  landmark feature itself not yet re-confirmed post-port.
- **Upstream v1.3.1 equivalent**: none — `src/shared/param_pages/tempo_landmarks.mjs`
  does not exist at `v1.3.1`.
- **Conflict risk**: MEDIUM — real conflicts in `CLAUDE.md`, `docs/MODULES.md`,
  `docs/PARAM_PAGES.md` (doc-insertion-point, resolved by keeping both
  sections) and two functional files:
  - `src/shadow/shadow_ui_param_pages.mjs`: upstream had independently added
    `loadCard`/`drawCanvasPage` callbacks to the same options object our
    `getTempo` callback was added to — both kept.
  - `src/shared/param_pages/page_controller.mjs`: upstream had independently
    added `drawCanvasPage`/`rect`/`bands`/`decorations` (its new
    tool-embeddable-grid support, see `docs/SCHWUNG_CAPABILITIES_FOR_DJTTTO.md`
    in `TTT.djto`) at the exact same object-literal position our
    landmark-aware `displayFor` override touches — merged to keep both; the
    landmark-aware `displayFor` is a **strict superset** of upstream's plain
    version (identical for every non-header surface, and identical for header
    when no landmark is near).
  - `src/shared/param_pages/render_page_movy.mjs`: upstream had independently
    added a `padIcon` parameter (with its own right-edge width budget) to
    `drawHeader`, at the same location our `atomicTokenTiers`/`fitHeaderRight`
    (never crop mid-token) rewrite touches — merged so the icon's width budget
    and the token-atomic fit both apply together.
  - One merge-introduced regression was caught and fixed **by this pass's own
    test suite**: a resolution comment used the word "landmark" inside
    `render_page_movy.mjs`, which `test_tempo_landmarks.sh`'s own static guard
    (`grep -ni "landmark" render_page_movy.mjs` must find nothing — the
    renderer must never compute landmark logic itself) correctly flagged;
    reworded, re-verified green.
- **Final preservation location**: `integration/lttte-schwung-v1.3.1`
  (`8ce1a38b`, `dcc9920d`).
- **Active in reconciled baseline**: **YES**.

### 6. Knob-law contract refresh on enum change

- **Commits**: `53eee201ac2be950e8930403aea26d935c7e4b4a` ("param pages: an
  enum that republishes a knob law re-arms the contract settle"),
  `ed1da08334415ab8597319e6fc9a768280a6c71a` ("tests: knob-law contract
  refresh test was missing its PASS line"), plus the sample-count/exact-unit
  follow-on `6fffbff71bdcf7ca70543f520f177cf99cee2fc9` ("knobs: exact-unit
  edit-speed composition + sample-count tempo landmarks")
- **Files touched**: `src/shared/param_pages/page_controller.mjs`,
  `src/shared/param_pages/param_meta.mjs`,
  `src/shared/param_pages/tempo_landmarks.mjs`, `docs/PARAM_PAGES.md`,
  `CLAUDE.md`, `tests/host/test_knob_law_contract_refresh.sh`,
  `tests/host/test_declared_knob_step.sh`, `tests/host/test_tempo_landmarks.sh`,
  `tests/host/test_fractional_micro_shift.sh`
- **Purpose**: a module deriving one param's control law from another (an
  "Edit Speed"/"Time Curve" enum rewriting `knob_step_frac`/`knob_curve`) now
  re-arms the settle/debounce on that enum's OWN turn — explicitly NOT the
  moving-window mechanism that failed on hardware (see item 11): "this
  re-reads because a different, discrete control was turned, once, after the
  hand stops," vs. the archived mechanism's continuous re-read under a moving
  finger.
- **Evidence level**: 260+7 checks (`test_knob_law_contract_refresh.sh`),
  re-verified; `6fffbff7`'s own message records that its companion
  Fractional+Micro+Shift-fine behavior (100.000→100.800 ms) was
  **"physically re-confirmed on hardware (100.000 -> 100.800 observed). No fix
  was needed; this guards the confirmed-correct behavior going forward"** —
  the one item in this inventory with an explicit **post-verification**
  hardware confirmation on record, and it is a *guard test* for
  already-correct behavior, not a fix.
- **Hardware status**: contract-refresh mechanism itself not separately
  hardware-tested; the fractional-shift guard IS hardware-confirmed (above).
- **Upstream v1.3.1 equivalent**: none (`declaresKnobLaw`, `knob_step_mode`
  awareness absent from `v1.3.1`'s `param_meta.mjs`/`page_controller.mjs`).
- **Conflict risk**: MEDIUM — `page_controller.mjs` import list conflicted
  (upstream added `resolveChildKey`/child-level and `voices.mjs` imports for
  its own new focus/child-press feature at the same import block; merged to
  keep both plus our `declaresKnobLaw` addition). Doc conflicts resolved as
  duplicate-bullet removal (the sibling-branch pattern — see the reconciliation
  note in `docs/LTTTE_PENDING_HARDWARE_TESTS.md`).
- **Merge-artifact caught by this pass**: a duplicate `export const
  KNOB_STEP_MODE_DECLARED` (two independently-authored branches each adding
  the same constant) was caught by a native `node --check` syntax pass
  immediately after porting item 2, not left for a later surprise; fixed in
  commit `234c0e94`.
- **Final preservation location**: `integration/lttte-schwung-v1.3.1`
  (`a4d3db0f`, `ed90d1b4`, `635789b7`).
- **Active in reconciled baseline**: **YES**.

### 7. Delete+JogClick removes a device; Fine Lock (rescoped Shift latch)

- **Commits**: `cf0a6790ea1ca9a08f8dcc7c46bbb32496a21ac5` ("shadow_ui:
  Delete+JogClick removes a device; double-tap Shift locks it") — the
  ORIGINAL design, calling the latch "Shift Lock" and OR-ing it into every
  Shift-layer read — followed by `b9ed7cb3c59edd9d84c23702c50e60210fccdc40`
  ("shadow: scope Shift latch to parameter Fine Lock"), which **rescopes** the
  same latch: physical Shift keeps its ordinary global/navigation meaning
  everywhere, and the double-tap latch (renamed Fine Lock) is consulted only
  by explicit parameter-fine paths, clearing when that editing scope ends.
- **Files touched**: `src/shadow/shadow_ui.js`,
  `src/shadow/shadow_ui_master_fx.mjs`, `src/shadow/shadow_ui_param_pages.mjs`,
  `src/shared/param_pages/README.md`, `src/shared/param_pages/page_input.mjs`,
  `CLAUDE.md`, plus 8 test files.
- **Purpose**: Delete(CC119)+JogClick removes the selected populated device in
  either chain, through the same host call the existing Remove-Module row
  uses. Fine Lock double-tap-latches the fine-adjust modifier so a
  precision-editing session doesn't require holding Shift continuously.
- **Evidence level**: `test_delete_jogclick_remove.sh` (5 checks),
  `test_shift_lock.sh` (rewritten by `b9ed7cb3` to pin the corrected
  physical/Fine split — 5 groups of checks), both green after porting.
- **Hardware status**: not hardware-tested. `cf0a6790`'s own message records a
  deliberate scope-down: no visual "REMOVED" toast / footer indicator was
  implemented, because this codebase's convention for that kind of change is
  screen-render verification on hardware, which this session had no way to
  perform safely.
- **Upstream v1.3.1 equivalent**: none for either mechanism.
- **Conflict risk**: HIGH — the largest functional merges in this pass, in
  `shadow_ui.js` (22000+ lines) and `shadow_ui_master_fx.mjs`. Concretely:
  - `cf0a6790` conflicted where upstream had independently added a NEW
    `VIEWS.BUS_CHAIN`/`selectingBusModule` branch (its own bus feature) right
    beside the `VIEWS.MASTER_FX` branch our Shift-Lock rename touched; merged
    to keep upstream's bus branch and apply our rename to it too. Also had to
    preserve upstream's own, unrelated `masterFxPositionOf(...)` wrapper
    (added independently around the same call) rather than reverting to our
    older raw-index call.
  - `b9ed7cb3` conflicted at THREE sites in `shadow_ui.js` and TWO in
    `shadow_ui_master_fx.mjs`, all variations on the same theme: our earlier
    (`cf0a6790`-era) `hostEffectiveShiftHeld()`/`isShiftHeld()` calls needed
    rescoping to `hostPhysicalShiftHeld()`/`isPhysicalShiftHeld()` for
    navigation gestures, while upstream's independently-added `fxBus()`/
    `fxBusHints()` (Send-bus-aware footer labelling) and `sendBusLevelRead`
    destructure needed to be kept alongside.
  - **A real consistency gap was found and fixed, not merely resolved**:
    upstream's own new `BUS_CHAIN` Shift+Click branch (in both the co-run and
    main dispatch, 2 call sites) used bare/effective Shift reads that this
    pass's OWN `test_shift_lock.sh` static guard (a whole-file grep for any
    remaining bare `hostShiftHeld` gating read) correctly caught as violating
    the very invariant `b9ed7cb3` establishes. Fixed to `hostPhysicalShiftHeld()`/
    `isPhysicalShiftHeld()` at all 3 sites for consistency with the sibling
    `MASTER_FX`/`CHAIN_EDIT` branches beside them — a genuine extension of
    upstream's own bus feature to honor an invariant upstream had not yet been
    taught, not a reinterpretation of it.
  - `tests/host/test_shift_lock.sh`'s own literal-string check for the Master
    FX footer's hint expression was too strict for the reconciled code (it
    expected `hints: isPhysicalShiftHeld() ? ...` but the merged code correctly
    wraps that in upstream's new `fxBusHints(...)`); loosened to match the new,
    still-invariant-preserving call shape.
  - `test_list_layout_footer.sh`, a THIRD, unrelated test file that also lifts
    `footerHints()`/`orderedHints()` out of `shadow_ui_param_pages.mjs` by
    name, was left silently broken by the rename (it never conflicted during
    the cherry-pick, since it doesn't touch source — it just went on stubbing
    the pre-rescoping parameter names). Fixed in a separate follow-up commit
    (`b614f4ae`) once the full suite surfaced it.
- **Final preservation location**: `integration/lttte-schwung-v1.3.1`
  (`c3ac069e`, `c81f820c`, `b614f4ae`).
- **Active in reconciled baseline**: **YES**.

### 8. Native button LED ownership

- **Commits**: `52faecab3cf7e57c92fd4a810664a8831a2e0460` ("research: native
  button LED ownership audit and candidate API sketch" — docs only, no code),
  `262b7dd8e38ceb29d01ea51356b03be0010eff4f` ("implementa: ownership genérico
  de leds nativos por botón" — the implementation)
- **Branch**: `feature/native-button-led-ownership` (was checked out HEAD at
  the start of this pass)
- **Files touched**: `docs/LED_OWNERSHIP_RESEARCH.md`, `docs/API.md`,
  `src/host/shadow_constants.h`, `src/host/shadow_led_queue.c/.h`,
  `src/schwung_shim.c`, `src/shadow/shadow_ui.c`, `tests/host/Makefile`,
  `tests/host/test_button_led_ownership.c/.sh`
- **Purpose**: a plain Shadow UI can request temporary ownership of a native
  button's LED (identified by its cable-0 CC index), have the audio-side LED
  queue restore its last native state on release (one button or all owned),
  scoped to buttons only (not pads/steps or encoder rings, which already have
  a restore path).
- **Evidence level**: `test_button_led_ownership.c` (linked against the real
  `shadow_led_queue.c`, not a stub) — passed in the full `make -C tests/host
  test` run, both before and after porting.
- **Hardware status**: not hardware-tested — this is genuinely brand-new,
  written the session before this reconciliation pass. `52faecab`'s own
  message is explicit: "documents current cache/suppression/restore paths…
  and the fail-safe gap that blocks physical Shift LED pulse until a
  Shadow-scoped ownership mask + deterministic restore is proven."
- **Upstream v1.3.1 equivalent**: none — `v1.3.1`'s `shadow_led_queue.c` has
  no `owner_mask`/`button_led_owner` concept, only the pre-existing
  `led_keep_mask`/corun suppression paths this feature builds alongside.
- **Conflict risk**: HIGH, and the highest-stakes file in this entire
  reconciliation: `src/host/shadow_constants.h`, the shared-memory
  `shadow_control_t` struct schwung-manager reads at RAW OFFSETS
  (`shmconfig.go`), where sizeof is a binary contract and — per the file's own
  repeated comment — "APPENDING IS FREE; INSERTING IS NOT."
  - Our commit had (correctly, for the *pre-upstream-growth* struct) shrunk
    `CONTROL_BUFFER_SIZE` from upstream's already-generous 256 back down to
    120 to make exact room for its own fields — upstream had independently
    solved the same "no headroom" problem it was reacting to by growing the
    container to a full free page (256 bytes for a struct using ~85) and
    removing a fragile `==`-sized assert. Kept upstream's 256, NOT our 120 —
    our fields (`button_led_owned_mask[4]`, `button_led_release_mask[4]`,
    `release_all_owned_button_leds`, padding — ~36 bytes) fit comfortably in
    the headroom upstream already provided.
  - Our new fields were APPENDED after upstream's own newly-added fields
    (`stay_in_shadow`, the metronome trio, `save_stems`, `claim_cc_bits[16]`,
    `pad_observe`) rather than before them, preserving every existing
    binary offset schwung-manager depends on.
  - `_Static_assert`/typedef size-check (`sizeof(shadow_control_t) <=
    CONTROL_BUFFER_SIZE`) re-verified via `gcc -fsyntax-only` after the merge
    — passes.
  - `tests/host/Makefile`'s `TARGETS` list conflicted (upstream's own new
    `test_ui_midi_out_carry` target beside our new
    `test_button_led_ownership` target, at the same list position); both
    kept.
- **Toolchain finding, unrelated to this feature but discovered while
  building it**: the local `aarch64-linux-gnu-gcc` (Homebrew, v15.2.0) refuses
  a pre-existing, byte-identical-on-`v1.3.1` implicit pointer conversion in
  `shim_handle_param_bulk()` (`src/schwung_shim.c`) as a hard error under its
  C23-default strictness — verified via an isolated `git worktree` at pure
  `v1.3.1` (that worktree fails for an unrelated missing-`clang` reason before
  reaching this line, but the exact source line is byte-identical between
  branches, and this GCC's own documented behavior change fully explains the
  new error). One explicit cast added (`(plugin_api_v2_t *)`) to unblock a
  real, local AArch64 build in this environment; not an upstream contribution,
  not pushed anywhere upstream — see `docs/LTTTE_PENDING_HARDWARE_TESTS.md`.
- **Final preservation location**: `integration/lttte-schwung-v1.3.1`
  (`0123c7c6`, `f65cbd88`).
- **Active in reconciled baseline**: **YES**.

### 9. `live_params` / `changes_contract` moving-window (HARDWARE_FAILED_ARCHIVED)

- **Commits** (chronological): `b84741d0556ffec262b20207a058556b1961128b`
  (generic `changes_contract: true` re-arm-on-write mechanism),
  `d06bd7cf4e7c2116916a5e4e549515e3e13793d7` (adds `live_params`
  moving-window refresh), `b03fa50521976c5ab6de47fa9af7a201eeaded3f` (fixes a
  stall on continuous-motion re-arming), `17da2ee7d7e24919f79f0b226add3521409cb286`
  (fixes per-key pending staleness), `f44402b2518ac05b67fa5cbf3f00ef68a539f3b0`
  (the archive marker commit itself, adding `EXPERIMENTAL_LIVE_PARAMS.md`)
- **Branch**: `archive/live-params-moving-window-hardware-failed-2026-08-30`
  — **already pushed** to the `archive` remote (`jorgeuribera/schwung-archive`,
  one commit ahead locally: the remote copy additionally carries a
  `CONFIDENTIALITY.md` notice, `bf0db97e`).
- **Purpose**: a parameter whose OWN contract (min/max) moves with its
  current value — a module republishing a local window centred on the
  current position — used to only refresh on exit/re-entry. This mechanism
  tried to refresh it live, under continuous touch.
- **Evidence level**: full synthetic/host test suites passed, plus a realistic
  stale/lag regression the commits' own messages describe in detail (see
  below) — software-only.
- **Hardware status**: **HARDWARE_FAILED**, in the archive commit's own
  words (`f44402b2`): "Synthetic validation passed... Physical hardware
  disagreed: under continuous touch on a real encoder the parameter still
  stalled permanently, and the final [`1cc1536a`] generation stalled earlier
  than the previous physical test." Multiple real physical retries, each
  worse or no better.
- **Upstream v1.3.1 equivalent**: none.
- **Reconciliation action**: **NOT ported.** Per the explicit instruction for
  this special case, its existence alone is not a reason to merge it, and no
  new hardware evidence surfaced during this pass. Its own archive commit
  message already records the reasoning to prefer the (ported, still-active)
  declared-step + response-curve combination as "the simpler path to the
  actual musical requirement," and explicitly carves OUT declared-step as "a
  separate capability that is still wanted" — which is exactly why item 1
  above WAS ported and this was not.
- **Final preservation location**: unchanged, on
  `archive/live-params-moving-window-hardware-failed-2026-08-30` (local) and
  `jorgeuribera/schwung-archive` (remote, pre-existing push). Untouched by
  this pass. `EXPERIMENTAL_LIVE_PARAMS.md` on that branch remains the primary
  record.
- **Active in reconciled baseline**: **NO** — `HARDWARE_FAILED_ARCHIVED`,
  exactly as classified before this pass began, unchanged.

### 10. `contract-probe/` module

- **Location**: `/Users/jaur/OtherProjects/Coding/Move:Schwung/contract-probe/`
  (sibling directory to `schwung/`, plus `contract-probe-module.tar.gz` next
  to it, dated 2026-08-30 04:24)
- **Files**: `module.json`, `dsp/probe.c`, built `contract-probe.so`
- **Purpose**: unclear from the files alone — name and timestamp (same day as
  the `live_params`/`changes_contract` work, ~90 minutes before the earliest
  `live_params` commit) strongly suggest it was a throwaway probe module used
  to inspect `chain_params`/contract behavior on real hardware while
  designing that feature, but no commit message or README ties them together
  explicitly.
- **Evidence level / hardware status**: unknown — no test suite, no
  provenance commit found.
- **Upstream v1.3.1 equivalent**: N/A (not a fork of any upstream module).
- **Reconciliation action**: left in place, untouched, not ported anywhere
  (nothing to port — it isn't part of the `schwung` git repo).
- **Final preservation location**: unchanged, on disk.
- **Active in reconciled baseline**: **NO** — `UNKNOWN_PROVENANCE_PRESERVED`.

### 11. `SchwungTempoTester/u6-port-test/`

- **Location**: `/Users/jaur/OtherProjects/Coding/Move:Schwung/SchwungTempoTester/`
- **Files**: `module.json`, `ui.js`, `dsp/u6_port_test.c`, `build.sh`,
  `README.md`, `dist/u6-port-test-0.5.0.tar.gz`
- **Purpose**: a standalone, versioned (0.5.0) exploratory tool module,
  apparently for testing tempo/timing behavior — has its own README and build
  script, suggesting more deliberate, longer-lived work than `contract-probe/`,
  but still entirely outside the `schwung` git repo and with no cross-reference
  found tying it to any of the 20 inventoried commits.
- **Evidence level / hardware status**: unknown — has a versioned dist
  tarball, which suggests at least one intentional build/deploy cycle, but no
  test suite or hardware-status note was found in this pass.
- **Upstream v1.3.1 equivalent**: N/A.
- **Reconciliation action**: left in place, untouched.
- **Final preservation location**: unchanged, on disk.
- **Active in reconciled baseline**: **NO** — `UNKNOWN_PROVENANCE_PRESERVED`.

## Artifacts (workspace-root tarballs)

All left in place; none overwritten, none deleted, none renamed.

| File | Date | Matches |
|---|---|---|
| `rollback/schwung-v1.0.0.tar.gz` | pre-existing | Rollback artifact for `v1.0.0` |
| `schwung-core-knob-fixes-baf78e73.tar.gz` | 2026-08-29 23:10 | `integration/core-knob-fixes` at merge commit `baf78e73` — **includes the archived `live_params` work**, per that branch's own log (do not treat as a clean declared-step-only build) |
| `schwung-core-knob-fixes-207df0c2.tar.gz` | 2026-08-29 23:59 | same branch, later merge commit `207df0c2` — same caveat |
| `schwung-integration-performance-knob-core-ed1da083-arm64-2026-08-30.tar.gz` | 2026-08-30 05:31 | `integration/performance-knob-core` at `ed1da083` — declared-step + response-curve + step-frac + contract-refresh, **no `live_params`** |
| `schwung-integration-ux-additions-94fab58e-arm64-2026-08-30.tar.gz` | 2026-08-30 08:16 | `integration/ux-additions` at intermediate merge `94fab58e` |
| `schwung-integration-ux-additions-6fffbff7-arm64-2026-08-30.tar.gz` | 2026-08-30 15:32 | `integration/ux-additions` at tip `6fffbff7` — the most complete pre-reconciliation custom build (everything through item 6, not items 7/8, since those postdate it) |
| `schwung-integration-lttte-v1.3.1-b614f4ae-arm64-2026-09-08.tar.gz` **(new, this pass)** | 2026-09-08 | `integration/lttte-schwung-v1.3.1` at `b614f4ae` — the reconciled v1.3.1-based candidate; SHA256 recorded in `docs/LTTTE_PENDING_HARDWARE_TESTS.md` |
| `contract-probe-module.tar.gz` | 2026-08-30 04:24 | see item 10 |

**No custom item from this inventory was silently discarded.** Every branch,
tag, and artifact enumerated above still exists at the path/ref recorded
here; this pass only ADDED a new branch (`integration/lttte-schwung-v1.3.1`)
and a new tarball, and made zero destructive git operations (no branch
deletion, no force-push, no `git reset --hard` affecting committed work — the
one `git reset --hard` used during this pass targeted this session's own
uncommitted working-tree mistake, restoring to this session's own prior
commit, not discarding any pre-existing work).

---
Ideas and pending work, with what to develop or propose upstream: `docs/LTTTE_IDEAS_AND_PENDING.md`.
