/* Battery, USB, the pilot LED and switching off (docs/hardware.md, ConsolaS3 LEEME). The battery is read on IO8
 * through a 2:1 divider; USB on IO43 (the console's divider from VBUS: about 3 V when plugged); the LED is
 * red on IO45 and green on IO46. The charger's own status pin reaches no GPIO, so "charged" is a voltage guess.
 *
 *   power on       green rising over 0.6 s          on battery    dim green
 *   charging       orange breathing                 charged       steady green
 *   low (< 3.6 V)  a red flash every 3 s            critical (< 3.4 V): fast red, the game saves and sleeps
 *   off (menu)     green fading, then deep sleep; BOOT (or the power switch) wakes it */
#include "power.h"

#include "audio_out.h"
#include "display.h"
#include "driver/gpio.h"
#include "driver/ledc.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_sleep.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <math.h>

#define PIN_USB 43
#define PIN_RED 45
#define PIN_GREEN 46
#define PIN_BOOT 0
#define LOW_V 3.6f
#define CRITICAL_V 3.4f
#define FULL_V 4.15f
#define DIM 0.08f /* the running glow */

static adc_oneshot_unit_handle_t adc;
static adc_cali_handle_t cali;
static volatile float volts;
static volatile bool usb, critical, off; /* off: power_off owns the LED */
static volatile int game_led = -1;        /* a game's colour for the LED (led() in Lua), -1: the console's own */

static void led(float red, float green) { /* 0..1 each */
    ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_1, (uint32_t)(255 * (red < 0 ? 0 : red > 1 ? 1 : red)));
    ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_1);
    ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_2, (uint32_t)(255 * (green < 0 ? 0 : green > 1 ? 1 : green)));
    ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_2);
}

static float read_battery(void) {
    int sum = 0, mv, raw;
    for (int i = 0; i < 16; i++) {
        adc_oneshot_read(adc, ADC_CHANNEL_7, &raw);
        sum += raw;
    }
    if (cali && adc_cali_raw_to_voltage(cali, sum / 16, &mv) == ESP_OK) return 2.0f * mv / 1000.0f;
    return 2.0f * (sum / 16) * 3.1f / 4095.0f; /* uncalibrated fallback */
}

static void power_task(void *arg) {
    (void)arg;
    int low_count = 0;
    for (int64_t t0 = esp_timer_get_time();; vTaskDelay(pdMS_TO_TICKS(50))) {
        if (off) continue;
        float s = (esp_timer_get_time() - t0) / 1e6f;
        static float last_sample = -10;
        if (s - last_sample >= 2) { /* battery every 2 s, smoothed */
            last_sample = s;
            float v = read_battery();
            volts = volts > 0 ? volts * 0.7f + v * 0.3f : v;
            usb = gpio_get_level(PIN_USB);
            low_count = !usb && volts < CRITICAL_V ? low_count + 1 : 0;
            if (low_count >= 3) critical = true; /* three readings in a row, not a dip under load */
        }
        if (critical) led(fmodf(s, 0.25f) < 0.12f, 0);
        else if (game_led >= 0) led((game_led >> 16 & 255) / 255.0f, (game_led >> 8 & 255) / 255.0f);
        else if (usb && volts < FULL_V) { /* charging: orange breathing */
            float b = 0.5f - 0.5f * cosf(s * 6.2831853f / 2.5f);
            led(b, b * 0.45f);
        } else if (usb) led(0, 1);
        else if (volts < LOW_V) led(fmodf(s, 3) < 0.12f, DIM);
        else led(0, DIM);
    }
}

void power_init(void) {
    const ledc_timer_config_t timer = {
        .speed_mode = LEDC_LOW_SPEED_MODE, .duty_resolution = LEDC_TIMER_8_BIT, .timer_num = LEDC_TIMER_1,
        .freq_hz = 1000, .clk_cfg = LEDC_AUTO_CLK,
    };
    ESP_ERROR_CHECK(ledc_timer_config(&timer));
    const int pins[2] = {PIN_RED, PIN_GREEN};
    for (int i = 0; i < 2; i++) {
        const ledc_channel_config_t ch = {
            .gpio_num = pins[i], .speed_mode = LEDC_LOW_SPEED_MODE, .channel = (ledc_channel_t)(LEDC_CHANNEL_1 + i),
            .timer_sel = LEDC_TIMER_1, .duty = 0,
        };
        ESP_ERROR_CHECK(ledc_channel_config(&ch));
    }
    const gpio_config_t usb_pin = {.pin_bit_mask = 1ULL << PIN_USB, .mode = GPIO_MODE_INPUT,
                                   .pull_down_en = GPIO_PULLDOWN_ENABLE}; /* reads low with nothing wired */
    gpio_config(&usb_pin);

    const adc_oneshot_unit_init_cfg_t unit = {.unit_id = ADC_UNIT_1};
    ESP_ERROR_CHECK(adc_oneshot_new_unit(&unit, &adc));
    const adc_oneshot_chan_cfg_t chan = {.atten = ADC_ATTEN_DB_12, .bitwidth = ADC_BITWIDTH_DEFAULT};
    ESP_ERROR_CHECK(adc_oneshot_config_channel(adc, ADC_CHANNEL_7, &chan)); /* GPIO8 */
    const adc_cali_curve_fitting_config_t cc = {.unit_id = ADC_UNIT_1, .chan = ADC_CHANNEL_7,
                                                .atten = ADC_ATTEN_DB_12, .bitwidth = ADC_BITWIDTH_DEFAULT};
    if (adc_cali_create_scheme_curve_fitting(&cc, &cali) != ESP_OK) cali = NULL;

    for (int i = 0; i <= 12; i++) { /* power on: green rising over 0.6 s */
        led(0, i / 12.0f);
        vTaskDelay(pdMS_TO_TICKS(50));
    }
    volts = read_battery();
    usb = gpio_get_level(PIN_USB);
    hal_log("power: battery %.2f V, USB %s", volts, usb ? "yes" : "no");
    xTaskCreatePinnedToCore(power_task, "power", 2048, NULL, 2, NULL, 0); /* 0.9 KB used at most */
}

float power_volts(void) { return volts; }

void hal_led(int rgb) {
    game_led = rgb;
    if (rgb >= 0 && !critical && !off) led((rgb >> 16 & 255) / 255.0f, (rgb >> 8 & 255) / 255.0f); /* at once */
}

/* ponytail: a LiPo's voltage is not linear in its charge; 3.4 V empty to 4.15 V full is a guess good for a bar.
 * On USB the reading is the charger's output, so the level says little until it is unplugged. */
bool hal_battery(float *level, bool *charging) {
    float l = (volts - CRITICAL_V) / (FULL_V - CRITICAL_V);
    *level = l < 0 ? 0 : l > 1 ? 1 : l;
    *charging = usb && volts < FULL_V;
    return volts > 0;
}
bool power_usb(void) { return usb; }
bool power_critical(void) { return critical; }


void power_off(void) {
    hal_save_flush(); /* the game's last store() is still on its way to the flash */
    hal_log("power: off");
    off = true;
    audio_out_off();
    for (int i = 12; i >= 0; i--) { /* green fading */
        led(0, i / 12.0f);
        vTaskDelay(pdMS_TO_TICKS(50));
    }
    display_backlight(0);
    display_sleep();
    gpio_deep_sleep_hold_en(); /* backlight and amplifier pins keep their held levels while asleep */
    esp_sleep_enable_ext0_wakeup((gpio_num_t)PIN_BOOT, 0);
    esp_deep_sleep_start();
}
