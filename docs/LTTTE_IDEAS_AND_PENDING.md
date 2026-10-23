# Ideas and pending work for this fork

A running list of things this fork has, wants, or is considering, and what to do with each: **keep local**, **develop**, or **propose upstream** (charlesvestal/schwung). Anything proposed upstream must be written in English (code comments, docs, PR text) and have its own test and hardware plan first. This file is the index; the detail lives in the linked documents.

Hardware test plans: `LTTTE_PENDING_HARDWARE_TESTS.md`, `LTTTE_MASTER_FX_USER_PRESETS.md`, `LTTTE_PASSTHROUGH_LED_COLOR.md`. Provenance of the older mods: `LTTTE_CUSTOM_SCHWUNG_INVENTORY.md`.

## A. Implemented in the fork

| # | Idea | Where | Hardware status | Upstream |
|---|---|---|---|---|
| A1 | **Delete ("X", CC 119) + Jog click removes the selected device from the chain** (Move-style gesture, same host call as the Remove-Module row) | `shadow_ui.js` (`hostDeleteHeld`, MFX slot and chain slot removal); inventory §7; test `test_delete_jogclick_remove.sh` | **Not yet tested on the Move** (it is part of the build currently installed: hold Delete, click the jog on a populated device) | No upstream equivalent. Good PR candidate: small, self-contained; first add a "removed" footer/toast and test on hardware |
| A2 | Master FX **My Presets** (load / save / save as / delete on the 8 Master FX positions) | branch `feat/master-fx-user-presets` | Pending (13 tests listed in its guide) | Upstream issue #305. **PR opened: charlesvestal/schwung#661** (2026-10-22; AI use declared in the description, as CONTRIBUTING asks) |
| A3 | `button_passthrough` keeps Move's **LED colour** while a Tool suppresses the rest of the native LED sysex | branch `feat/overtake-passthrough-led-color` | Pending (see its doc); known risk: sysex index collision with pad notes 79/85/88 | Upstream issue #341. Small PR candidate |
| A4 | Declared knob-step mode, opt-in knob response curves, edit-speed fraction, tempo landmarks with header crop, knob-law contract refresh, Fine Lock | integration branch, inventory | Pending | Not offered upstream yet; decide per item which are general enough |
| A5 | Native button LED ownership (`CONTROL_BUFFER_SIZE` 256 → 512; shim and shadow UI must ship together) | integration branch | Pending | Fork-only for now |

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
