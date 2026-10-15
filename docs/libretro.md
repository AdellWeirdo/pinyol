# pinyol in RetroArch: RetroPie, Batocera, Lakka and the rest

`platform/libretro/` builds the engine as a [libretro](https://www.libretro.com) core, so pinyol games play in
RetroArch and in everything built on it: RetroPie and Lakka on a Raspberry Pi, Batocera, Recalbox, handhelds that run
RetroArch, a desktop. It is the same engine as the console's and the simulator's: the same game plays the same.

Tested: built and tested (`ctest -R libretro`) on macOS, on Linux arm64 (Debian 12, the base of Raspberry Pi OS) and
on 32-bit ARM as in RetroPie's image (Debian 10, GCC 8, CMake 3.13), where RetroPie-Setup also installed it with
`lr-pinyol.sh`; played in RetroArch 1.22 on a Mac. Not yet tried on a real Raspberry Pi.

## Build it

```sh
cmake -B build-release -DCMAKE_BUILD_TYPE=Release
cmake --build build-release --target pinyol_libretro -j4    # -> build-release/pinyol_libretro.so (.dylib on a Mac)
```

Build it as Release: the default Debug build carries the sanitizers, and RetroArch cannot load a core built with
them. On a Mac with Apple silicon, the RetroArch that Homebrew installs is an Intel app: add
`-DCMAKE_OSX_ARCHITECTURES=x86_64`, or it will refuse the core ("incompatible architecture").

## The games

A game is what `tools/pack_game.py` makes, or what the Library hands out: a `.zip` with a folder `<id>/` inside. The
core opens it as it is; renamed to `<id>.pinyol` it is the same file, and a game list can tell it apart from other
zips. A game's folder also opens, through its `game.json`.

The first time, a zip is unpacked into the frontend's save folder, as `<saves>/pinyol/<id>/game`. After that it
is not even read while it stays the same (the same size and time); a changed zip is unpacked again. The game's saves
go to `<saves>/pinyol/<id>/saves`, for a zip or a folder alike. A zip with a damaged file, or with a name that
would land outside its folder, is refused.

## RetroArch on a desktop

```sh
retroarch -L build-release/pinyol_libretro.so dist/naves.zip
```

Or from its menu: *Load Core*, then *Load Content*. Copy `platform/libretro/pinyol_libretro.info` into
RetroArch's info folder (*Settings, Directory, Core Info*) for it to show the core as "Pinyol" and know its files.

## RetroPie

RetroPie-Setup builds and installs it with the module in `platform/libretro/lr-pinyol.sh`. On the Raspberry Pi:

```sh
mkdir -p ~/RetroPie-Setup/ext/pinyol/scriptmodules/libretrocores
curl -fsSL https://raw.githubusercontent.com/ipaud/pinyol/main/platform/libretro/lr-pinyol.sh \
  -o ~/RetroPie-Setup/ext/pinyol/scriptmodules/libretrocores/lr-pinyol.sh
sudo ~/RetroPie-Setup/retropie_packages.sh lr-pinyol
```

Once the module is in place it is also in RetroPie-Setup's menu (*Manage packages, Manage experimental packages,
lr-pinyol*). It builds the core on the Pi (a few minutes), installs it, and adds the Pinyol system to
EmulationStation, which shows the `.pinyol` and `.zip` games in `~/RetroPie/roms/pinyol`. Copy the games there and
restart EmulationStation. Running it again updates the core.

### By hand

The same, step by step (it takes a few minutes):

```sh
sudo apt install -y cmake git
git clone https://github.com/ipaud/pinyol && cd pinyol
cmake -B build-release -DCMAKE_BUILD_TYPE=Release && cmake --build build-release --target pinyol_libretro -j4
sudo mkdir -p /opt/retropie/libretrocores/lr-pinyol /opt/retropie/configs/pinyol
sudo cp build-release/pinyol_libretro.so /opt/retropie/libretrocores/lr-pinyol/
mkdir -p ~/RetroPie/roms/pinyol
```

Then tell `runcommand` how to start it. Write `/opt/retropie/configs/pinyol/emulators.cfg`:

```
lr-pinyol = "/opt/retropie/emulators/retroarch/bin/retroarch -L /opt/retropie/libretrocores/lr-pinyol/pinyol_libretro.so --config /opt/retropie/configs/pinyol/retroarch.cfg %ROM%"
default = "lr-pinyol"
```

and `/opt/retropie/configs/pinyol/retroarch.cfg`, so it takes RetroPie's settings for every system:

```
#include "/opt/retropie/configs/all/retroarch.cfg"
```

Last, add the system to EmulationStation. Copy `/etc/emulationstation/es_systems.cfg` to
`/opt/retropie/configs/all/emulationstation/es_systems.cfg` (if it is not there yet) and add, inside
`<systemList>`:

```xml
<system>
  <name>pinyol</name>
  <fullname>Pinyol</fullname>
  <path>/home/pi/RetroPie/roms/pinyol</path>
  <extension>.pinyol .zip</extension>
  <command>/opt/retropie/supplementary/runcommand/runcommand.sh 0 _SYS_ pinyol %ROM%</command>
  <platform>pinyol</platform>
  <theme>pinyol</theme>
</system>
```

(`/home/pi`: your home folder, if the user is not `pi`.) Copy the games' zips into `~/RetroPie/roms/pinyol`
and restart EmulationStation. Leave `.json` out of the extensions: the unpacked games go into the save folder, which
in RetroPie is the games' own folder, and their `game.json` would show up in the list.

Other frontends (Batocera, Recalbox, Lakka) take a core the same way: the `.so` in their cores folder, and a system
that opens `.pinyol` or `.zip` with it.

## The controls

| RetroPad | pinyol |
|---|---|
| d-pad | d-pad |
| A (right) | A |
| B (bottom) | B |
| X, Y | C |
| START | START |
| SELECT | MENU |
| touch screen or mouse | touch |

RetroArch remaps them per core (*Quick Menu, Controls*).

## What it does not do yet

- **Save states**, and so rewind, run-ahead and netplay. An emulator saves the memory of the machine it emulates; a
  pinyol game's state is its Lua heap and the engine's own memory, full of pointers that mean nothing in another run
  or on another machine. Playing the inputs again from the start instead would take seconds for every minute played.
  The games keep their own saves, as on the console, and consoles play together over `link` (below).
- **The microphone**: a game that listens hears silence.
- **Its music clock** assumes RetroArch's default audio latency (64 ms). A rhythm game played with another one can
  still be tuned in the game (`music_time`, [lua.md](lua.md)).

Consoles playing together (`link`) work as in the desktop simulator: cores on the same network hear each other.
