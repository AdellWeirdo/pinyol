/* The Cirera desktop app's files (platform/sdl/main.c, --console or PINYOL_APP): where its menu and games are, the
 * games it comes with copied where they can be played and saved, and a game's .zip dropped on the window installed.
 *   menu:   <app>/cirera            (the console's menu, firmware/cirera: a pinyol game)
 *   games:  <user data>/games/<id>  (macOS: ~/Library/Application Support/pinyol/Cirera, Windows: %APPDATA%\pinyol\Cirera)
 * The games that come with the app (<app>/games) are copied there, so their saves live beside them, and copied again
 * by a newer app (its games/.stamp changed). */
#include "desktop.h"

#include <SDL.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "compat.h"
#include "hal.h"

#ifdef _WIN32
#include <process.h>
#include <windows.h>
#else
#include <spawn.h>
#include <sys/wait.h>
extern char **environ;
#endif

static bool is_dir(const char *p) {
    struct stat st;
    return !stat(p, &st) && S_ISDIR(st.st_mode);
}

static bool is_file(const char *p) {
    struct stat st;
    return !stat(p, &st) && S_ISREG(st.st_mode);
}

static bool is_link(const char *p) { /* a link, or on Windows any reparse point: never followed */
#ifdef _WIN32
    DWORD a = GetFileAttributesA(p);
    return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_REPARSE_POINT);
#else
    struct stat st;
    return !lstat(p, &st) && S_ISLNK(st.st_mode);
#endif
}

/* Only folders and files under dir: a link unpacked from a zip could point anywhere on the computer */
static bool plain(const char *dir) {
    DIR *d = opendir(dir);
    if (!d) return false;
    struct dirent *e;
    bool ok = true;
    while (ok && (e = readdir(d))) {
        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
        char c[1024];
        snprintf(c, sizeof c, "%s/%s", dir, e->d_name);
        ok = !is_link(c) && (is_file(c) || (is_dir(c) && plain(c)));
    }
    closedir(d);
    return ok;
}

static bool copy_file(const char *from, const char *to) {
    FILE *a = fopen(from, "rb"), *b = a ? fopen(to, "wb") : NULL;
    char buf[65536];
    size_t n;
    bool ok = a && b;
    while (ok && (n = fread(buf, 1, sizeof buf, a)) > 0) ok = fwrite(buf, 1, n, b) == n;
    if (a) fclose(a);
    if (b && fclose(b)) ok = false;
    return ok;
}

static bool same_file(const char *a, const char *b) {
    FILE *x = fopen(a, "rb"), *y = x ? fopen(b, "rb") : NULL;
    bool same = x && y;
    while (same) {
        int c = fgetc(x);
        same = c == fgetc(y);
        if (c == EOF) break;
    }
    if (x) fclose(x);
    if (y) fclose(y);
    return same;
}

static bool copy_tree(const char *from, const char *to) {
    DIR *d = opendir(from);
    if (!d) return false;
    if (mkdir(to, 0755) && !is_dir(to)) return closedir(d), false;
    struct dirent *e;
    bool ok = true;
    while (ok && (e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        char a[1024], b[1024];
        snprintf(a, sizeof a, "%s/%s", from, e->d_name);
        snprintf(b, sizeof b, "%s/%s", to, e->d_name);
        ok = !is_link(a) && (is_dir(a) ? copy_tree(a, b) : copy_file(a, b));
    }
    closedir(d);
    return ok;
}

static void rm_tree(const char *p) {
    DIR *d = opendir(p);
    if (d) {
        struct dirent *e;
        while ((e = readdir(d))) {
            if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
            char c[1024];
            snprintf(c, sizeof c, "%s/%s", p, e->d_name);
            if (is_dir(c) && !is_link(c)) rm_tree(c);
            else if (remove(c)) rmdir(c); /* (a link to a folder, on Windows: the link goes, not what it points to) */
        }
        closedir(d);
    }
    rmdir(p);
}

bool desktop_paths(char *menu, char *games, size_t n) {
    char *base = SDL_GetBasePath(), *pref = SDL_GetPrefPath("pinyol", "Cirera"); /* (both end in a separator) */
    bool ok = base && pref;
    if (ok) {
        snprintf(menu, n, "%scirera", base);
        snprintf(games, n, "%sgames", pref);
        mkdir(games, 0755);
        char bundled[1024], stamp[1100], mine[1100];
        snprintf(bundled, sizeof bundled, "%sgames", base);
        snprintf(stamp, sizeof stamp, "%s/.stamp", bundled); /* tools/make_app.py's: what the app's games are */
        snprintf(mine, sizeof mine, "%s/.stamp", games);
        DIR *d = same_file(stamp, mine) ? NULL : opendir(bundled);
        struct dirent *e;
        bool copied = d != NULL;
        while (d && (e = readdir(d))) { /* over the player's copy, if there is one: its saves stay */
            char from[1024], to[1024];
            snprintf(from, sizeof from, "%s/%s", bundled, e->d_name);
            snprintf(to, sizeof to, "%s/%s", games, e->d_name);
            if (e->d_name[0] == '.' || !is_dir(from)) continue;
            if (!copy_tree(from, to)) hal_log("app: could not copy %s", e->d_name), copied = false;
        }
        if (d) closedir(d);
        if (copied) copy_file(stamp, mine);
        ok = is_dir(menu) && is_dir(games);
    }
    SDL_free(base);
    SDL_free(pref);
    return ok;
}

/* tar -xf ZIP -C DIR: macOS's and Windows 10's tar (bsdtar) both read zips, and both refuse a name with ".." or an
 * absolute path, so nothing lands outside DIR */
static bool untar(const char *zip, const char *dir) {
#ifdef _WIN32
    char tar[MAX_PATH + 16], qz[1100], qd[1100]; /* Windows' own tar, not one on the PATH (Git's GNU tar reads no zip) */
    UINT n = GetSystemDirectoryA(tar, MAX_PATH);
    if (!n || n >= MAX_PATH) return false;
    strcat(tar, "\\tar.exe");
    snprintf(qz, sizeof qz, "\"%s\"", zip); /* _spawnv joins its arguments with spaces: quote the paths */
    snprintf(qd, sizeof qd, "\"%s\"", dir);
    const char *argv[] = {"tar", "-xf", qz, "-C", qd, NULL};
    return _spawnv(_P_WAIT, tar, argv) == 0;
#else
    char *argv[] = {"tar", "-xf", (char *)zip, "-C", (char *)dir, NULL};
    pid_t pid;
    int st;
    return posix_spawnp(&pid, "tar", NULL, NULL, argv, environ) == 0 && waitpid(pid, &st, 0) == pid &&
           WIFEXITED(st) && WEXITSTATUS(st) == 0;
#endif
}

/* The game in a .zip (game.json at its top, or in one folder as tools/pack_game.py makes it) installed as
 * <games>/<its folder's name, or the zip's>, kept to letters, digits, _ and -. A game already there is unpacked over,
 * without the saves the zip may carry, so the player's stay. */
bool desktop_install(const char *zip, const char *games, char *name, size_t name_max) {
    char tmp[1024], json[1100], src[1100] = "", id[41] = "";
    snprintf(tmp, sizeof tmp, "%s/.instalando", games);
    rm_tree(tmp);
    if (mkdir(tmp, 0755) || !untar(zip, tmp) || !plain(tmp)) return rm_tree(tmp), false;
    snprintf(json, sizeof json, "%s/game.json", tmp);
    const char *slash = strrchr(zip, '/'), *back = strrchr(zip, '\\');
    const char *base = back && (!slash || back > slash) ? back + 1 : slash ? slash + 1 : zip;
    if (is_file(json)) { /* game.json at the top: the zip's name */
        snprintf(id, sizeof id, "%s", base);
        char *dot = strrchr(id, '.');
        if (dot && !strcmp(dot, ".zip")) *dot = 0;
        snprintf(src, sizeof src, "%s", tmp);
    } else { /* in one folder */
        DIR *d = opendir(tmp);
        struct dirent *e;
        while (d && (e = readdir(d))) {
            snprintf(json, sizeof json, "%s/%s/game.json", tmp, e->d_name);
            if (e->d_name[0] != '.' && is_file(json)) {
                snprintf(id, sizeof id, "%s", e->d_name);
                snprintf(src, sizeof src, "%s/%s", tmp, e->d_name);
                break;
            }
        }
        if (d) closedir(d);
    }
    for (char *c = id; *c; c++) /* a folder name that is safe anywhere: no dots, slashes, spaces */
        if (!((*c >= 'a' && *c <= 'z') || (*c >= 'A' && *c <= 'Z') || (*c >= '0' && *c <= '9') || *c == '_' || *c == '-'))
            *c = '_';
    snprintf(name, name_max, "%s", id);
    bool ok = *src && *id && SDL_strcasecmp(id, CONSOLE_MENU_ID) != 0;
    if (ok) {
        char to[1024], saves[1200];
        snprintf(to, sizeof to, "%s/%s", games, id);
        if (is_dir(to)) {
            snprintf(saves, sizeof saves, "%s/saves", src); /* (src/game.c's save folder) */
            rm_tree(saves);
            ok = copy_tree(src, to); /* ponytail: files the new version dropped stay; harmless, the game never reads them */
        } else
            ok = rename(src, to) == 0 || copy_tree(src, to);
    }
    rm_tree(tmp);
    return ok;
}
