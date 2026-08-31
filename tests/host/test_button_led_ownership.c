/* Regression test for plain-Shadow native button LED ownership.
 *
 * The contract:
 *   - native cache updates BEFORE ownership suppression
 *   - owned buttons suppress Move's hardware writes, but only for themselves
 *   - custom writes still reach hardware
 *   - release restores the LATEST native state, not the acquire-time one
 *   - release-all fires on explicit request and on leaving plain Shadow
 *   - sysex for the same button index is part of the same logical identity
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

static void begin_host(void) {
    memset(&control, 0, sizeof control);
    memset(midi_out, 0, sizeof midi_out);
    control.display_mode = 1;
    led_queue_host_t host = {
        .midi_out_buf = midi_out,
        .shadow_control = &control_ptr,
        .shadow_ui_midi_shm = &ui_midi,
        .passthrough_ccs = NULL,
    };
    led_queue_init(&host);
}

static void empty_frame(void) {
    memset(midi_out, 0, sizeof midi_out);
}

static void own_button_cc(uint8_t cc) {
    int word = shadow_button_led_mask_word(cc);
    control.button_led_owned_mask[word] |= shadow_button_led_mask_bit(cc);
}

static void request_release(uint8_t cc) {
    int word = shadow_button_led_mask_word(cc);
    control.button_led_release_mask[word] |= shadow_button_led_mask_bit(cc);
}

static void write_native_cc(int packet_index, uint8_t cc, uint8_t value) {
    int pos = packet_index * 4;
    midi_out[pos] = 0x0B;
    midi_out[pos + 1] = 0xB0;
    midi_out[pos + 2] = cc;
    midi_out[pos + 3] = value;
}

static void write_native_sysex_led(int packet_index, uint8_t subcmd, uint8_t idx, uint8_t seed) {
    int pos = packet_index * 4;
    midi_out[pos + 0] = 0x04; midi_out[pos + 1] = 0xF0; midi_out[pos + 2] = 0x00; midi_out[pos + 3] = 0x21;
    midi_out[pos + 4] = 0x04; midi_out[pos + 5] = 0x1D; midi_out[pos + 6] = 0x01; midi_out[pos + 7] = 0x01;
    midi_out[pos + 8] = 0x04; midi_out[pos + 9] = 0x3B; midi_out[pos +10] = subcmd; midi_out[pos +11] = idx;
    midi_out[pos +12] = 0x04; midi_out[pos +13] = seed; midi_out[pos +14] = (uint8_t)(seed + 1); midi_out[pos +15] = (uint8_t)(seed + 2);
    midi_out[pos +16] = 0x04; midi_out[pos +17] = (uint8_t)(seed + 3); midi_out[pos +18] = (uint8_t)(seed + 4); midi_out[pos +19] = (uint8_t)(seed + 5);
    midi_out[pos +20] = 0x05; midi_out[pos +21] = 0xF7; midi_out[pos +22] = 0x00; midi_out[pos +23] = 0x00;
}

static int packet_present(uint8_t type, uint8_t data1, uint8_t data2) {
    for (int i = 0; i < HW_MIDI_OUT_SIZE; i += 4) {
        if ((midi_out[i + 1] & 0xF0) == type &&
            midi_out[i + 2] == data1 &&
            midi_out[i + 3] == data2) return 1;
    }
    return 0;
}

static int sysex_led_present(uint8_t idx) {
    for (int i = 8; i + 12 < HW_MIDI_OUT_SIZE; i += 4) {
        if ((midi_out[i] & 0x0F) == 0x04 &&
            ((midi_out[i] >> 4) & 0x0F) == 0 &&
            midi_out[i + 1] == 0x3B &&
            midi_out[i + 3] == idx) {
            return 1;
        }
    }
    return 0;
}

static void test_unowned_passthrough_is_unchanged(void) {
    begin_host();
    write_native_cc(0, 50, 11);
    shadow_clear_move_leds_if_overtake();
    CHECK(packet_present(0xB0, 50, 11),
          "unowned button LED passes through unchanged");
}

static void test_owned_button_suppresses_but_custom_can_drive(void) {
    begin_host();
    own_button_cc(50);

    write_native_cc(0, 50, 11);
    shadow_clear_move_leds_if_overtake();
    CHECK(!packet_present(0xB0, 50, 11),
          "owned button suppresses native hardware packet");

    empty_frame();
    shadow_queue_led(0x0B, 0xB0, 50, 99);
    shadow_flush_pending_leds();
    CHECK(packet_present(0xB0, 50, 99),
          "custom owned button LED reaches hardware");

    empty_frame();
    request_release(50);
    shadow_clear_move_leds_if_overtake();
    shadow_flush_pending_leds();
    CHECK(packet_present(0xB0, 50, 11),
          "release restores cached native value, not the custom one");
}

static void test_latest_native_wins_on_release(void) {
    begin_host();
    own_button_cc(50);

    write_native_cc(0, 50, 11);
    shadow_clear_move_leds_if_overtake();
    empty_frame();
    write_native_cc(0, 50, 22);
    shadow_clear_move_leds_if_overtake();
    CHECK(!packet_present(0xB0, 50, 22),
          "owned button keeps suppressing later native updates");

    empty_frame();
    request_release(50);
    shadow_clear_move_leds_if_overtake();
    shadow_flush_pending_leds();
    CHECK(packet_present(0xB0, 50, 22),
          "release restores the latest native value seen while owned");
}

static void test_two_owned_buttons_are_independent(void) {
    begin_host();
    own_button_cc(50);
    own_button_cc(51);

    write_native_cc(0, 50, 10);
    write_native_cc(1, 51, 20);
    shadow_clear_move_leds_if_overtake();
    CHECK(!packet_present(0xB0, 50, 10),
          "first owned button is suppressed");
    CHECK(!packet_present(0xB0, 51, 20),
          "second owned button is suppressed");

    empty_frame();
    request_release(50);
    shadow_clear_move_leds_if_overtake();
    shadow_flush_pending_leds();
    CHECK(packet_present(0xB0, 50, 10),
          "releasing one owned button restores only that button");
    CHECK(!packet_present(0xB0, 51, 20),
          "releasing one owned button does not restore the other");

    empty_frame();
    write_native_cc(0, 51, 21);
    shadow_clear_move_leds_if_overtake();
    CHECK(!packet_present(0xB0, 51, 21),
          "other owned button remains suppressed after the first is released");
}

static void test_release_all_restores_everything(void) {
    begin_host();
    own_button_cc(50);
    own_button_cc(51);

    write_native_cc(0, 50, 10);
    write_native_cc(1, 51, 20);
    shadow_clear_move_leds_if_overtake();

    empty_frame();
    control.release_all_owned_button_leds = 1;
    shadow_clear_move_leds_if_overtake();
    shadow_flush_pending_leds();
    CHECK(packet_present(0xB0, 50, 10),
          "explicit release_all restores first owned button");
    CHECK(packet_present(0xB0, 51, 20),
          "explicit release_all restores second owned button");
}

static void test_display_exit_triggers_release_all(void) {
    begin_host();
    own_button_cc(50);
    own_button_cc(51);

    write_native_cc(0, 50, 33);
    write_native_cc(1, 51, 44);
    shadow_clear_move_leds_if_overtake();

    empty_frame();
    control.display_mode = 0;
    shadow_clear_move_leds_if_overtake();
    shadow_flush_pending_leds();
    CHECK(packet_present(0xB0, 50, 33),
          "leaving plain Shadow restores first owned button");
    CHECK(packet_present(0xB0, 51, 44),
          "leaving plain Shadow restores second owned button");
}

static void test_owned_sysex_follows_same_logical_button_identity(void) {
    begin_host();
    own_button_cc(50);

    write_native_sysex_led(0, 0x10, 50, 0x20);
    write_native_sysex_led(6, 0x10, 51, 0x40);
    shadow_clear_move_leds_if_overtake();
    CHECK(!sysex_led_present(50),
          "owned button suppresses native sysex for the same logical index");
    CHECK(sysex_led_present(51),
          "owning one button does not suppress another button's sysex");

    empty_frame();
    request_release(50);
    shadow_clear_move_leds_if_overtake();
    shadow_flush_pending_leds();
    CHECK(sysex_led_present(50),
          "release restores targeted sysex for the released button");
    CHECK(!sysex_led_present(51),
          "targeted sysex restore does not repaint another button");
}

static void test_duplicate_release_and_invalid_control_are_safe(void) {
    begin_host();
    own_button_cc(50);

    write_native_cc(0, 50, 12);
    shadow_clear_move_leds_if_overtake();

    empty_frame();
    request_release(50);
    request_release(50);
    /* Invalid: knob ring, not a button LED in this API. */
    control.button_led_release_mask[shadow_button_led_mask_word(71)] |= shadow_button_led_mask_bit(71);
    shadow_clear_move_leds_if_overtake();
    shadow_flush_pending_leds();
    CHECK(packet_present(0xB0, 50, 12),
          "duplicate release still produces one correct restore");
    CHECK(!packet_present(0xB0, 71, 0),
          "invalid button identity is ignored safely");
}

int main(void) {
    test_unowned_passthrough_is_unchanged();
    test_owned_button_suppresses_but_custom_can_drive();
    test_latest_native_wins_on_release();
    test_two_owned_buttons_are_independent();
    test_release_all_restores_everything();
    test_display_exit_triggers_release_all();
    test_owned_sysex_follows_same_logical_button_identity();
    test_duplicate_release_and_invalid_control_are_safe();
    if (fails) {
        fprintf(stderr, "%d check(s) failed\n", fails);
        return 1;
    }
    puts("PASS: plain Shadow button LED ownership");
    return 0;
}
