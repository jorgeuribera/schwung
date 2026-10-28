# Ideas and pending work for this fork

A running list of things this fork has, wants, or is considering, and what to do with each: **keep local**, **develop**, or **propose upstream** (charlesvestal/schwung). Anything proposed upstream must be written in English (code comments, docs, PR text) and have its own test and hardware plan first. This file is the index; the detail lives in the linked documents.

Hardware test plans: `LTTTE_PENDING_HARDWARE_TESTS.md`, `LTTTE_MASTER_FX_USER_PRESETS.md`, `LTTTE_SEND_FX_USER_PRESETS.md`, `LTTTE_PASSTHROUGH_LED_COLOR.md`. Provenance of the older mods: `LTTTE_CUSTOM_SCHWUNG_INVENTORY.md`.

## A. Implemented in the fork

| # | Idea | Where | Hardware status | Upstream |
|---|---|---|---|---|
| A1 | **Delete ("X", CC 119) + Jog click removes the selected device from the chain** (Move-style gesture, same host call as the Remove-Module row). While Delete is held the footer reads `JOG SEL / CLK DELETE` on a loaded device; after a removal a `REMOVED <NAME>` pill shows in the footer row for 1.5 s (or until the next jog turn / button press), never covering the screen | `shadow_ui.js` (`hostDeleteHeld`, MFX slot and chain slot removal, `chainFooterNotice`); `chain_editor_chrome.mjs` (`deleteHintsFor`, `createFooterNotice`, `footerNoticeDismissedBy`, `drawFooterNotice`); shim forwards CC 119 (`8588435c`); inventory §7; tests `test_delete_jogclick_remove.sh`, `test_delete_footer_notice.sh`, chain-editor snapshot cases `*/delete*`, `*/removed-notice*` | **Gesture confirmed on the Move** (slots and Master FX, after the shim fix). **Footer `CLK DELETE` and the `REMOVED` notice: pending on hardware** (see `LTTTE_PENDING_HARDWARE_TESTS.md` §7) | **PR opened: charlesvestal/schwung#662** (2026-10-22, AI use declared). Footer and confirmation confirmed on the Move |
| A2 | Master FX **My Presets** (load / save / save as / delete on the 8 Master FX positions) | branch `feat/master-fx-user-presets` | Pending (13 tests listed in its guide) | Upstream issue #305. **PR opened: charlesvestal/schwung#661** (2026-10-22; AI use declared in the description, as CONTRIBUTING asks) |
| A3 | `button_passthrough` keeps Move's **LED colour** while a Tool suppresses the rest of the native LED sysex | branch `feat/overtake-passthrough-led-color` | Pending (see its doc); known risk: sysex index collision with pad notes 79/85/88 | Upstream issue #341. Small PR candidate |
| A4 | Declared knob-step mode, opt-in knob response curves, edit-speed fraction, tempo landmarks with header crop, knob-law contract refresh, Fine Lock | integration branch, inventory | Pending | Not offered upstream yet; decide per item which are general enough |
| A5 | Native button LED ownership (`CONTROL_BUFFER_SIZE` 256 → 512; shim and shadow UI must ship together) | integration branch | Pending | Fork-only for now |
| A6 | Send A / Send B **My Presets** (load / save / save as / delete on the 8 positions of each send bus; same code as A2, parametrised by bus: `fxBus*` helpers; record persisted after `state` in `send_fx_<send>_<i>.json`; no shim change) | branch `feat/send-fx-user-presets` (from `integration/lttte-schwung-v1.7.3-b`); guide `LTTTE_SEND_FX_USER_PRESETS.md`; test `test_send_fx_user_presets.sh` | Pending (13 tests listed in its guide; summary in `LTTTE_PENDING_HARDWARE_TESTS.md` §10) | Natural follow-up to #661 once that PR lands; would need its own English PR |

## B. Ideas not started

| # | Idea | Notes |
|---|---|---|
| B1 | Docs note and/or UI hint for Move → Schwung: "Move master-track devices, returns and metronome are bypassed" | Raised upstream as #660. Offer a docs PR after Charles answers |
| B2 | Optional mode that consumes Move's Main channel (so master-track devices stay audible) | Depends on whether the 2026-04 ring overrun is still real; see #660 question 4 |
| B3 | **Export to Live** button / endpoint in Schwung Manager that returns `schwung_export.json` | Belongs with the SchwungLive project (private repo, roadmap in `docs/ROADMAP.md`); upstream-friendly as a small Go endpoint |
| B4 | Short "portable module" note for authors: build with `-ffixed-x18`, no files/threads inside audio callbacks | Draft already written in English in SchwungLive (`docs/FOR_MODULE_AUTHORS.md`) |
| B5 | Reply to #341 (co-run does not cover it: `MOVE_NATIVE` hands the OLED to the firmware) and #365 (no `primary_param` needed) | Drafts exist, not posted |

## C. Rules for this list
- Never delete fork code because it has not been hardware-tested (same rule as `LTTTE_PENDING_HARDWARE_TESTS.md`).
- Before anything goes upstream: English docs and comments, a minimal diff, a test that fails without the change, and the hardware result written down.
- Add new ideas here the moment they come up, even half-formed.
