/* Full overtake + overtake_suppress_sysex + capabilities.button_passthrough.
 *
 * shadow_set_overtake_suppress_sysex(1) strips Move's cable-0 RGB LED sysex so
 * the native knob-ring / pad colors cannot leak over a tool's LEDs. But the
 * Track buttons (CC 40-43) are RGB too, and their color rides the same sysex:
 * a tool that yields those buttons to Move via button_passthrough got their
 * INPUT and CC latch through, yet lost their COLOR (muting a track no longer
 * dimmed its Track LED).
 *
 * Contract pinned here:
 *   - suppress on + passthrough list: an RGB LED command (F0 00 21 1D 01 01 3B
 *     <sub> <idx> ... F7, 6 USB-MIDI packets) whose idx is in the list reaches
 *     hardware intact; every other cable-0 sysex packet is still stripped.
 *   - suppress on, no list (or an empty one): everything stripped, as before.
 *   - suppress off: sysex untouched, as before.
 *   - partial / malformed commands are never kept (stripped as before).
 */
#include <stdio.h>
#include <string.h>

#include "shadow_led_queue.h"

static int fails = 0;
#define CHECK(cond, msg) do { \
    if (!(cond)) { fprintf(stderr, "FAIL: %s\n", msg); fails++; } \
} while (0)

static shadow_control_t control;
static shadow_control_t *control_ptr = &control;
static uint8_t midi_out[HW_MIDI_OUT_SIZE];
static uint8_t *ui_midi;
static uint8_t passthrough[128];

static void begin_host(const uint8_t *pt) {
    memset(&control, 0, sizeof control);
    memset(midi_out, 0, sizeof midi_out);
    led_queue_host_t host = {
        .midi_out_buf = midi_out,
        .shadow_control = &control_ptr,
        .shadow_ui_midi_shm = &ui_midi,
        .passthrough_ccs = pt,
    };
    led_queue_init(&host);
}

static void set_djttto_passthrough(void) {
    memset(passthrough, 0, sizeof passthrough);
    const int ccs[] = {40, 41, 42, 43, 79, 85, 88};
    for (size_t k = 0; k < sizeof ccs / sizeof ccs[0]; k++) passthrough[ccs[k]] = 1;
}

/* Enter full overtake on an empty frame so the transition ceremony is done
 * before the frame under test is filtered. */
static void enter_overtake(int suppress_sysex) {
    control.overtake_mode = 2;
    control.overtake_suppress_sysex = (uint8_t)suppress_sysex;
    memset(midi_out, 0, sizeof midi_out);
    shadow_clear_move_leds_if_overtake();
    memset(midi_out, 0, sizeof midi_out);
}

static void put(int slot, uint8_t b0, uint8_t b1, uint8_t b2, uint8_t b3) {
    midi_out[slot * 4 + 0] = b0;
    midi_out[slot * 4 + 1] = b1;
    midi_out[slot * 4 + 2] = b2;
    midi_out[slot * 4 + 3] = b3;
}

/* One Ableton RGB LED command, 6 packets starting at `slot`. */
static void put_rgb(int slot, uint8_t idx, uint8_t r, uint8_t g, uint8_t b) {
    put(slot + 0, 0x04, 0xF0, 0x00, 0x21);
    put(slot + 1, 0x04, 0x1D, 0x01, 0x01);
    put(slot + 2, 0x04, 0x3B, 0x10, idx);
    put(slot + 3, 0x04, r & 0x7F, r >> 7, g & 0x7F);
    put(slot + 4, 0x04, g >> 7, b & 0x7F, b >> 7);
    put(slot + 5, 0x05, 0xF7, 0x00, 0x00);
}

static int slot_zero(int slot) {
    return midi_out[slot*4] == 0 && midi_out[slot*4+1] == 0 &&
           midi_out[slot*4+2] == 0 && midi_out[slot*4+3] == 0;
}

static int span_zero(int slot, int n) {
    for (int s = slot; s < slot + n; s++) if (!slot_zero(s)) return 0;
    return 1;
}

static int span_equals(int slot, int n, const uint8_t *ref) {
    return memcmp(midi_out + slot * 4, ref + slot * 4, (size_t)n * 4) == 0;
}

/* Frame: Track 1 color (idx 40) | knob ring 1 (idx 71) | pad (idx 68) | CC 40 | CC 71 */
static void fill_mixed_frame(void) {
    memset(midi_out, 0, sizeof midi_out);
    put_rgb(0, 40, 20, 30, 40);
    put_rgb(6, 71, 100, 0, 0);
    put_rgb(12, 68, 0, 100, 0);
    put(18, 0x0B, 0xB0, 40, 127);
    put(19, 0x0B, 0xB0, 71, 5);
}

static void test_passthrough_color_survives_suppress(void) {
    set_djttto_passthrough();
    begin_host(passthrough);
    enter_overtake(1);
    fill_mixed_frame();
    uint8_t ref[HW_MIDI_OUT_SIZE];
    memcpy(ref, midi_out, sizeof ref);
    shadow_clear_move_leds_if_overtake();

    CHECK(span_equals(0, 6, ref), "Track 1 (idx 40) RGB sysex passes intact with suppress_sysex + passthrough");
    CHECK(span_zero(6, 6), "knob ring (idx 71) RGB sysex is still stripped");
    CHECK(span_zero(12, 6), "pad (idx 68) RGB sysex is still stripped");
    CHECK(span_equals(18, 1, ref), "passthrough CC 40 latch still passes");
    CHECK(slot_zero(19), "non-passthrough CC 71 still stripped");
}

static void test_every_listed_button_passes(void) {
    set_djttto_passthrough();
    begin_host(passthrough);
    enter_overtake(1);
    const uint8_t ids[] = {41, 42, 43, 79, 85, 88};
    for (size_t k = 0; k < sizeof ids; k++) {
        memset(midi_out, 0, sizeof midi_out);
        put_rgb(3, ids[k], 1, 2, 3);
        uint8_t ref[HW_MIDI_OUT_SIZE];
        memcpy(ref, midi_out, sizeof ref);
        shadow_clear_move_leds_if_overtake();
        char msg[96];
        snprintf(msg, sizeof msg, "listed idx %d RGB sysex passes", ids[k]);
        CHECK(span_equals(3, 6, ref), msg);
    }
}

static void test_no_list_strips_everything(void) {
    begin_host(NULL);
    enter_overtake(1);
    fill_mixed_frame();
    shadow_clear_move_leds_if_overtake();
    CHECK(span_zero(0, 20), "no passthrough list: all cable-0 sysex + CC stripped (unchanged)");
}

static void test_empty_list_strips_everything(void) {
    memset(passthrough, 0, sizeof passthrough);
    begin_host(passthrough);
    enter_overtake(1);
    fill_mixed_frame();
    shadow_clear_move_leds_if_overtake();
    CHECK(span_zero(0, 20), "empty passthrough list: all cable-0 sysex + CC stripped (unchanged)");
}

static void test_suppress_off_leaves_sysex_alone(void) {
    set_djttto_passthrough();
    begin_host(passthrough);
    enter_overtake(0);
    fill_mixed_frame();
    uint8_t ref[HW_MIDI_OUT_SIZE];
    memcpy(ref, midi_out, sizeof ref);
    shadow_clear_move_leds_if_overtake();
    CHECK(span_equals(0, 18, ref), "suppress off: all sysex untouched (unchanged)");
    CHECK(span_equals(18, 1, ref), "suppress off: passthrough CC 40 passes");
    CHECK(slot_zero(19), "suppress off: CC 71 stripped");
}

static void test_partial_commands_not_kept(void) {
    set_djttto_passthrough();
    begin_host(passthrough);
    enter_overtake(1);

    /* Tail of a command that started last frame: marker visible, no F0 start. */
    memset(midi_out, 0, sizeof midi_out);
    put(0, 0x04, 0x3B, 0x10, 40);
    put(1, 0x04, 1, 0, 1);
    put(2, 0x04, 0, 1, 0);
    put(3, 0x05, 0xF7, 0, 0);
    /* Head of a command that runs off the end of this frame (16 slots used,
     * command starts at slot 16 -> only 4 of its 6 packets fit). */
    put(16, 0x04, 0xF0, 0x00, 0x21);
    put(17, 0x04, 0x1D, 0x01, 0x01);
    put(18, 0x04, 0x3B, 0x10, 41);
    put(19, 0x04, 1, 0, 1);
    shadow_clear_move_leds_if_overtake();
    CHECK(span_zero(0, 20), "partial commands for listed idx are stripped, not kept");

    /* Marker for a listed idx but the span does not end in F7: malformed. */
    memset(midi_out, 0, sizeof midi_out);
    put_rgb(2, 40, 1, 2, 3);
    put(7, 0x04, 0x11, 0x22, 0x33);   /* not an end packet */
    shadow_clear_move_leds_if_overtake();
    CHECK(span_zero(0, 20), "malformed command (no sysex end) is stripped");

    /* Same command on cable 2 is not Move's LED output; untouched as before. */
    memset(midi_out, 0, sizeof midi_out);
    put_rgb(0, 71, 1, 2, 3);
    for (int s = 0; s < 6; s++) midi_out[s*4] |= 0x20;
    uint8_t ref[HW_MIDI_OUT_SIZE];
    memcpy(ref, midi_out, sizeof ref);
    shadow_clear_move_leds_if_overtake();
    CHECK(span_equals(0, 6, ref), "non-cable-0 sysex untouched (unchanged)");
}

static void test_two_listed_commands_back_to_back(void) {
    set_djttto_passthrough();
    begin_host(passthrough);
    enter_overtake(1);
    memset(midi_out, 0, sizeof midi_out);
    put_rgb(0, 42, 5, 6, 7);
    put_rgb(6, 43, 8, 9, 10);
    put_rgb(12, 72, 11, 12, 13);
    uint8_t ref[HW_MIDI_OUT_SIZE];
    memcpy(ref, midi_out, sizeof ref);
    shadow_clear_move_leds_if_overtake();
    CHECK(span_equals(0, 12, ref), "two consecutive listed commands (42, 43) both pass");
    CHECK(span_zero(12, 6), "following unlisted command (72) stripped");
}

int main(void) {
    test_passthrough_color_survives_suppress();
    test_every_listed_button_passes();
    test_no_list_strips_everything();
    test_empty_list_strips_everything();
    test_suppress_off_leaves_sysex_alone();
    test_partial_commands_not_kept();
    test_two_listed_commands_back_to_back();
    if (fails) {
        fprintf(stderr, "%d check(s) failed\n", fails);
        return 1;
    }
    puts("PASS: overtake suppress_sysex keeps button_passthrough RGB LED color");
    return 0;
}
