"""THIRD_PARTY_NOTICES.md: the notices and licences of everything pinyol carries that others wrote, gathered from
their own files: the engine's third_party/, the editor's and the site's vendored code, what the desktop app carries,
the parts of ESP-IDF and its toolchain that end up in the console's firmware, and what Emscripten puts in the web
player.

    python3 tools/notices.py        # needs ESP-IDF (IDF_PATH, or ~/esp/esp-idf-v5.4.2) and Emscripten (em-config)

Run it again when a version changes; the file goes with every release.
"""
from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IDF = Path(os.environ.get("IDF_PATH", Path.home() / "esp/esp-idf-v5.4.2"))
TOOLS = Path(os.environ.get("IDF_TOOLS_PATH", Path.home() / ".espressif"))
EM_CACHE = Path(subprocess.run(["em-config", "CACHE"], capture_output=True, text=True, check=True).stdout.strip())
EM = EM_CACHE.parent

BSD3 = """Copyright (c) 2006-2016, Matthew Conte
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the
following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following
   disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following
   disclaimer in the documentation and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote
   products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."""


def read(path: Path) -> str:
    if not path.exists():
        raise SystemExit(f"missing {path}")
    return path.read_text(encoding="utf-8", errors="replace").strip()


def comment(path: Path, start: str, end: str) -> str:
    """A licence written in a source file's opening comment, from the line holding `start` to the one holding `end`."""
    lines = read(path).splitlines()
    a = next(i for i, l in enumerate(lines) if start in l)
    b = next(i for i, l in enumerate(lines) if i > a and end in l)
    return "\n".join(re.sub(r"^\s*[/*]?\s?", "", l).rstrip(" /") for l in lines[a:b + 1])


def block(title: str, what: str, text: str | None = None) -> str:
    out = f"### {title}\n\n{what}\n"
    return out + (f"\n```\n{text}\n```\n" if text else "")


def fonts() -> str:
    lines = []
    for ofl in sorted([*(ROOT / "third_party/fonts").glob("*/OFL.txt"), ROOT / "third_party/pixelify/OFL.txt"]):
        head = read(ofl).split("This Font Software is licensed")[0].strip()
        lines.append(f"- `{ofl.parent.relative_to(ROOT)}`: {' '.join(head.split())}")
    return "\n".join(lines)


def main() -> None:
    sdl = next(EM_CACHE.glob("ports/sdl2/SDL-release-*/LICENSE.txt"))
    newlib = next(TOOLS.glob("tools/xtensa-esp-elf/*/xtensa-esp-elf/share/licenses/newlib/COPYING.NEWLIB"))
    ofl = read(ROOT / "third_party/pixelify/OFL.txt")
    parts = [
        "# Third-party notices\n",
        "pinyol is MIT licensed ([LICENSE](LICENSE)). It carries code and fonts that others wrote, under their own "
        "licences; this file gathers their notices, as those licences ask. Made by `tools/notices.py`.\n",
        "## In the engine (the simulator, the web player, the console and the libretro core)\n",
        block("Lua 5.4", "MIT. `third_party/lua`", read(ROOT / "third_party/lua/LICENSE")),
        block("cJSON", "MIT. `third_party/cjson` (and ESP-IDF's `json` component, the same library)",
              read(ROOT / "third_party/cjson/LICENSE")),
        block("pocketmod", "MIT. `third_party/pocketmod`", read(ROOT / "third_party/pocketmod/LICENSE")),
        block("Fonts", "SIL Open Font License 1.1 (its text is at the end). What pinyol makes from them (`.fnt`, "
              "`.woff2`) is a Modified Version under that licence, and never carries a Reserved Font Name: Press Start "
              "2P's conversions are called Arcade 8, and the font packs (`tools/font2fnt.py --pack`) name their files by pack, never by font.\n\n" + fonts()),
        "## In the libretro core (RetroArch, RetroPie)\n",
        block("puff", "zlib licence. `third_party/puff`, the zip reader's inflate",
              comment(ROOT / "third_party/puff/puff.h", "Copyright (C)", "madler@alumni")),
        block("libretro.h", "MIT. `third_party/libretro`, the libretro API",
              comment(ROOT / "third_party/libretro/libretro.h", "Copyright (C) 2010", "OUT OF OR IN CONNECTION")),
        f"## In the console's firmware (ESP-IDF {IDF.name.removeprefix('esp-idf-')})\n",
        block("ESP-IDF", "Apache License 2.0 (its text is at the end). Copyright Espressif Systems (Shanghai) Co., Ltd. "
              "The drivers, the system, and the precompiled Wi-Fi, ESP-NOW, coexistence and PHY libraries, which are "
              "under the same licence (`components/esp_wifi/lib/LICENSE`)."),
        block("Mbed TLS", "Apache License 2.0 (dual licensed Apache-2.0 OR GPL-2.0-or-later; used under Apache-2.0). "
              "Copyright The Mbed TLS Contributors."),
        block("FreeRTOS kernel", "MIT.", read(IDF / "components/freertos/FreeRTOS-Kernel/LICENSE.md")),
        block("lwIP", "BSD-3-Clause.", read(IDF / "components/lwip/lwip/COPYING")),
        block("wpa_supplicant", "BSD-3-Clause.", read(IDF / "components/wpa_supplicant/COPYING")),
        block("TLSF (the heap allocator)", "BSD-3-Clause.", BSD3),
        block("FatFs", "ChaN's licence.", comment(IDF / "components/fatfs/src/ff.c", "Copyright (C)", "by use of this software")),
        block("Xtensa HAL", "MIT-style.", comment(IDF / "components/xtensa/include/xtensa/hal.h", "Copyright (c)",
                                                  "SOFTWARE OR THE USE OR OTHER DEALINGS")),
        block("newlib (the C library, from the toolchain)", "BSD-style licences of several authors, as listed here.",
              read(newlib)),
        block("The display's and the codec's settings", "Not code from others: the ST77922 panel's init table "
              "(firmware/main/display.c) is the register settings its maker publishes for this module (LCDwiki, "
              "https://github.com/ydedox/st77922), values the hardware needs; the ES8311 codec's registers are set as "
              "Espressif's esp_codec_dev driver (Apache License 2.0) and the codec's datasheet set them."),
        block("GCC runtime (libgcc, libstdc++)", "GPL-3.0 with the GCC Runtime Library Exception, which puts no "
              "conditions on the firmware built with them."),
        "## In the web player (Emscripten)\n",
        block("SDL 2", "zlib licence.", read(sdl)),
        block("Emscripten's runtime and libraries (musl, and others)", "MIT / University of Illinois NCSA, as below; "
              "musl's own notice follows.", read(next(d / "LICENSE" for d in (EM, EM.parent) if (d / "LICENSE").exists())) + "\n\n" + read(EM / "system/lib/libc/musl/COPYRIGHT")),
        "## In the desktop app (Cirera for Mac and Windows)\n",
        block("SDL 2", "zlib licence, the notice above: the app carries SDL 2.32 inside it."),
        block("mingw-w64 runtime (the Windows app)", "Zope Public License 2.1. `third_party/mingw-w64`",
              read(ROOT / "third_party/mingw-w64/COPYING")),
        block("winpthreads (the Windows app)", "MIT, with parts under a BSD licence. `third_party/mingw-w64`",
              read(ROOT / "third_party/mingw-w64/COPYING.winpthreads")),
        block("GCC runtime (libgcc, the Windows app)", "GPL-3.0 with the GCC Runtime Library Exception, which puts no "
              "conditions on the programs built with it."),
        "## In the editor and the site\n",
        block("Blockly", "Apache License 2.0. Copyright Google LLC. `editor/vendor/blockly`"),
        block("GoatCounter's count.js", "ISC licence (https://opensource.org/licenses/ISC), as the file says. "
              "`site/vendor/goatcounter`, the site's visit counter."),
        block("ESP Web Tools (with esptool-js)", "Apache License 2.0. ESPHome and Espressif. "
              "`site/vendor/esp-web-tools`, as published; the libraries in its bundle keep their own licences."),
        "## Apache License 2.0\n",
        f"```\n{read(IDF / 'LICENSE')}\n```\n",
        "## SIL Open Font License 1.1\n",
        f"```\n{ofl[ofl.index('This Font Software is licensed'):]}\n```\n",
    ]
    (ROOT / "THIRD_PARTY_NOTICES.md").write_text("\n".join(parts))
    print(f"THIRD_PARTY_NOTICES.md: {len(''.join(parts)) // 1024} KB")


if __name__ == "__main__":
    main()
