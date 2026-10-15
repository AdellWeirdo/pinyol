#!/usr/bin/env bash

# RetroPie-Setup's module for the pinyol libretro core (docs/libretro.md). It goes in
# ~/RetroPie-Setup/ext/pinyol/scriptmodules/libretrocores/, then:
#   sudo ~/RetroPie-Setup/retropie_packages.sh lr-pinyol
# builds the core from this repo, installs it, and adds the Pinyol system to EmulationStation.

rp_module_id="lr-pinyol"
rp_module_desc="pinyol game engine - libretro core"
rp_module_help="ROM Extensions: .pinyol .zip\n\nCopy your games (a game's .zip, from the Library or tools/pack_game.py) to $romdir/pinyol\n\n"
rp_module_licence="MIT https://raw.githubusercontent.com/ipaud/pinyol/main/LICENSE"
rp_module_repo="git https://github.com/ipaud/pinyol.git main"
rp_module_section="exp"

function depends_lr-pinyol() {
    getDepends cmake
}

function sources_lr-pinyol() {
    gitPullOrClone
}

function build_lr-pinyol() {
    rm -rf build-release
    cmake -B build-release -DCMAKE_BUILD_TYPE=Release
    cmake --build build-release --target pinyol_libretro -- -j"$__jobs"
    md_ret_require="$md_build/build-release/pinyol_libretro.so"
}

function install_lr-pinyol() {
    md_ret_files=(
        'build-release/pinyol_libretro.so'
        'platform/libretro/pinyol_libretro.info'
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
