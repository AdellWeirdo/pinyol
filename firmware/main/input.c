/* Buttons and touch (docs/hardware.md). One I2C bus (SDA 38, SCL 39) carries the console's PCF8574 (0x20:
 * P0-P3 the d-pad up/down/left/right, P4-P7 A, B, MENU, START, all to ground), the panel's touch (0x55) and
 * the codec (0x18). C is on IO44. On a bare board without the PCF8574, BOOT (IO0) stands in for A. */
#include "input.h"
#include "cable.h"
#include "remote.h"

#include "driver/gpio.h"
#include "driver/i2c_master.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#define PIN_SDA 38
#define PIN_SCL 39
#define PIN_C 44
#define PIN_BOOT 0
#define PIN_TOUCH_RST 48
#define ADDR_PCF 0x20
#define ADDR_TOUCH 0x55
#define ADDR_CODEC 0x18
#define I2C_MS 5

static i2c_master_bus_handle_t bus;
static i2c_master_dev_handle_t pcf, touch;
static int touch_points;
static hal_input last_touch;

static const uint16_t PCF_BITS[8] = {ACT_UP, ACT_DOWN, ACT_LEFT, ACT_RIGHT, ACT_OK, ACT_BACK, ACT_INV, ACT_PAUSE};

i2c_master_bus_handle_t input_bus(void) { return bus; }

static bool touch_read(uint16_t reg, uint8_t *buf, size_t n) {
    uint8_t r[2] = {reg >> 8, reg & 0xFF};
    return i2c_master_transmit_receive(touch, r, 2, buf, n, I2C_MS) == ESP_OK;
}

static void touch_reset(void) { /* the controller only answers after a reset pulse (Freenove does the same) */
    gpio_set_direction(PIN_TOUCH_RST, GPIO_MODE_OUTPUT);
    gpio_set_level(PIN_TOUCH_RST, 0);
    vTaskDelay(pdMS_TO_TICKS(100));
    gpio_set_level(PIN_TOUCH_RST, 1);
    vTaskDelay(pdMS_TO_TICKS(100));
}

static void touch_init(void) {
    uint8_t v = 0xFF;
    for (int i = 0; i < 50 && touch_read(0x0001, &v, 1) && (v & 0x0F); i++) vTaskDelay(pdMS_TO_TICKS(10)); /* busy */
    if (touch_read(0x0009, &v, 1) && v > 0 && v <= 10) touch_points = v;
}

void input_init(void) {
    const i2c_master_bus_config_t cfg = {
        .i2c_port = 0, .sda_io_num = PIN_SDA, .scl_io_num = PIN_SCL, .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7, .flags.enable_internal_pullup = false, /* 10k on the board */
    };
    ESP_ERROR_CHECK(i2c_new_master_bus(&cfg, &bus));
    touch_reset();
    bool has_pcf = i2c_master_probe(bus, ADDR_PCF, 20) == ESP_OK;
    bool has_touch = i2c_master_probe(bus, ADDR_TOUCH, 20) == ESP_OK;
    bool has_codec = i2c_master_probe(bus, ADDR_CODEC, 20) == ESP_OK;
    hal_log("i2c: buttons PCF8574 %s, touch %s, codec %s", has_pcf ? "yes" : "no", has_touch ? "yes" : "no",
            has_codec ? "yes" : "no");
    const i2c_device_config_t dev = {.dev_addr_length = I2C_ADDR_BIT_LEN_7, .scl_speed_hz = 400000};
    if (has_pcf) {
        i2c_device_config_t d = dev;
        d.device_address = ADDR_PCF;
        ESP_ERROR_CHECK(i2c_master_bus_add_device(bus, &d, &pcf));
        uint8_t all_in = 0xFF; /* quasi-bidirectional pins: written high, they read the buttons */
        i2c_master_transmit(pcf, &all_in, 1, I2C_MS);
    }
    if (has_touch) {
        i2c_device_config_t d = dev;
        d.device_address = ADDR_TOUCH;
        ESP_ERROR_CHECK(i2c_master_bus_add_device(bus, &d, &touch));
        touch_init();
        hal_log("touch: %d points", touch_points);
    }
    const gpio_config_t keys = {
        .pin_bit_mask = (1ULL << PIN_C) | (has_pcf ? 0 : 1ULL << PIN_BOOT), .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    gpio_config(&keys);
}

/* Panel touch is portrait (x 0..319, y 0..479); the frame is landscape: frame x = panel y,
 * frame y = 319 - panel x (as display.c turns the picture). */
static void poll_touch(hal_input *in) {
    uint8_t info = 0, p[7 * 10]; /* up to 10 points of 7 bytes */
    if (touch && touch_points && !touch_read(0x0010, &info, 1)) {
        static bool warned;
        if (!warned) hal_log("touch: no answer from the controller"), warned = true;
    } else if (info & 0x08) { /* a new report, about every 16 ms while touched; on release one with no valid point */
        last_touch.touch = false;
        /* all points: read only the first and the controller keeps that report latched, a finger that never lifts */
        if (touch_read(0x0014, p, 7 * touch_points)) {
            last_touch.points = 0;
            for (int k = 0; k < touch_points && last_touch.points < HAL_POINTS; k++) { /* each point as the first is laid out */
                const uint8_t *q = p + 7 * k; /* each point laid out as the first (tried on the board: 4 fingers at once) */
                if (!(q[0] & 0x80)) continue;
                int tx = (q[0] & 0x3F) << 8 | q[1], ty = (q[2] & 0x3F) << 8 | q[3];
                last_touch.x[last_touch.points] = (int16_t)ty, last_touch.y[last_touch.points] = (int16_t)(319 - tx);
                last_touch.points++;
            }
            if (last_touch.points)
                last_touch.touch = true, last_touch.px = last_touch.x[0], last_touch.py = last_touch.y[0];
        }
    }
    in->touch = last_touch.touch;
    in->px = last_touch.px;
    in->py = last_touch.py;
    in->points = last_touch.touch ? last_touch.points : 0;
    for (int i = 0; i < in->points; i++) in->x[i] = last_touch.x[i], in->y[i] = last_touch.y[i];
}

hal_input input_poll(void) {
    hal_input in = {0};
    if (pcf) {
        uint8_t v = 0xFF;
        if (i2c_master_receive(pcf, &v, 1, I2C_MS) == ESP_OK)
            for (int i = 0; i < 8; i++)
                if (!(v & (1 << i))) in.held |= PCF_BITS[i];
    } else if (!gpio_get_level(PIN_BOOT)) {
        in.held |= ACT_OK;
    }
    if (!gpio_get_level(PIN_C)) in.held |= ACT_NEXT;
    poll_touch(&in);
    cable_poll(&in); /* a game sent over the cable; in test builds, remote.c's taps and keys */
    return in;
}
