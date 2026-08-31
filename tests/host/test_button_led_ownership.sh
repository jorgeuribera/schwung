#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

fail() { echo "FAIL: $1" >&2; exit 1; }

constants="src/host/shadow_constants.h"
queue="src/host/shadow_led_queue.c"
ui="src/shadow/shadow_ui.c"
shim="src/schwung_shim.c"
hdr="src/host/shadow_led_queue.h"

grep -q "button_led_owned_mask\\[4\\]" "$constants" || \
  fail "shared control struct is missing the plain-shadow owned mask"
grep -q "button_led_release_mask\\[4\\]" "$constants" || \
  fail "shared control struct is missing the plain-shadow release mask"
grep -q "release_all_owned_button_leds" "$constants" || \
  fail "shared control struct is missing the plain-shadow release-all flag"

eligibleBody=$(awk '/^static inline int shadow_button_led_is_cc_eligible\(int cc\)/{f=1} f{print; if(/^}/) exit}' "$constants")
grep -q "case 49" <<<"$eligibleBody" || fail "eligible button helper must include Shift"
grep -q "case 50" <<<"$eligibleBody" || fail "eligible button helper must include Menu"
grep -q "case 85" <<<"$eligibleBody" || fail "eligible button helper must include transport buttons"
if grep -q "case 71" <<<"$eligibleBody"; then
  fail "knob rings must not be part of the button ownership API"
fi

for binding in \
  shadow_button_led_acquire \
  shadow_button_led_release \
  shadow_release_all_owned_button_leds
do
  grep -q "\"$binding\"" "$ui" || fail "missing JS binding: $binding"
done

requestExitBody=$(awk '/^static JSValue js_shadow_request_exit/{f=1} f{print; if(/^}/) exit}' "$ui")
grep -q "shadow_button_led_release_all_request();" <<<"$requestExitBody" || \
  fail "shadow_request_exit must request release-all before dismissing Shadow"

grep -q "service_plain_button_led_release_requests" "$queue" || \
  fail "LED queue is missing the plain-shadow release-request service"
grep -q "suppress_owned_plain_button_led_cc_packets" "$queue" || \
  fail "LED queue is missing owned-CC suppression"
grep -q "suppress_owned_plain_button_led_sysex_packets" "$queue" || \
  fail "LED queue is missing owned-sysex suppression"
grep -q "led_queue_restore_move_sysex_led_index" "$queue" || \
  fail "LED queue is missing per-button sysex restore"
grep -q "should_restore_all = ctrl->skip_led_clear ? 1 : 0" "$queue" || \
  fail "overtake entry must distinguish skip-led-clear from full takeover"
grep -q "should_drop_all = ctrl->skip_led_clear ? 0 : 1" "$queue" || \
  fail "full overtake entry must drop plain-shadow ownership without replay"

grep -q "LED_CAPTURE_F_SUPPRESSED_BY_OWNERSHIP" "$hdr" || \
  fail "capture flags must expose ownership suppression"
grep -q "raw=%02X %02X %02X %02X" "$shim" || \
  fail "capture log must print raw USB-MIDI bytes"
grep -q "owned_suppress=%u" "$shim" || \
  fail "capture log must print ownership-suppression state"
grep -q "sysex_bytes=%d" "$shim" || \
  fail "capture log must print sysex byte counts"

echo "  ok  plain-shadow ownership state is in shared control"
echo "  ok  button ownership excludes knob rings and has explicit JS bindings"
echo "  ok  release-all is wired into shadow_request_exit"
echo "  ok  cache/suppress/targeted-restore helpers exist in the LED queue"
echo "  ok  capture log includes raw bytes and ownership context"
echo "PASS: button LED ownership wiring is present and scoped"
