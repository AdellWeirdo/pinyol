/* Firmware updates (docs/firmware-plan.md, OTA): two app slots, ota_0 and ota_1. The update is written to the slot
 * not running, and the bootloader tries it once: if it never finds its games (ota_mark_good), the next
 * restart goes back to the previous firmware. The card is the first source; Wi-Fi can feed the same slots later. */
#include "ota.h"

#include <stdio.h>

#include "bp.h"
#include "esp_app_desc.h"
#include "esp_ota_ops.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "launcher.h"

#ifndef BP_OTA_FILE
#define BP_OTA_FILE "/sdcard/firmware.bin"
#endif
#define CARD_FILE BP_OTA_FILE /* -DBP_OTA_TEST=<bin>: the same path from the flash image, to test with the card in */
#define CHUNK 4096

#define WORK_FILE CARD_FILE ".instalando"

static void finish(const char *suffix) { /* renamed, never deleted: what was on the card stays inspectable */
    char to[48];
    snprintf(to, sizeof to, "%s.%s", CARD_FILE, suffix);
    remove(to);
    rename(WORK_FILE, to);
}

void ota_from_card(uint16_t *frame) {
    const esp_partition_t *run = esp_ota_get_running_partition();
    hal_log("firmware %s in %s", esp_app_get_description()->version, run->label);
    FILE *f = fopen(CARD_FILE, "rb");
    if (!f) return;
    fclose(f);
    remove(WORK_FILE);
    if (rename(CARD_FILE, WORK_FILE) != 0) { /* claimed first: a card that cannot be written is never a boot loop */
        hal_log("ota: %s cannot be renamed (locked card?), not installed", CARD_FILE);
        launcher_message(frame, "La tarjeta está bloqueada", -1);
        vTaskDelay(pdMS_TO_TICKS(2000));
        return;
    }
    f = fopen(WORK_FILE, "rb");
    long size = -1;
    if (f && fseek(f, 0, SEEK_END) == 0) size = ftell(f), fseek(f, 0, SEEK_SET);
    const esp_partition_t *to = esp_ota_get_next_update_partition(NULL);
    esp_ota_handle_t h = 0;
    esp_err_t err = !f || !to ? ESP_ERR_NOT_FOUND
                    : size <= 0 || size > (long)to->size ? ESP_ERR_INVALID_SIZE
                                                         : esp_ota_begin(to, size, &h);
    static uint8_t buf[CHUNK];
    long done = 0;
    int shown = -1;
    while (err == ESP_OK && done < size) {
        size_t n = fread(buf, 1, CHUNK, f);
        if (n == 0) {
            err = ESP_FAIL;
            break;
        }
        err = esp_ota_write(h, buf, n);
        done += (long)n;
        int pc = (int)(done * 100 / size);
        if (pc / 5 != shown) launcher_message(frame, "Actualizando la consola", pc), shown = pc / 5;
    }
    if (f) fclose(f);
    if (h) err = err == ESP_OK ? esp_ota_end(h) : (esp_ota_abort(h), err); /* end validates the image */
    if (err == ESP_OK) err = esp_ota_set_boot_partition(to);
    finish(err == ESP_OK ? "instalado" : "fallido");
    if (err != ESP_OK) {
        hal_log("ota: %s not installed: %s", CARD_FILE, esp_err_to_name(err));
        launcher_message(frame, "La actualización no vale", -1);
        vTaskDelay(pdMS_TO_TICKS(2000)); /* long enough to read; the reason is in the log */
        return;
    }
    hal_log("ota: %ld bytes into %s, restarting", size, to->label);
    launcher_message(frame, "Actualizada. Reiniciando...", 100);
    esp_restart();
}

void ota_mark_good(void) {
#ifdef BP_OTA_NEVER_GOOD /* -DBP_OTA_NEVER_GOOD=ON: a firmware that never keeps itself, to watch the rollback */
    hal_log("ota: test build, never kept: the next restart goes back");
    return;
#endif
    esp_ota_img_states_t st;
    if (esp_ota_get_state_partition(esp_ota_get_running_partition(), &st) == ESP_OK && st == ESP_OTA_IMG_PENDING_VERIFY) {
        esp_ota_mark_app_valid_cancel_rollback();
        hal_log("ota: this firmware is kept");
    }
}
