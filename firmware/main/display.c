/* ST77922 over QSPI. The panel is 320x480 portrait and cannot swap rows and columns (MADCTL has no MV), so
 * the 480x320 frame is turned in software: 32 frame columns at a time become 32 panel rows in internal RAM,
 * with the byte swap the bus wants, and each strip goes out by DMA while the next one is built.
 * INIT is the panel's register settings as the module's maker publishes them (LCDwiki's ST77922 example,
 * github.com/ydedox/st77922, the same table Freenove's driver carries): the values this glass needs to light up.
 * The QSPI command format is the ST77922 interface protocol's. */
#include "display.h"

#include <string.h>

#include "driver/gpio.h"
#include "driver/ledc.h"
#include "driver/spi_master.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#define PIN_CS 10 /* SPI2 IOMUX pins: 80 MHz is possible */
#define PIN_SCK 12
#define PIN_D0 11
#define PIN_D1 13
#define PIN_D2 14
#define PIN_D3 9
#define PIN_BL 41
#define PIN_TE 42
#define SCAN_START_US 3000 /* this close after the TE pulse the strips (8 ms) still outrun the scan (16 ms) */
#define FRAME_W 480
#define FRAME_H 320
#define PANEL_W 320
#define PANEL_H 480
#define STRIP 32 /* panel rows (frame columns) per transfer: 20 KB */

static spi_device_handle_t dev;
static SemaphoreHandle_t te_pulse;
static volatile int64_t te_last; /* when the panel last started a scan */
static void te_init(void);
static uint16_t *strip_buf[2];
static bool flipped;

static const struct {
    uint8_t cmd, len;
    uint8_t data[16];
    uint16_t delay_ms;
} INIT[] = {
    {0xF1, 1, {0x00}, 0},
    {0x60, 3, {0x00, 0x00, 0x00}, 0},
    {0x65, 1, {0x80}, 0},
    {0x79, 1, {0x06}, 0},
    {0x7B, 3, {0x00, 0x08, 0x08}, 0},
    {0x80, 11, {0x55, 0x62, 0x2F, 0x17, 0xF0, 0x52, 0x70, 0xD2, 0x52, 0x62, 0xEA}, 0},
    {0x81, 4, {0x26, 0x52, 0x72, 0x27}, 0},
    {0x84, 2, {0x92, 0x25}, 0},
    {0x87, 6, {0x10, 0x10, 0x58, 0x00, 0x02, 0x3A}, 0},
    {0x88, 15, {0x00, 0x00, 0x2C, 0x10, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x06}, 0},
    {0x89, 3, {0x00, 0x00, 0x00}, 0},
    {0x8A, 11, {0x13, 0x00, 0x2C, 0x00, 0x00, 0x2C, 0x10, 0x10, 0x00, 0x3E, 0x19}, 0},
    {0x8B, 9, {0x15, 0xB1, 0xB1, 0x44, 0x96, 0x2C, 0x10, 0x97, 0x8E}, 0},
    {0x8C, 13, {0x1D, 0xB1, 0xB1, 0x44, 0x96, 0x2C, 0x10, 0x50, 0x0F, 0x01, 0xC5, 0x12, 0x09}, 0},
    {0x8D, 1, {0x0C}, 0},
    {0x8E, 6, {0x33, 0x01, 0x0C, 0x13, 0x01, 0x01}, 0},
    {0xB3, 2, {0x00, 0x30}, 0},
    {0xF1, 1, {0x00}, 0},
    {0x71, 1, {0xD0}, 0},
    {0x66, 2, {0x02, 0x3F}, 0},
    {0xBE, 3, {0x26, 0x00, 0x9D}, 0},
    {0x70, 12, {0x01, 0xA0, 0x11, 0x40, 0xE0, 0x00, 0x11, 0x69, 0x11, 0x00, 0x00, 0x1A}, 0},
    {0x90, 9, {0x04, 0x04, 0x55, 0x74, 0x00, 0x40, 0x43, 0x27, 0x27}, 0},
    {0x91, 9, {0x04, 0x04, 0x55, 0x75, 0x00, 0x40, 0x42, 0x27, 0x27}, 0},
    {0x92, 10, {0x04, 0x44, 0x55, 0xC0, 0x06, 0x00, 0x07, 0x05, 0x90, 0x27}, 0},
    {0x93, 10, {0x04, 0x43, 0x11, 0x00, 0x00, 0x00, 0x00, 0x05, 0x90, 0x27}, 0},
    {0x94, 6, {0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, 0},
    {0x95, 5, {0x96, 0x16, 0x00, 0x00, 0xFF}, 0},
    {0x96, 12, {0x44, 0x53, 0x03, 0x12, 0x23, 0x24, 0x06, 0x05, 0x94, 0x27, 0x00, 0x44}, 0},
    {0x97, 12, {0x44, 0x53, 0x47, 0x56, 0x20, 0x20, 0x02, 0x01, 0x94, 0x27, 0x00, 0x44}, 0},
    {0xBA, 5, {0x55, 0x94, 0x2D, 0x94, 0x27}, 0},
    {0x9A, 7, {0x40, 0x00, 0x06, 0x00, 0x00, 0x00, 0x00}, 0},
    {0x9B, 7, {0x00, 0x00, 0x06, 0x00, 0x00, 0x00, 0x00}, 0},
    {0x9C, 13, {0x5C, 0x12, 0x00, 0x00, 0x10, 0x12, 0x00, 0x00, 0x10, 0x02, 0x00, 0x00, 0x00}, 0},
    {0x9D, 8, {0x8A, 0x51, 0x00, 0x00, 0x00, 0x80, 0x1E, 0x01}, 0},
    {0x9E, 7, {0x51, 0x00, 0x00, 0x00, 0x80, 0x1E, 0x01}, 0},
    {0xB4, 12, {0x1D, 0x1C, 0x1E, 0x0B, 0x14, 0x02, 0x13, 0x09, 0x1E, 0x00, 0x1E, 0x10}, 0},
    {0xB5, 12, {0x1D, 0x1C, 0x1E, 0x0A, 0x15, 0x03, 0x11, 0x08, 0x1E, 0x01, 0x1E, 0x12}, 0},
    {0xB6, 7, {0x77, 0x77, 0x00, 0x0A, 0xFF, 0x0A, 0xFF}, 0},
    {0x86, 14, {0xCD, 0x04, 0xB1, 0x02, 0x58, 0x12, 0x58, 0x0C, 0x13, 0x01, 0xA5, 0x00, 0xA5, 0xA5}, 0},
    {0xB7, 16, {0x07, 0x0A, 0x0E, 0x06, 0x05, 0x03, 0x2B, 0x03, 0x03, 0x42, 0x07, 0x10, 0x10, 0x2E, 0x3F, 0x0D}, 0},
    {0xB8, 16, {0x07, 0x0A, 0x0D, 0x05, 0x05, 0x02, 0x2B, 0x02, 0x03, 0x42, 0x06, 0x10, 0x0F, 0x2E, 0x3F, 0x0D}, 0},
    {0xB9, 2, {0x23, 0x23}, 0},
    {0xBF, 6, {0x10, 0x14, 0x14, 0x0B, 0x0B, 0x0B}, 0},
    {0xF2, 1, {0x00}, 0},
    {0x73, 5, {0x04, 0xDA, 0x12, 0x54, 0x47}, 0},
    {0x77, 5, {0x6B, 0x5B, 0xFD, 0xC3, 0xC5}, 0},
    {0x7A, 2, {0x15, 0x27}, 0},
    {0x7B, 2, {0x04, 0x57}, 0},
    {0x7E, 2, {0x01, 0x0E}, 0},
    {0xBF, 1, {0x36}, 0},
    {0xE3, 2, {0x40, 0x40}, 0},
    {0xF0, 1, {0x00}, 0},
    {0xD0, 1, {0x00}, 0},
    {0x2A, 4, {0x00, 0x00, 0x01, 0x3F}, 0}, /* columns 0..319 */
    {0x2B, 4, {0x00, 0x00, 0x01, 0xDF}, 0}, /* rows 0..479 */
    {0x21, 0, {0}, 0},                      /* inversion on (this IPS panel) */
    {0x11, 0, {0}, 120},                    /* sleep out */
    {0x29, 0, {0}, 0},                      /* display on */
    {0x3A, 1, {0x01}, 0},                   /* RGB565 */
    {0x36, 1, {0x00}, 0},                   /* portrait, as the panel is */
    {0x35, 1, {0x00}, 20},                  /* tearing-effect output on: one pulse per frame (display_wait_scan) */
};

static void write_reg(uint8_t cmd, const uint8_t *data, int len) {
    spi_transaction_ext_t t = {0};
    t.base.flags = SPI_TRANS_VARIABLE_CMD | SPI_TRANS_VARIABLE_ADDR;
    t.base.cmd = 0x02; /* register write, one line */
    t.base.addr = (uint32_t)cmd << 8;
    t.command_bits = 8;
    t.address_bits = 24;
    t.base.tx_buffer = len ? data : NULL;
    t.base.length = 8 * len;
    ESP_ERROR_CHECK(spi_device_polling_transmit(dev, &t.base));
}

void display_backlight(int percent) {
    percent = percent < 0 ? 0 : percent > 100 ? 100 : percent;
    ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_0, (uint32_t)(255 * percent / 100));
    ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_0);
}

void display_init(int spi_hz, bool flip) {
    flipped = flip;
    const spi_bus_config_t bus = {
        .data0_io_num = PIN_D0, .data1_io_num = PIN_D1, .data2_io_num = PIN_D2, .data3_io_num = PIN_D3,
        .sclk_io_num = PIN_SCK, .max_transfer_sz = STRIP * PANEL_W * 2,
        .flags = SPICOMMON_BUSFLAG_MASTER | SPICOMMON_BUSFLAG_IOMUX_PINS | SPICOMMON_BUSFLAG_QUAD,
    };
    ESP_ERROR_CHECK(spi_bus_initialize(SPI2_HOST, &bus, SPI_DMA_CH_AUTO));
    const spi_device_interface_config_t cfg = {
        .mode = 0, .clock_speed_hz = spi_hz, .spics_io_num = PIN_CS, .flags = SPI_DEVICE_HALFDUPLEX, .queue_size = 2,
    };
    ESP_ERROR_CHECK(spi_bus_add_device(SPI2_HOST, &cfg, &dev));

    const ledc_timer_config_t timer = {
        .speed_mode = LEDC_LOW_SPEED_MODE, .duty_resolution = LEDC_TIMER_8_BIT, .timer_num = LEDC_TIMER_0,
        .freq_hz = 20000, .clk_cfg = LEDC_AUTO_CLK,
    };
    ESP_ERROR_CHECK(ledc_timer_config(&timer));
    const ledc_channel_config_t ch = {
        .gpio_num = PIN_BL, .speed_mode = LEDC_LOW_SPEED_MODE, .channel = LEDC_CHANNEL_0,
        .timer_sel = LEDC_TIMER_0, .duty = 0,
    };
    ESP_ERROR_CHECK(ledc_channel_config(&ch)); /* dark until the first frame is up */
    gpio_hold_dis(PIN_BL);                     /* held low through deep sleep (display_sleep) */

    for (size_t i = 0; i < sizeof INIT / sizeof INIT[0]; i++) {
        write_reg(INIT[i].cmd, INIT[i].data, INIT[i].len);
        if (INIT[i].delay_ms) vTaskDelay(pdMS_TO_TICKS(INIT[i].delay_ms));
    }
    for (int i = 0; i < 2; i++) {
        strip_buf[i] = heap_caps_malloc(STRIP * PANEL_W * 2, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
        assert(strip_buf[i]);
    }
    te_init();
}

static void IRAM_ATTR te_isr(void *arg) {
    (void)arg;
    te_last = esp_timer_get_time();
    BaseType_t woken = pdFALSE;
    xSemaphoreGiveFromISR(te_pulse, &woken);
    if (woken) portYIELD_FROM_ISR();
}

static void te_init(void) {
    te_pulse = xSemaphoreCreateBinary();
    const gpio_config_t io = {.pin_bit_mask = 1ULL << PIN_TE, .mode = GPIO_MODE_INPUT, .intr_type = GPIO_INTR_POSEDGE};
    esp_err_t e = gpio_config(&io);
    if (e == ESP_OK) e = gpio_install_isr_service(0);
    if (e == ESP_OK || e == ESP_ERR_INVALID_STATE) e = gpio_isr_handler_add(PIN_TE, te_isr, NULL);
    if (e != ESP_OK) {
        vSemaphoreDelete(te_pulse);
        te_pulse = NULL; /* frames go out unsynchronised */
    }
}

void display_wait_scan(void) {
    if (!te_pulse || esp_timer_get_time() - te_last < SCAN_START_US) return;
    xSemaphoreTake(te_pulse, 0);                    /* a pulse from an earlier scan */
    xSemaphoreTake(te_pulse, pdMS_TO_TICKS(20));    /* the next one; no pulse in 20 ms: send anyway */
}

/* Panel rows p0..p0+STRIP-1 from the frame. Panel pixel (px, py) shows frame pixel (lx, ly) with
 * lx = py, ly = 319 - px; flipped turns it 180 degrees. Frame rows are read contiguously. */
static void build_strip(int p0, uint16_t *out, void *ctx) {
    const uint16_t *frame = ctx;
    for (int ly = 0; ly < FRAME_H; ly++) {
        const uint16_t *row = frame + ly * FRAME_W;
        int px = flipped ? ly : PANEL_W - 1 - ly;
        for (int k = 0; k < STRIP; k++) {
            uint16_t v = row[flipped ? FRAME_W - 1 - p0 - k : p0 + k];
            out[k * PANEL_W + px] = (uint16_t)(v >> 8 | v << 8); /* the bus sends the high byte first */
        }
    }
}

void display_present_strips(display_strip_fn build, void *ctx) {
    static spi_transaction_ext_t t[2];
    int inflight = 0;
    for (int s = 0; s < PANEL_H / STRIP; s++) {
        spi_transaction_t *done;
        if (inflight == 2) { /* the buffer about to be reused is the oldest in flight */
            ESP_ERROR_CHECK(spi_device_get_trans_result(dev, &done, portMAX_DELAY));
            inflight--;
        }
        uint16_t *buf = strip_buf[s & 1];
        build(s * STRIP, buf, ctx);
        spi_transaction_ext_t *x = &t[s & 1];
        memset(x, 0, sizeof *x);
        x->base.flags = SPI_TRANS_MODE_QIO | SPI_TRANS_VARIABLE_CMD | SPI_TRANS_VARIABLE_ADDR;
        x->base.cmd = 0x32; /* pixels on four lines */
        x->base.addr = (uint32_t)(s == 0 ? 0x2C : 0x3C) << 8; /* memory write, then continue */
        x->command_bits = 8;
        x->address_bits = 24;
        x->base.tx_buffer = buf;
        x->base.length = STRIP * PANEL_W * 16;
        ESP_ERROR_CHECK(spi_device_queue_trans(dev, &x->base, portMAX_DELAY));
        inflight++;
    }
    while (inflight--) {
        spi_transaction_t *done;
        ESP_ERROR_CHECK(spi_device_get_trans_result(dev, &done, portMAX_DELAY));
    }
}

void display_present(const uint16_t *frame) { display_present_strips(build_strip, (void *)frame); }

void display_te_vblank_only(bool vblank_only) { write_reg(0x35, (const uint8_t[]){vblank_only ? 0x00 : 0x01}, 1); }

int display_spi_khz(void) {
    int khz = 0;
    spi_device_get_actual_freq(dev, &khz);
    return khz;
}

volatile int64_t display_present_us;
static QueueHandle_t pending;
static SemaphoreHandle_t idle;

static void present_task(void *arg) {
    (void)arg;
    for (;;) {
        const uint16_t *frame;
        xQueueReceive(pending, &frame, portMAX_DELAY);
        int64_t t = esp_timer_get_time();
        display_present(frame);
        display_present_us += esp_timer_get_time() - t;
        xSemaphoreGive(idle);
    }
}

void display_start_task(void) {
    pending = xQueueCreate(1, sizeof(const uint16_t *));
    idle = xSemaphoreCreateBinary();
    xSemaphoreGive(idle);
    xTaskCreatePinnedToCore(present_task, "display", 4096, NULL, 5, NULL, 1);
}

bool display_flipped(void) { return flipped; }

void display_wait(void) {
    if (!idle) return;
    xSemaphoreTake(idle, portMAX_DELAY); /* the frame the task was sending is out */
    xSemaphoreGive(idle);
}

static const uint16_t *last;

const uint16_t *display_last(void) { return last; }

void display_submit(const uint16_t *frame) {
    xSemaphoreTake(idle, portMAX_DELAY); /* the previous frame is on the panel: its buffer is free again */
    last = frame;
    xQueueSend(pending, &frame, portMAX_DELAY);
}

void display_sleep(void) {
    if (idle) xSemaphoreTake(idle, portMAX_DELAY); /* let the frame in flight finish; nothing is drawn after this */
    write_reg(0x28, NULL, 0);                      /* display off */
    write_reg(0x10, NULL, 0);                      /* sleep in */
    gpio_hold_en(PIN_BL); /* the backlight stays dark while the chip sleeps (with gpio_deep_sleep_hold_en) */
}
