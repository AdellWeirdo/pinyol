#!/usr/bin/env bash

# RetroPie-Setup's module for the pinyol libretro core (docs/libretro.md). It goes in
# ~/RetroPie-Setup/ext/pinyol/scriptmodules/libretrocores/, then:
#   sudo ~/RetroPie-Setup/retropie_packages.sh lr-pinyol
# installs the core and adds the Pinyol system to EmulationStation. A Raspberry Pi 2 and up (32 or 64 bits) or an
# x86-64 PC gets it built already, from the release "libretro" (.github/workflows/libretro.yml); anything else, a Pi 1
# or Zero among them, builds it from the source.

rp_module_id="lr-pinyol"
rp_module_desc="pinyol game engine - libretro core"
rp_module_help="ROM Extensions: .pinyol .zip\n\nCopy your games (a game's .zip, from the Library or tools/pack_game.py) to $romdir/pinyol\n\n"
rp_module_licence="MIT https://raw.githubusercontent.com/ipaud/pinyol/main/LICENSE"
rp_module_repo="git https://github.com/ipaud/pinyol.git main"
rp_module_section="exp"

function _built_lr-pinyol() { # the release's build for this machine, if it has one
    if isPlatform "aarch64"; then
        echo arm64
    elif isPlatform "armv7" || isPlatform "armv8"; then # (armv8 here: a 32-bit system)
        echo armhf
    elif isPlatform "x86" && isPlatform "64bit"; then
        echo x86_64
    fi
}

function depends_lr-pinyol() {
    if [[ -z "$(_built_lr-pinyol)" ]]; then
        getDepends cmake
    fi
}

function sources_lr-pinyol() {
    local arch="$(_built_lr-pinyol)"
    if [[ -n "$arch" ]]; then
        downloadAndExtract "https://github.com/ipaud/pinyol/releases/download/libretro/pinyol_libretro-linux-$arch.zip" "$md_build"
    else
        gitPullOrClone
    fi
}

function build_lr-pinyol() {
    if [[ -z "$(_built_lr-pinyol)" ]]; then
        rm -rf build-release
        cmake -B build-release -DCMAKE_BUILD_TYPE=Release
        cmake --build build-release --target pinyol_libretro -- -j"$__jobs"
        cp build-release/pinyol_libretro.so platform/libretro/pinyol_libretro.info .  # (laid out as the release's zip)
    fi
    md_ret_require="$md_build/pinyol_libretro.so"
}

function install_lr-pinyol() {
    md_ret_files=(
        'pinyol_libretro.so'
        'pinyol_libretro.info'
        'LICENSE'
        'THIRD_PARTY_NOTICES.md'
    )
}

function configure_lr-pinyol() {
    mkRomDir "pinyol"
    defaultRAConfig "pinyol"
    addEmulator 1 "$md_id" "pinyol" "$md_inst/pinyol_libretro.so"
    addSystem "pinyol" "Pinyol" ".pinyol .zip"
}
