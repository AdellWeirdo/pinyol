/* Sound out and in (docs/hardware.md). The engine's mixer (audio_mix, mono at AUDIO_HZ) feeds an I2S stream, 16-bit
 * stereo at 22050 Hz, into the ES8311 codec on the shared I2C bus (0x18), which clocks itself from BCLK: the
 * register sequence is the one proven on the sister 2.8" board (from Freenove's es8311.cpp). The
 * 8002 amplifier is switched on once (IO1 low) and left on until power-off, as it swallows its first ~100 ms.
 * The same stream runs both ways: the codec's ADC (the microphone, registers as Espressif's esp_codec_dev sets them)
 * comes back on DIN, block for block with what goes out; the mixer's task keeps it in a ring for hal_mic_read while
 * a game listens. */
#include "audio_out.h"

#include "bp.h"
#include "driver/gpio.h"
#include "driver/i2s_std.h"
#include "esp_heap_caps.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#define PIN_BCLK 18
#define PIN_WS 21
#define PIN_DOUT 15 /* ESP to codec (DSDIN) */
#define PIN_DIN 16  /* codec to ESP (ASDOUT): the microphone */
#define PIN_AMP 1   /* amplifier shutdown, active high: low plays */
#define ADDR_CODEC 0x18
#define BLOCK 256 /* samples per mix, 11.6 ms */
#define I2C_MS 10
/* ponytail: calibration knobs, measured on the board (docs/measurements.md): the microphone's analog gain, 0..7 =
 * 0..42 dB in 6 dB steps (REG16), and the PGA (REG14 low bits) */
#define MIC_GAIN 4
#define MIC_PGA 0x0A
#define MIC_RING 4096

static i2c_master_dev_handle_t codec;
static i2s_chan_handle_t tx, rx;
static int16_t *mic_ring; /* PSRAM, made the first time a game listens */
static volatile bool mic_on;
static volatile int mic_w, mic_r;
static portMUX_TYPE mic_lock = portMUX_INITIALIZER_UNLOCKED;
volatile int64_t audio_out_mix_us;
volatile int audio_out_blocks, audio_out_underruns;

static void w(uint8_t reg, uint8_t v) {
    uint8_t b[2] = {reg, v};
    i2c_master_transmit(codec, b, 2, I2C_MS);
}

static uint8_t r(uint8_t reg) {
    uint8_t v = 0;
    i2c_master_transmit_receive(codec, &reg, 1, &v, 1, I2C_MS);
    return v;
}

static bool codec_init(void) {
    uint8_t id1 = r(0xFD), id2 = r(0xFE);
    if (id1 != 0x83 || id2 != 0x11) {
        hal_log("audio: no ES8311 (id %02x %02x)", id1, id2);
        return false;
    }
    w(0x00, 0x1F); /* reset */
    vTaskDelay(pdMS_TO_TICKS(20));
    w(0x00, 0x00);
    w(0x00, 0x80);                                    /* power on */
    w(0x01, 0x3F | 0x80);                             /* clocks on, internal MCLK from BCLK */
    w(0x06, r(0x06) & ~0x20);                         /* BCLK not inverted */
    w(0x02, (r(0x02) & 0x07) | (0 << 5) | (3 << 3)); /* 705600 Hz BCLK x8 -> 256 fs at 22050 Hz */
    w(0x03, 0x10);
    w(0x04, 0x10);
    w(0x05, 0x00);
    w(0x06, (r(0x06) & 0xE0) | (4 - 1));
    w(0x07, r(0x07) & 0xC0);
    w(0x08, 0xFF);
    w(0x00, r(0x00) & 0xBF); /* I2S slave */
    w(0x09, 0x0C);           /* 16-bit in */
    w(0x0A, 0x0C);           /* 16-bit out */
    w(0x0D, 0x01);
    w(0x0E, 0x02);
    w(0x12, 0x00);
    w(0x13, 0x10);
    w(0x1C, 0x6A);
    w(0x37, 0x08);
    w(0x32, 0xBF); /* DAC volume 0 dB: above it the codec adds gain and clips */
    w(0x14, 0x10 | MIC_PGA); /* ADC input: the analog microphone on MIC1P/MIC1N, through the PGA */
    w(0x15, 0x40);           /* ADC soft ramp */
    w(0x16, MIC_GAIN);
    w(0x17, 0xBF);           /* ADC volume 0 dB */
    w(0x1B, 0x0A);           /* ADC high-pass: no DC from the microphone */
    w(0x44, 0x08);           /* both ADC slots carry the microphone (no DAC loopback) */
    return true;
}

static bool IRAM_ATTR on_underrun(i2s_chan_handle_t h, i2s_event_data_t *e, void *ctx) {
    (void)h, (void)e, (void)ctx;
    audio_out_underruns++;
    return false;
}

static void mix_task(void *arg) {
    (void)arg;
    static int16_t mono[BLOCK], stereo[2 * BLOCK];
    for (;;) {
        int64_t t = esp_timer_get_time();
        hal_audio_lock();
        audio_mix(mono, BLOCK);
        hal_audio_unlock();
        audio_out_mix_us += esp_timer_get_time() - t;
        audio_out_blocks++;
        for (int i = 0; i < BLOCK; i++) stereo[2 * i] = stereo[2 * i + 1] = mono[i];
        size_t sent;
        i2s_channel_write(tx, stereo, sizeof stereo, &sent, portMAX_DELAY); /* blocks: this paces the mixer */
        for (int k = 0; k < 3; k++) { /* what came in meanwhile, as one block goes out one comes in */
            size_t got = 0;
            i2s_channel_read(rx, stereo, sizeof stereo, &got, 0); /* (drained even unheard: no stale backlog) */
            if (!got) break;
            if (!mic_on) continue;
            portENTER_CRITICAL(&mic_lock);
            for (size_t i = 0; i < got / 4; i++) {
                mic_ring[mic_w] = stereo[2 * i];
                mic_w = (mic_w + 1) % MIC_RING;
                if (mic_w == mic_r) mic_r = (mic_r + 1) % MIC_RING; /* full: the oldest goes */
            }
            portEXIT_CRITICAL(&mic_lock);
        }
    }
}

bool audio_out_init(i2c_master_bus_handle_t bus) {
    const i2c_device_config_t dev = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7, .device_address = ADDR_CODEC, .scl_speed_hz = 400000,
    };
    if (i2c_master_bus_add_device(bus, &dev, &codec) != ESP_OK || !codec_init()) return false;

    i2s_chan_config_t chan = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_0, I2S_ROLE_MASTER);
    chan.dma_desc_num = 6; /* 6 x 256 frames: 70 ms of sound queued */
    chan.dma_frame_num = BLOCK;
    chan.auto_clear = true; /* silence, not a stutter, if the mixer is ever late */
    ESP_ERROR_CHECK(i2s_new_channel(&chan, &tx, &rx)); /* full duplex: one clock both ways */
    const i2s_std_config_t std = {
        .clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(AUDIO_HZ),
        .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_STEREO),
        .gpio_cfg = {.mclk = I2S_GPIO_UNUSED, .bclk = PIN_BCLK, .ws = PIN_WS, .dout = PIN_DOUT, .din = PIN_DIN},
    };
    ESP_ERROR_CHECK(i2s_channel_init_std_mode(tx, &std));
    ESP_ERROR_CHECK(i2s_channel_init_std_mode(rx, &std));
    const i2s_event_callbacks_t cbs = {.on_send_q_ovf = on_underrun};
    i2s_channel_register_event_callback(tx, &cbs, NULL);
    ESP_ERROR_CHECK(i2s_channel_enable(tx));
    ESP_ERROR_CHECK(i2s_channel_enable(rx));

    gpio_set_direction(PIN_AMP, GPIO_MODE_OUTPUT);
#ifdef BP_QUIET
    gpio_set_level(PIN_AMP, 1); /* test build: everything mixed and sent, the amplifier stays off */
#else
    gpio_set_level(PIN_AMP, 0); /* amplifier on, until audio_out_off */
#endif
    gpio_hold_dis(PIN_AMP);     /* held off through deep sleep */
    vTaskDelay(pdMS_TO_TICKS(100));
    xTaskCreatePinnedToCore(mix_task, "audio", 6144, NULL, 6, NULL, 1);
#ifdef BP_QUIET
    hal_log("audio: ES8311 at %d Hz, amplifier off (test build)", AUDIO_HZ);
#else
    hal_log("audio: ES8311 at %d Hz, amplifier on", AUDIO_HZ);
#endif
    return true;
}

void audio_out_off(void) {
    hal_audio_lock(); /* never given back: the mixer stops and the DMA plays its cleared buffers, silence */
    vTaskDelay(pdMS_TO_TICKS(100)); /* the 70 ms already queued */
    gpio_set_direction(PIN_AMP, GPIO_MODE_OUTPUT);
    gpio_set_level(PIN_AMP, 1); /* amplifier shut down on silence: no pop */
    gpio_hold_en(PIN_AMP);
}

bool hal_mic_open(void) {
    if (!rx) return false;
    if (!mic_ring && !(mic_ring = heap_caps_malloc(MIC_RING * sizeof(int16_t), MALLOC_CAP_SPIRAM))) return false;
    portENTER_CRITICAL(&mic_lock);
    mic_w = mic_r = 0;
    mic_on = true;
    portEXIT_CRITICAL(&mic_lock);
    return true;
}

void hal_mic_close(void) { mic_on = false; }

int hal_mic_read(int16_t *p, int max) {
    int n = 0;
    portENTER_CRITICAL(&mic_lock);
    while (mic_on && n < max && mic_r != mic_w) p[n++] = mic_ring[mic_r], mic_r = (mic_r + 1) % MIC_RING;
    portEXIT_CRITICAL(&mic_lock);
    return n;
}
