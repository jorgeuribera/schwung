# Native Button LED Ownership — Research Audit (feature/native-button-led-ownership)

> **Status: research / not deployed**. Branch `feature/native-button-led-ownership` is a
> private investigation off `integration/ux-additions` (`6fffbff7`). DO NOT merge to
> candidate or deploy to device without explicit approval.

## Goal

Generic, non-Shift-specific mechanism for temporary ownership of illuminated native
Move buttons with deterministic restoration of firmware state.

Immediate motivation: `Shift Lock ON → physical Shift LED pulses/blinks`.
Generic target: any illuminated button (Shift, Back, Menu, Mute, Play, Rec, etc.)
and potentially RGB transport/track LEDs if later needed.

Desired lifecycle:

```
acquireButtonLed(control)  // remember & mark owned
setButtonLed(control, value) / pulseButtonLed(control, policy)
releaseButtonLed(control)  // stop custom output → restore latest native
```

Critical property: restore target should be the **latest** native state observed
while owned, not a stale acquire-time snapshot, if architecture makes that
reliable. Fail-safe: if deterministic restore cannot be proven, **do not**
implement physical Shift LED pulse.

---

## 1. Current LED architecture (audit 2026-08-30)

### 1.1 Files

- `src/host/shadow_led_queue.c` — single source of truth for LED caching,
  queuing, and flushing. ~1214 LOC.
- `src/host/shadow_led_queue.h` — public API + capture ring definition.
- `src/host/shadow_constants.h` — `shadow_control_t` fields
  `restore_knob_leds`, `corun.led_keep_mask`, `CORUN_F_LED_DISTINCT`,
  LED group map, `corun_led_keep_mask_eff()`.
- `src/shadow/shadow_ui.c` — JS bindings
  `shadow_corun_set_led_keep_mask`, `shadow_corun_set_led_cede_mask`,
  `shadow_restore_knob_leds`, `shadow_set_skip_led_clear`, etc.
- `src/schwung_shim.c` — CC_SHIFT=49, shift-off injection on overtake exit,
  `shadow_clear_move_leds_if_overtake` + flush called each SPI frame (~344 Hz).
- `src/host/shadow_midi.c` / `shadow_midi.h` — MIDI routing, passthrough lists.
- `src/shared/constants.mjs` — `MoveShift = 49`.

### 1.2 How Move LED state is learned (Q-A)

**Q-A: How does Schwung learn the latest value Move firmware wanted for an LED?**

Every SPI frame, `shadow_clear_move_leds_if_overtake()` (called from shim)
scans `midi_out_buf` (HW MIDI_OUT mailbox, 20 packets / 80 bytes) before any
clearing, for `cable==0 && (type==0x90 || 0x80 || 0xB0)`. For each match it
accumulates:

```c
move_note_led_state[d1] = color;          // note 0-127
move_cc_led_state[d1]   = d2;            // CC 0-127, value 0-127
move_cc_led_cin/status  // CIN + full status for faithful replay
```

When **not** in overtake (`overtake_mode < 2`), this scan runs **every frame**
unconditionally — so normal Shadow UI (display_mode=1, overtake=0) is a
continuous passthrough cache. Also runs when `skip_led_clear` is set during
overtake, to keep snapshot up-to-date.

A second path caches the *RGB* colour, which is **not in the CC** at all: Move
firmware emits the real colour as an Ableton sysex
`F0 00 21 1D 01 01 3B <subcmd> <idx> <6 rgb bytes> F7` (6 USB-MIDI packets).
`led_queue_move_sysex_packet()` reassembles this per `(subcmd, idx)` in
`move_sysex_led_cache[subcmd][idx]` (valid flags + raw packets). Frozen on
overtake entry, replayed on exit via `led_queue_restore_move_sysex_leds()`.

Conclusion: the *authoritative* colour for white buttons (RGB) lives in sysex,
not CC. The CC cache is a latch trigger. Restoring CC alone gives “off” or
stale. This is precisely why `service_knob_led_restore` replays the **sysex**
cache, not `move_cc_led_state[71..78]`.

### 1.3 Which LEDs have cached native state (Q-B)

- CC cache: `move_cc_led_state[128]`, init `-1 = unknown` (`src/host/shadow_led_queue.c:91-93`).
  `hw_cc_leds[]` lists physically-existent indices that actually get restored/cleared
  (`src/host/shadow_led_queue.c:135-146`):
  ```
  16-31  UI buttons below sequencer
  40-43  Track row
  49,50,51,52,54,55,56,58,60,62,63  White buttons (Shift=49, etc.)
  71-78  Encoder knob rings (RGB)
  85,86,88,118,119  Transport / Record (RGB)
  ```
  So **CC 49 (Shift) is a real hw LED with full cache entry**.

- Note cache: `move_note_led_state[128]` for pads/steps (68-99 etc.).

- Sysex cache: `move_sysex_led_cache[2][128]` (subcmd 0x10 = RGB, 0x00 = palette/mode)
  indexed by the same `idx` as CC/note.

All three caches are updated every frame outside overtake, so they track latest
firmware intent — but only while `shadow_clear_move_leds_if_overtake` runs.

### 1.4 Which paths suppress firmware LED writes (Q-C)

- **Normal Shadow UI** (`display_mode==1`, `overtake_mode==0`): **no suppression**.
  `shadow_clear_move_leds_if_overtake` returns early after caching
  (`if (!cur_overtake) return;` at ~447). Firmware CC/note/sysex packets stay
  in `midi_out_buf` and reach hardware. Result: any custom write via
  `shadow_queue_led(B0 49 …)` races with firmware’s own B0 49 write in the same
  frame — flicker, not ownership.

- **Full overtake** (`overtake_mode>=2`): clears cable-0 LEDs aggressively.
  For `cable==0` packets: note LEDs (0x90) always cleared; CC LEDs cleared
  unless `passthrough_ccs[d1]` is set; sysex cleared if
  `overtake_suppress_sysex` is set. During `CORUN_TARGET_MOVE_NATIVE` with
  `led_keep_mask` eff, Move’s writes for groups in `keep` are actively **stripped**
  per `corun_group_for_event(type,d1)` (`src/host/shadow_led_queue.c:459-499`).
  That is the only today-per-group ownership.

- **Co-run LED ownership**: `shadow_control_t.corun.led_keep_mask`
  (`src/host/shadow_constants.h:184`) — `0 = follow keep_mask` unless
  `CORUN_F_LED_DISTINCT` is set, then 0 is meaningful “cede all”. Effective
  mask via `corun_led_keep_mask_eff()` (`shadow_constants.h:373`). Scoped to
  move_native co-run; outside that, no per-button keep.

### 1.5 How knob rings are restored (Q-D)

Knob rings (CC 71-78) are RGB, not CC values. Flow:

1. JS leaves knob grid → calls `shadow_restore_knob_leds()` → sets
   `shadow_control->restore_knob_leds = 1` (edge flag, `shadow_ui.c:603`).
2. Next SPI frame, `service_knob_led_restore()` sees the edge, clears it, and
   calls `led_queue_restore_move_sysex_leds()` (`shadow_led_queue.c:324-328`).
3. That arms `move_sysex_restore_pending`; subsequent
   `shadow_flush_pending_leds()` calls `led_queue_flush_move_sysex_restore(1)`
   — 1 LED per tick (6 packets), 2 passes for reliability. Buffer needs
   contiguous 6-packet block (`find_contiguous_empty_block`).
4. Cache was **continuously accumulated** in #1.2, frozen on overtake entry if
   applicable. For knob-grid (non-overtake), there is no snapshot — it just
   replays whatever firmware last sent.

Key lesson: **CC restore would blank the rings**; must replay sysex.

### 1.6 Overtake snapshot/restore vs normal Shadow (Q-E)

| Aspect | Overtake (mode ≥2) | Normal Shadow (mode 0) |
|--------|-------------------|------------------------|
| Entry  | snapshot `move_*_led_state[128]` + freeze sysex cache; `queue_hw_leds_off()` (or do nothing if `skip_led_clear`) | none |
| While  | firmware LEDs stripped per mask/passthrough; JS owns LEDs via queued `midi_out` | firmware LEDs **not stripped**; JS queue races firmware |
| Exit   | `queue_hw_leds_restore()` replays snapshot for hw LEDs + `led_queue_restore_move_sysex_leds()` replays sysex; 2 passes; or `discard_pending_shadow_leds()` + `cancel_move_sysex_restore_and_thaw()` if `skip_led_clear`/`native_repaint` | `restore_knob_leds` edge only for rings; no general restore |
| State  | `snapshot_valid`, `snapshot_skip_restore`, `move_led_{clear,restore}_pending` | `restore_knob_leds` edge only |

Overtake’s restore is **whole-surface** (`hw_note_leds` + `hw_cc_leds`) and
needs no per-LED mapping because it repaints everything. Knob-grid restore is
**targeted** (sysex only, 8 LEDs).

### 1.7 CC49/Shift LED observability (Q-F)

- `hw_cc_leds` contains `49`, so it participates in snapshot/restore/off sets.
- `move_cc_led_state[49]` is written every frame outside overtake from
  `midi_out[i+2]==49 && type==0xB0` (`shadow_led_queue.c:360`).
- `led_queue_move_sysex_packet` also captures Shift row RGB variant (Shift keys
  with RGB icons are driven via sysex palette+RGB). Whether Shift uses CC
  brightness vs sysex palette is not pinned by code comments — both exist.
- Capture ring (`led_capture_ring[2048]`, `led_capture_record`, gated by
  `led_queue_set_capture_enabled`) currently has **no caller** and no drain
  dump path — cannot be used to empirically map Shift’s LED encoding without
  adding one.

**Result:** CC49 writes are observable; RGB sysex for Shift (if any) is also
cached, but untangling which drives the physical LED requires a live sniff.

### 1.8 Race while owned (Q-G)

If Schwung temporarily owned Shift LED via queuing:

- Outside overtake: Move’s B0 49 packet remains in `midi_out_buf`; custom packet
  is queued to a free or next-available slot (`shadow_flush_pending_leds` budget
  `SHADOW_LED_MAX_UPDATES_PER_TICK=16`, `SAFE_BYTES=76`). Both packets may be in
  the same frame — hardware sees whichever is last in the buffer or interleaved
  across frames → visible flicker, not deterministic.

- During overtake with appropriate `led_keep_mask`: Move’s B0 49 could be
  stripped (if `CORUN_GRP_SHIFT` in keep). But Shift Lock lives inside normal
  Shadow UI, not overtake — so that path does not apply without moving Shift
  Lock into a keep-mask-owned context.

- `move_cc_led_state[49]` would continue updating if Move’s packet wasn’t
  stripped (since caching happens before clearing). So “latest native state” is
  in principle available for restore — **but** only if suppression and caching
  are arranged to happen consistently.

### 1.9 Lifecycle boundaries

- **Shadow UI enter/leave:** `display_mode` toggles 0↔1; `shadow_ui` process
  (PID 1011) is a long-lived host process, not per-view. Exiting Shadow back to
  Move native clears `display_mode` but does **not** auto-restore any custom
  LEDs unless explicit code runs (e.g. `restore_knob_leds` on grid leave).

- **Overtake enter/leave:** snapshot/restore pair covers exit, but only for
  overtake sessions.

- **Process exit / SIGABRT:** shim fallback? No generic “clear custom LEDs on
  shadow_ui exit” path was found. `shadow_clear_move_leds_if_overtake`’s
  `discard_pending_shadow_leds` drains tool-pending writes on native repaint,
  but a Shift-LED pulse would not be in that tool-pending set (it’s a Shadow
  queue). An orphaned pulse could persist until Move repaints the button on its
  next state change — undefined duration.

- **Mode changes (session/note/set_overview):** `move_ui_mode` is derived state
  (`shadow_constants.h:143`) and influences snapshot handling (e.g.
  `skip_led_clear` repaint path avoids stale snapshots across mode mismatches).
  A stale snapshot across a mode change would repaint wrong colours — one reason
  the current code can bail to native repaint.

### 1.10 Constants / helpers

- `MoveShift = 49` (`src/shared/constants.mjs:49`, `shadow_midi.h`, `schwung_shim.c`).
- Groups: `CORUN_GRP_SHIFT = (1u<<8)` (`shadow_constants.h:261`).
- Shadow UI triggers: Shift+Vol or long-press (`shadow_constants.h:154`).

---

## 2. Desired generic semantics (recap)

```
acquireButtonLed(controlId)  // e.g. CORUN_GRP_SHIFT or raw CC 49
  - mark owned
  - ensure native cache is fresh (frame-synced)

setButtonLed(controlId, value)   // queue custom value, suppress native for owned set
pulseButtonLed(controlId, policy) // e.g. 2 Hz blink, needs tick source

releaseButtonLed(controlId)
  - stop custom output (clear queue entry)
  - restore/replay latest valid native state (CC + sysex if RGB)
  - hand ownership back
  - safe on: leave Shadow UI, overtake exit, process exit, reboot
```

Critical property: restore target = latest native observed **while owned**.

### Feasibility assessment (honest)

| Property | Feasible today? | Blocker |
|----------|-----------------|---------|
| **Observe latest native Shift LED** | ✅ yes (CC cache + sysex cache continuous outside overtake) | need to decide which (CC vs sysex) actually drives Shift LED; may need cable-0 capture to prove |
| **Suppress native while owned** | ⚠️ partial | Outside overtake there is *no* per-button suppression. Would need a new generic `button_led_keep_mask` (outside corun) or moving Shift Lock into an owned context. `corun.led_keep_mask` only works during `CORUN_TARGET_MOVE_NATIVE`. |
| **Queue custom pulse** | ✅ yes | `shadow_queue_led(cable 0, B0, 49, val)` + tick-driven toggle; budget 16/frame is ample for 2 Hz. |
| **Deterministic restore** | ⚠️ risky without new suppression | If native was not suppressed, the known “latest” is trustworthy, but hardware may have shown flicker (both streams). If native *was* suppressed, latest is only as fresh as suppression allows — need to keep caching while suppressed (as overtake does with `skip_led_clear` flow). |
| **Fail-safe on exit** | ❌ not today | No generic “clear owned LEDs on Shadow UI exit / process death” path exists. `restore_knob_leds` is single-target edge; overtake exit clears `led_keep_mask`; plain Shadow exit does not. An owned Shift pulse could survive Shadow exit until Move happens to repaint — violates “never blink forever” requirement. |
| **Reboot persistence** | ✅ by definition | Shadow UI is a process; reboot starts clean. Requirement is Shift Lock OFF after reboot — already true (`shiftLocked = false` init). LED follows. |

**Overall verdict:** *Generic infrastructure is conceptually feasible, but
deterministic restore cannot be proven today without first adding a
Shadow-UI-scoped LED ownership mask + suppression + exit-restore path distinct
from the overtake snapshot.*

- Knob-ring restore is **not a suitable template**: it replays sysex for a
  known-fixed offset (CC 71-78) after Share zone; button LEDs span CC 49 etc. and
  may be CC-driven, sysex-driven, or both.

- The overtake `led_keep_mask` + `corun_group_for_event` grouping is the right
  direction, but scope-broadening it to plain Shadow UI (or adding a parallel
  `shadow_button_led_mask`) is a design decision, not a one-line patch.

### Alternative considered and rejected (for now)

Move Shift Lock pulse into a `CORUN_TARGET_MOVE_NATIVE` co-run so existing
`led_keep_mask` ownership applies. Rejected: Shift Lock is a Shadow UI feature,
not an overtake tool; forcing a co-run session just for one LED would tangle
input ownership (keep/cede for all groups) and OLED ownership.

---

## 3. What remains to prove before implementation

1. **Empirical Shift LED encoding:** Is the physical Shift LED driven by
   `B0 31 <val>` (CC value), by sysex `3B 10 <49> <rgb>` (palette/RGB), or
   both? Add a non-invasive `led_capture` drain thread or use `HW_MIDI_OUT`
   logging on device to record cable-0 traffic while toggling native Shift.

2. **Suppression semantics for plain Shadow:** Define and implement a
   `shadow_button_led_owned_mask` (or reuse `led_keep_mask` outside corun) that
   `shadow_clear_move_leds_if_overtake` *or a new Shadow-stage filter* respects
   even when `overtake_mode==0`. Cache must keep updating while suppressed
   (as overtake `skip_led_clear` does) to satisfy “latest native”.

3. **Exit-restore wiring:** On any of: Shadow UI `display_mode 1→0`, process
   `SIGTERM`/exit, `should_exit`, or crash, clear owned bits and queue restore
   of latest cached state (CC + sysex). Needs a new `restore_button_leds` edge
   analogous to `restore_knob_leds`, or a on-exit sweep.

4. **Mode / race handling:** Verify firmware does not change Shift LED while
   owned (e.g. entering SysEx splash) in a way that would be lost. If it does,
   caching-while-suppressed must remain correct.

5. **Multiplex with overtake:** Owned-button set must not clash with a later
   overtake snapshot. Either forbid overlap or layer the masks.

---

## 4. Candidate API sketch (not implemented)

```c
// host side (C) — proposed, not yet built
int shadow_button_led_acquire(uint32_t grp_mask);  // e.g. CORUN_GRP_SHIFT
int shadow_button_led_pulse(uint32_t grp_mask, uint32_t period_ms, uint8_t on_val, uint8_t off_val);
int shadow_button_led_set(uint32_t grp_mask, uint8_t val);
int shadow_button_led_release(uint32_t grp_mask); // deterministic restore + unown
```

```js
// shadow_ui side — proposed
shadow_button_led_acquire(CORUN_GRP_SHIFT);
shadow_button_led_pulse(CORUN_GRP_SHIFT, 500, 127, 0);
// on leave / Shift Lock OFF:
shadow_button_led_release(CORUN_GRP_SHIFT);
```

Ownership bit would live in `shadow_control_t` (new byte/word; budget for
`CONTROL_BUFFER_SIZE` — currently 84, check `shadow_control_size_check`).
Suppress logic: in the per-frame MIDI_OUT filter, zero any `B0 d1` where
`grp & owned_mask`, and stash its value into `move_cc_led_state` **before**
zeroing (so “latest native” stays fresh).

---

## 5. Hardware validation plan (when ready)

- Device build: `feature/native-button-led-ownership` with ownership op.
- Steps:
  1. Enter Shadow → double-tap Shift → Shift LED blinks at 2 Hz, screen says
     “Shift lock on”.
  2. Observe native Shift state while owned: toggle Move’s own Shift-driving
     condition (if any) — verify latest wins on release.
  3. Exit Shadow (Shift+Menu / Back toggle) → Shift Lock clears, LED stops
     blinking, native state restored immediately.
  4. Kill `shadow_ui` PID → within one frame, LED restored (no forever-blink).
  5. Reboot → Shift Lock OFF, LED off/normal.
  6. Repeat with other buttons (Menu CC50, Back CC51) to prove generic.
- Capture: `led_capture_ring` dump before/after to assert `B0 49` suppression
  and cache accuracy.

---

## 6. Upstreamability notes

- Keep generic implementation free of WET2/TUNNEL/DJTO semantics. Private modules
  may later consume `shadow_button_led_*` but must not leak into the generic
  layer.
- If architecture lands clean, prepare: design note (this doc), tests
  (`tests/host/test_button_led_ownership.sh` — simulate queue + cache + release),
  hardware validation matrix, and list of supported illuminated controls
  (`hw_cc_leds` plus pads).
- **No upstream PR yet, no public branch push** without explicit authorization.

---

## 7. Immediate recommendation

> **Do not implement physical Shift LED pulse in the deployed candidate
> (`integration/ux-additions` / `6fffbff7`).** The fail-safe (deterministic
> restore, never blink forever after Shadow exit) cannot be proven with the
> current ownership plumbing. The screen/announce-only Shift Lock feedback
> ships as-is.

Next commit on `feature/native-button-led-ownership` should add the
capture-drain diagnostic (wire `led_queue_set_capture_enabled` to a debug flag
+ dump via `schwung-testd` or log) so that Q-6 can be answered on hardware
without guessing.

---

## 8. Note/Session control-map note (backlog, §11)

`move_ui_mode` (0=unknown,1=session,2=note,3=set_overview) is derived state
observed in `shadow_control_t`, not a raw Note/Session button binding. No
authoritative raw Note/Session physical event (note/CC) was found in this
audit. Do not guess from Push. When needed for DJTO Session Transition
Inspector, perform a minimal read-only raw-event sniff (subscribe to MIDI_IN or
drain capture ring) with hardware in hand.

---

## 9. References

- `src/host/shadow_led_queue.c:329-413` — overtake snapshot / skip_led_clear
- `src/host/shadow_led_queue.c:135-146` — `hw_cc_leds` (includes CC49)
- `src/host/shadow_led_queue.c:86-113` — `move_cc_led_state` cache
- `src/host/shadow_constants.h:196-212` — `restore_knob_leds` edge
- `src/host/shadow_constants.h:260-262` — `CORUN_GRP_SHIFT`
- `src/shadow/shadow_ui.c:602-608` — `shadow_restore_knob_leds` binding
- `src/shadow/shadow_ui.c:337-346` — `led_keep_mask` / `CORUN_F_LED_DISTINCT`

