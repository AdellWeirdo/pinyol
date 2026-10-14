/* The cable: a game sent over the console's USB cable by pinyol's editor (Chrome's Web Serial), written to the card
 * (or, with no card, the flash) and started at once. A line each way; the console's answers start with "@pinyol " (the
 * log shares the cable) and it answers every line, so the editor never sends faster than it writes:
 *   hello                  @pinyol hello 1 <card|flash> <free KB>
 *   begin <id> <bytes>     the game playing (or the list) gives way, a folder is made ready: @pinyol ok | @pinyol err <why>
 *   file <path> <bytes>    the next file, a path inside the game made of safe names ("assets/SPR_x.rgb565"): ok
 *   data <base64>          its next bytes, at most 768 a line: ok
 *   end                    all of it: checked, the old copy replaced (its saves kept), the game started: ok
 *   abort                  what came is thrown away: ok
 *   patch <id> <bytes>     as begin, but the files that come are added to the game already there, each replacing its
 *                          own (new pictures for a game whose music is too big to send again): the game must be there
 * A game is written to games/.cable first (the list skips dot folders) and only replaces the old one whole. Lines that
 * are none of these go to remote.c in test builds (-DBP_REMOTE). */
#include "cable.h"

#include <dirent.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "bp.h"
#include "driver/usb_serial_jtag.h"
#include "driver/usb_serial_jtag_vfs.h"
#include "esp_vfs_fat.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "launcher.h"
#include "mbedtls/base64.h"
#include "remote.h"
#include "sd.h"

#define LINE 1100            /* a data line: "data " and 768 bytes in base64 */
#define CHUNK 768
#define GAME_MAX (32L << 20) /* a game sent at once */
#define FILE_MAX (16L << 20)
#define IDLE_MS 15000        /* nothing for this long: the editor is gone, what came is thrown away */

static char line[LINE];
static int len;
static bool overlong, ready;
static volatile bool wanted;
static bool patching; /* patch, not begin: the files go into the game there */
static char want_id[32];
static long want_bytes;

void cable_init(void) {
    usb_serial_jtag_driver_config_t cfg = USB_SERIAL_JTAG_DRIVER_CONFIG_DEFAULT();
    cfg.rx_buffer_size = 2048;
    if (usb_serial_jtag_driver_install(&cfg) != ESP_OK) return;
    usb_serial_jtag_vfs_use_driver(); /* the log goes through the driver too; with nobody reading it drops, not waits */
    ready = true;
}

static void say(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    printf("@pinyol ");
    vprintf(fmt, ap);
    printf("\n");
    fflush(stdout);
    va_end(ap);
}

static const char *root(void) { return storage_card() ? "/sdcard" : "/flash"; }

static uint64_t free_bytes(void) {
    uint64_t total = 0, room = 0;
    return esp_vfs_fat_info(root(), &total, &room) == ESP_OK ? room : 0;
}

static bool safe_id(const char *s) { /* a game's folder: what the editor makes of its title */
    size_t n = strlen(s);
    if (!n || n > 31) return false;
    for (; *s; s++)
        if (!((*s >= 'a' && *s <= 'z') || (*s >= '0' && *s <= '9') || *s == '_')) return false;
    return true;
}

static bool safe_path(const char *p) { /* inside the game: up to 4 parts of letters, digits, _ - . (none starts with .) */
    int parts = 0;
    if (strlen(p) > 100) return false;
    for (const char *s = p; *s;) {
        const char *e = strchr(s, '/');
        size_t n = e ? (size_t)(e - s) : strlen(s);
        if (!n || n > 48 || s[0] == '.' || ++parts > 4) return false;
        for (size_t i = 0; i < n; i++) {
            char c = s[i];
            if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.'))
                return false;
        }
        s += n + (e ? 1 : 0);
        if (e && !*s) return false; /* "dir/" */
    }
    return parts > 0;
}

static void remove_tree(const char *path) {
    DIR *d = opendir(path);
    if (!d) {
        unlink(path);
        return;
    }
    char sub[256];
    for (struct dirent *e; (e = readdir(d));) {
        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
        snprintf(sub, sizeof sub, "%s/%s", path, e->d_name);
        if (e->d_type == DT_DIR) remove_tree(sub);
        else unlink(sub);
    }
    closedir(d);
    rmdir(path);
}

static void make_parents(const char *file) { /* the folders a file's path goes through */
    char p[256];
    snprintf(p, sizeof p, "%s", file);
    for (char *s = strchr(p + 1, '/'); s; s = strchr(s + 1, '/')) {
        *s = 0;
        mkdir(p, 0755);
        *s = '/';
    }
}

/* Outside a transfer: the hello, a begin (answered once the game has stopped), or a test build's remote line. */
static void command(const char *cmd) {
    char id[32];
    long bytes = 0;
    if (!strcmp(cmd, "hello")) {
        say("hello 1 %s %llu", storage_card() ? "card" : "flash", (unsigned long long)(free_bytes() / 1024));
    } else if (sscanf(cmd, "begin %31s %ld", id, &bytes) == 2 || sscanf(cmd, "patch %31s %ld", id, &bytes) == 2) {
        if (!safe_id(id) || bytes <= 0 || bytes > GAME_MAX) say("err not a game this console can take");
        else snprintf(want_id, sizeof want_id, "%s", id), want_bytes = bytes, patching = cmd[0] == 'p', wanted = true;
    } else if (!strcmp(cmd, "abort")) {
        say("ok"); /* nothing on its way */
    } else {
#ifdef BP_REMOTE
        remote_line(cmd);
#endif
    }
}

void cable_poll(hal_input *in) {
    char buf[64];
    int n = ready && !wanted ? usb_serial_jtag_read_bytes(buf, sizeof buf, 0) : 0;
    for (int i = 0; i < n; i++) {
        if (buf[i] == '\n' || buf[i] == '\r') {
            line[len] = 0;
            if (len && !overlong) command(line);
            len = 0;
            overlong = false;
        } else if (len < LINE - 1) line[len++] = buf[i];
        else overlong = true;
    }
#ifdef BP_REMOTE
    remote_input(in);
#else
    (void)in;
#endif
}

bool cable_wanted(void) { return wanted; }

static int read_line(void) { /* the next line into `line`: its length, or -1 after IDLE_MS of nothing */
    len = 0;
    overlong = false;
    for (;;) {
        char c;
        if (usb_serial_jtag_read_bytes(&c, 1, pdMS_TO_TICKS(IDLE_MS)) != 1) return -1;
        if (c == '\n' || c == '\r') {
            if (!len) continue;
            line[len] = 0;
            return overlong ? 0 : len;
        }
        if (len < LINE - 1) line[len++] = c;
        else overlong = true;
    }
}

/* Every file under from into the same place under to, replacing what is there (patch). */
static bool move_tree(const char *from, const char *to) {
    DIR *d = opendir(from);
    if (!d) return false;
    bool ok = true;
    mkdir(to, 0755);
    for (struct dirent *e; ok && (e = readdir(d));) {
        if (e->d_name[0] == '.') continue;
        char a[256], b[256];
        snprintf(a, sizeof a, "%s/%s", from, e->d_name);
        snprintf(b, sizeof b, "%s/%s", to, e->d_name);
        if (e->d_type == DT_DIR) ok = move_tree(a, b);
        else remove(b), ok = !rename(a, b);
    }
    closedir(d);
    return ok;
}

bool cable_receive(uint16_t *frame, char *id, size_t id_size) {
    static unsigned char bytes[CHUNK + 4];
    char tmp[48], dst[64], path[256], title[64];
    const char *why = NULL;
    FILE *f = NULL;
    long left = 0, got = 0;
    int shown = -1;
    wanted = false;
    snprintf(tmp, sizeof tmp, "%s/games/.cable", root());
    snprintf(dst, sizeof dst, "%s/games/%s", root(), want_id);
    snprintf(path, sizeof path, "%s/games", root());
    mkdir(path, 0755);
    remove_tree(tmp);
    if ((uint64_t)want_bytes + 256 * 1024 > free_bytes()) { /* room for it while the old copy is still there */
        say("err no room: %llu KB free", (unsigned long long)(free_bytes() / 1024));
        return false;
    }
    if (mkdir(tmp, 0755)) {
        say("err cannot write to %s", root());
        return false;
    }
    snprintf(title, sizeof title, "Recibiendo %s", want_id);
    launcher_message(frame, title, 0);
    say("ok");
    for (;;) {
        int n = read_line();
        long size = 0;
        char rel[160];
        if (n < 0) {
            why = "nothing came for a while";
            break;
        }
        if (!strncmp(line, "data ", 5)) {
            size_t out = 0;
            if (!f || mbedtls_base64_decode(bytes, sizeof bytes, &out, (const unsigned char *)line + 5, (size_t)n - 5) ||
                (long)out > left) {
                why = "bad data";
                break;
            }
            if (fwrite(bytes, 1, out, f) != out) {
                why = "the card is full or failing";
                break;
            }
            left -= (long)out, got += (long)out;
            if (!left) {
                fclose(f);
                f = NULL;
            }
            int pct = (int)(got * 100 / want_bytes);
            if (pct / 5 != shown / 5) launcher_message(frame, title, shown = pct); /* every 5 %: drawing takes time */
            say("ok");
        } else if (sscanf(line, "file %159s %ld", rel, &size) == 2) {
            if (f || left || !safe_path(rel) || size < 0 || size > FILE_MAX || got + size > want_bytes) {
                why = "bad file";
                break;
            }
            snprintf(path, sizeof path, "%s/%s", tmp, rel);
            make_parents(path);
            if (!(f = fopen(path, "wb"))) {
                why = "cannot write a file";
                break;
            }
            if (!(left = size)) {
                fclose(f);
                f = NULL;
            }
            say("ok");
        } else if (!strcmp(line, "end")) {
            struct stat st;
            snprintf(path, sizeof path, "%s/game.json", tmp);
            if (f || left || (!patching && stat(path, &st))) {
                why = "not all of it came";
                break;
            }
            if (patching) { /* into the game there, file by file */
                if (stat(dst, &st)) {
                    why = "no such game to add to";
                    break;
                }
                if (!move_tree(tmp, dst)) {
                    why = "cannot put them in place";
                    break;
                }
                remove_tree(tmp);
                snprintf(id, id_size, "%s", want_id);
                hal_log("cable: %s patched, %ld bytes, in %s", want_id, got, dst);
                say("ok");
                return true;
            }
            if (!stat(dst, &st)) { /* the old copy goes; its saves stay with the game */
                char a[96], b[96];
                snprintf(a, sizeof a, "%s/saves", dst);
                snprintf(b, sizeof b, "%s/saves", tmp);
                rename(a, b);
                remove_tree(dst);
            }
            if (rename(tmp, dst)) {
                why = "cannot put it in place";
                break;
            }
            snprintf(id, id_size, "%s", want_id);
            hal_log("cable: %s received, %ld bytes, in %s", want_id, got, dst);
            say("ok");
            return true;
        } else if (!strcmp(line, "abort")) {
            why = "";
            break;
        } else {
            why = "unknown line";
            break;
        }
    }
    if (f) fclose(f);
    remove_tree(tmp);
    if (*why) {
        hal_log("cable: %s not received: %s", want_id, why);
        say("err %s", why);
    } else {
        say("ok");
    }
    return false;
}
