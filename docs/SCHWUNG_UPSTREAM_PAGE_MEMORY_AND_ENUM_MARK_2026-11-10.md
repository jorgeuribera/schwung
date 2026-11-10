# Schwung upstream UX proposals — optional page resume and fixed enum value marker

**Owner:** Jorge A. Uribe R. · **2026-11-10** · Status: source-audited proposal, offline prototype assigned; **no upstream submission or Move deployment**.

This public document covers **only the two generic Schwung UI features**. Any private product's modulation-routing UI requirements are deliberately outside its scope and must not be researched, represented, or implemented by external/free coding agents.

## A. Optional remember-last-page on module reentry

Current upstream behavior: `src/shadow/shadow_ui_param_pages.mjs` exposes `enterParamPages(slot, component, prefix, restorePageName, ...)` and `src/shared/param_pages/page_controller.mjs` implements `restorePage(name, {enter})`. Today the host supplies an explicit restore name for certain return paths (e.g. from an editor/preset browser), **not when a user exits a module and later re-enters it**. `exitParamPages()` drops the controller; therefore returning to page 1 is expected. The owner wants a distinct opt-in preference, not a bug workaround or enabling a dormant setting.

**Design:** in Global Settings under an appropriate navigation/UI section, `Remember Module Page`, default **Off**. Persist the *preference* with existing settings infrastructure. When enabled, on normal module exit remember the active **page name** for the exact container and module identity. On later reentry restore only when that name is still available and the module identity matches. Use separate identities for track slot, Master FX, Send A/B buses, module position and loaded module. A name is preferable to an array index because modules' page sequence can change after dynamic hierarchy/mode/preset updates. A saved index 4 might become the wrong page; a saved name `Delay B` can be relocated safely. If the page no longer exists, land normally at page 1.

Explicit editor/browser one-shot restore remains higher priority. Do not auto-open a destructive action, silently commit changes, or re-trigger momentary actions. Screen reader, LED restoration, current params and module replacement should behave unchanged. Consider session-only page memory initially; do not introduce new disk formats needlessly. Acceptance: track/module swap, two tracks using same module, Master, Send A/B, dynamic/reordered pages, Off behavior, normal Back/Exit, TTS, no unnecessary IPC/DSP reads.

## B. Active enum value marker in a fixed LEFT gutter

Current upstream `src/shared/param_pages/enum_list.mjs` passes `getValue(item, i) => i === markIndex ? '*' : ''` to `drawMenuList` in `src/shared/menu_layout.mjs`. Thus the star appears on the **right**, inside the value column. It indicates the **currently active value**, **not the cursor row**. Picker and peek modes differ: choosing a new item may not write until commit (picker), whereas peek follows an already-performed knob write. Preserve these semantics.

The owner reports the right-hand mark visually conflicting with long labels; move only this mark into a fixed small left gutter. The glyph should be independent of text, so it remains visible while a long selected label marquee-scrolls. Reserve consistent width for both marked and unmarked rows; keep text clear of the left mark and scrollbar; preserve selected-row inverse paint and accessible announcements. Prefer an optional `getLeadingMark`/similar argument on the shared `drawMenuList` rather than reimplementing the picker. A raw `'* ' + label` prefix is insufficient if the glyph scrolls off.

**Important separate semantic:** the modified-user-preset mark is **already leading** in `src/shared/param_pages/current_preset.mjs` (`presetRowValue` returns `'* ' + name` when modified) and in `src/shadow/shadow_ui_param_pages.mjs`'s header (`S1 > * preset`). The standalone saved-preset browser `src/shadow/shadow_ui_presets.mjs` draws the names of saved presets and highlights the current one; it does **not** reuse the enum right-hand star as a dirty mark. Do not move any existing preset-dirty marks.

Acceptance: short/very long selected labels, 1/2/many enum options, right vs left before/after rendered frame comparisons, marquee, selected vs marked different rows, highlight inversion, zero clipped pixels, fixed star under scrolling, TTS, Back/commit/peek behavior. Existing harness `tests/host/test_enum_picker_chrome.sh`.

## Scope and submission

This is suitable for **two separate small upstream PRs** against `charlesvestal/schwung`: first fixed enum marker, then optional page memory. First implement/test against only public Schwung source with synthetic examples and offline framebuffer/unit tests; obtain real hardware tests and owner review before submitting upstream or installing to Move. The separate F031 public pilot in `jorgeuribera/feature-workbench` is **not** a patch already merged into Schwung.
