/* The link between consoles (src/link.c) over ESP-NOW: packets straight from one console's radio to the others in
 * range, no router, no network. The radio is on only while a game uses link (hal_link_open on its first call,
 * hal_link_close when it ends); its buffers are in PSRAM and none of its code takes IRAM (sdkconfig.defaults), so
 * the games that do not use it lose nothing. */
#include <string.h>

#include "esp_event.h"
#include "esp_heap_caps.h"
#include "esp_mac.h"
#include "esp_now.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "hal.h"

#define CHANNEL 1 /* every console on the same one */
#define INBOX 16  /* packets waiting for the game's next tick; more and they are dropped, as the air would */

typedef struct {
    uint8_t len;
    uint8_t data[HAL_LINK_MAX];
} packet;

static const uint8_t EVERYONE[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
static QueueHandle_t inbox;
static bool up;
static uint32_t id;

static void received(const esp_now_recv_info_t *info, const uint8_t *data, int len) { /* the radio's task */
    (void)info;
    if (len <= 0 || len > HAL_LINK_MAX) return;
    packet p = {.len = (uint8_t)len};
    memcpy(p.data, data, (size_t)len);
    xQueueSend(inbox, &p, 0);
}

uint32_t hal_link_id(void) {
    if (!id) { /* from the radio's own address: the same every time this console starts */
        uint8_t mac[6] = {0};
        esp_read_mac(mac, ESP_MAC_WIFI_STA);
        id = (uint32_t)mac[2] << 24 | (uint32_t)mac[3] << 16 | (uint32_t)mac[4] << 8 | mac[5];
        if (!id) id = 1;
    }
    return id;
}

bool hal_link_open(void) {
    if (up) return true;
    size_t before = heap_caps_get_free_size(MALLOC_CAP_INTERNAL);
    if (!inbox && !(inbox = xQueueCreateWithCaps(INBOX, sizeof(packet), MALLOC_CAP_SPIRAM))) return false; /* 4 KB, not internal */
    esp_err_t e = esp_event_loop_create_default(); /* the radio's driver reports to it */
    if (e != ESP_OK && e != ESP_ERR_INVALID_STATE) return false;
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    if (esp_wifi_init(&cfg) != ESP_OK) {
        hal_log("link: the radio did not start");
        return false;
    }
    esp_now_peer_info_t all = {.channel = CHANNEL, .ifidx = WIFI_IF_STA, .encrypt = false};
    memcpy(all.peer_addr, EVERYONE, 6);
    if (esp_wifi_set_storage(WIFI_STORAGE_RAM) != ESP_OK || esp_wifi_set_mode(WIFI_MODE_STA) != ESP_OK ||
        esp_wifi_start() != ESP_OK || esp_wifi_set_channel(CHANNEL, WIFI_SECOND_CHAN_NONE) != ESP_OK ||
        esp_now_init() != ESP_OK || esp_now_register_recv_cb(received) != ESP_OK || esp_now_add_peer(&all) != ESP_OK) {
        hal_log("link: ESP-NOW did not start");
        esp_now_deinit();
        esp_wifi_stop();
        esp_wifi_deinit();
        return false;
    }
    up = true;
    hal_log("link: ESP-NOW on, channel %d, console %08x; internal RAM %u KB -> %u KB", CHANNEL, (unsigned)hal_link_id(),
            (unsigned)(before / 1024), (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024));
    return true;
}

void hal_link_close(void) {
    if (!up) return;
    esp_now_deinit();
    esp_wifi_stop();
    esp_wifi_deinit();
    esp_event_loop_delete_default(); /* its task and stack back to the games */
    xQueueReset(inbox);
    up = false;
    hal_log("link: off; internal RAM %u KB", (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024));
}

bool hal_link_send(const uint8_t *p, int n) { return up && esp_now_send(EVERYONE, p, (size_t)n) == ESP_OK; }

int hal_link_recv(uint8_t *p, int max) {
    packet k;
    if (!up || xQueueReceive(inbox, &k, 0) != pdTRUE) return 0;
    int n = k.len < max ? k.len : max;
    memcpy(p, k.data, (size_t)n);
    return n;
}
