/* What differs on Windows (MinGW): mkdir takes no mode, and fsync is _commit. */
#ifndef PINYOL_COMPAT_H
#define PINYOL_COMPAT_H
#include <stdio.h>
#include <sys/stat.h>
#ifdef _WIN32
#include <direct.h>
#include <io.h>
#define mkdir(path, mode) _mkdir(path)
#define fsync(fd) _commit(fd)
#else
#include <unistd.h>
#endif
#endif
