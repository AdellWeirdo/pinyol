/* Game storage: the microSD over SDMMC, 4 lines (docs/hardware.md), or the "game" partition in flash. */
#include "sd.h"

#include <string.h>

#include "diskio_impl.h"
#include "diskio_sdmmc.h"
#include "driver/sdmmc_host.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_memory_utils.h"
#include "esp_vfs_fat.h"
#include "sdmmc_cmd.h"

static const char *TAG = "storage";

/* FatFs reads from the card. The SDMMC DMA cannot reach PSRAM, where the engine's buffers live, and the IDF driver
 * then reads one 512-byte sector per command: 1.6 MB/s, measured. Here such a read goes through a 16 KB internal
 * buffer, 32 sectors a command (~9 MB/s), so loads are shorter and the mixer's streams wait less for the card. FatFs
 * holds the volume's lock while it calls this, so one buffer serves. The rest is the IDF's own driver. */
#define BOUNCE_SECTORS 32
DSTATUS ff_sdmmc_initialize(BYTE pdrv);
DSTATUS ff_sdmmc_status(BYTE pdrv);
DRESULT ff_sdmmc_write(BYTE pdrv, const BYTE *buff, DWORD sector, UINT count);
DRESULT ff_sdmmc_ioctl(BYTE pdrv, BYTE cmd, void *buff);

static sdmmc_card_t *card;
static uint8_t *bounce;

static DRESULT fast_read(BYTE pdrv, BYTE *buff, uint32_t sector, unsigned count) {
    (void)pdrv;
    if (!bounce || (esp_ptr_dma_capable(buff) && !esp_ptr_external_ram(buff) && !((uintptr_t)buff & 3)))
        return sdmmc_read_sectors(card, buff, sector, count) == ESP_OK ? RES_OK : RES_ERROR;
    for (unsigned n; count; count -= n, sector += n, buff += n * 512) {
        n = count < BOUNCE_SECTORS ? count : BOUNCE_SECTORS;
        if (sdmmc_read_sectors(card, bounce, sector, n) != ESP_OK) return RES_ERROR;
        memcpy(buff, bounce, n * 512);
    }
    return RES_OK;
}

static bool sd_mount(void) {
    sdmmc_host_t host = SDMMC_HOST_DEFAULT();
    host.max_freq_khz = SDMMC_FREQ_HIGHSPEED; /* 40 MHz; the lines have 10k pull-ups on the board */
    sdmmc_slot_config_t slot = SDMMC_SLOT_CONFIG_DEFAULT();
    slot.width = 4;
    slot.clk = 5, slot.cmd = 4, slot.d0 = 6, slot.d1 = 7, slot.d2 = 2, slot.d3 = 3;
    const esp_vfs_fat_sdmmc_mount_config_t mount = {
        .format_if_mount_failed = false, .max_files = 12, .allocation_unit_size = 16 * 1024,
    };
    esp_err_t err = esp_vfs_fat_sdmmc_mount("/sdcard", &host, &slot, &mount, &card);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "no microSD: %s", esp_err_to_name(err));
        return false;
    }
    sdmmc_card_print_info(stdout, card);
    static const ff_diskio_impl_t fast = {ff_sdmmc_initialize, ff_sdmmc_status, fast_read, ff_sdmmc_write, ff_sdmmc_ioctl};
    if (card->csd.sector_size == 512 && (bounce = heap_caps_malloc(BOUNCE_SECTORS * 512, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL)))
        ff_diskio_register(ff_diskio_get_pdrv_card(card), &fast);
    else ESP_LOGW(TAG, "card reads stay sector by sector");
    return true;
}

static bool flash_mount(void) {
    static wl_handle_t wl;
    const esp_vfs_fat_mount_config_t mount = {.format_if_mount_failed = false, .max_files = 12};
    esp_err_t err = esp_vfs_fat_spiflash_mount_rw_wl("/flash", "game", &mount, &wl);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "no game partition: %s", esp_err_to_name(err));
        return false;
    }
    return true;
}

bool storage_mount(void) {
    bool sd = sd_mount(), flash = flash_mount(); /* both: the launcher lists the card's games, then the flash's */
    if (!sd) ESP_LOGI(TAG, "no card: games from flash (no music)");
    return sd || flash;
}
