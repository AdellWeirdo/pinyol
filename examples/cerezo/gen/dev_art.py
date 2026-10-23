"""Placeholder art so the game's code can be written and tested before the real art is drawn (build.py --dev).

It defines the same names the artists' briefs ask for, with simple pictures; the real modules replace it."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gbart as g  # noqa: E402
from gbart import ART  # noqa: E402

HERO16 = g.pic("""
................
.....333333.....
...3331111333...
..310000000013..
..333333333333..
...3100000013...
...3103003013...
...3100000013...
....31000013....
....33222233....
...3211111123...
..303211112303..
...3211111123...
....32222223....
....33.33.33....
...333.33.333...
""", 16, 16)


def on32(p, dx=0, dy=0):
    return g.overlay(g.blank(32, 32), p, 8 + dx, 8 + dy)


def hero_variants():
    hero = ART.sheet("HERO", 16, 16)
    base = HERO16
    names = ["down_0", "down_1", "down_2", "up_0", "up_1", "up_2", "side_0", "side_1", "side_2", "blink", "get_item",
             "hurt_down", "hurt_up", "hurt_side", "die_0", "die_1", "die_2", "die_3", "push_side_0", "push_side_1",
             "push_down_0", "push_down_1", "push_up_0", "push_up_1", "fall", "sleep", "sit_0", "sit_1"]
    for i, n in enumerate(names):
        p = base
        if n.endswith("_1"):
            p = g.shift(base, 0, 1)
        elif n.endswith("_2"):
            p = g.flip_h(base)
        if n.startswith("side"):
            p = g.shift(p, 1, 0)
        hero.add(n, p)
    herox = ART.sheet("HEROX", 32, 32)
    for n in ["swing_down_0", "swing_down_1", "swing_down_2", "swing_up_0", "swing_up_1", "swing_up_2", "swing_side_0",
              "swing_side_1", "swing_side_2", "dig_0", "dig_1", "shoot_down", "shoot_up", "shoot_side", "lantern_down",
              "lantern_up", "lantern_side"]:
        p = on32(base)
        # the tool, a stick where the strike reaches
        if n.endswith("_1") or n.startswith(("shoot", "dig")):
            vx, vy = (0, 1) if "down" in n else (0, -1) if "up" in n else (1, 0)
            for i in range(8, 17):
                x, y = 16 + vx * i, 16 + vy * i
                if 0 <= x < 32 and 0 <= y < 32:
                    p[y][x] = 3
                    if 0 <= x + vy < 32 and 0 <= y + vx < 32:
                        p[y + vx][x + vy] = 2
        herox_pic = p
        herox.add(n, herox_pic)
    fx = ART.sheet("TOOLFX", 16, 16, bank=6)
    for n in ["slash_down_0", "slash_down_1", "slash_up_0", "slash_up_1", "slash_side_0", "slash_side_1", "clod_0", "clod_1",
              "clod_2", "cut_0", "cut_1", "cut_2", "hit_0", "hit_1", "hit_2"]:
        p = g.blank(16, 16)
        for i in range(6):
            p[6 + i // 2][5 + i] = 0
            p[7 + i // 2][5 + i] = 3
        fx.add(n, p)


GRASS_A = g.pic("""
0000000000000000
0000000000000000
0000010000000000
0000121000000000
0000000000010000
0000000000121000
0000000000000000
0000000000000000
0000000000000000
0010000000000000
0121000000000000
0000000000000000
0000000001000000
0000000012100000
0000000000000000
0000000000000000
""", 16, 16)


def tiles():
    ART.meta("overworld", "grass_a", GRASS_A)
    ART.meta("overworld", "grass_b", g.flip_h(GRASS_A))
    ART.meta("overworld", "grass_c", g.flip_v(GRASS_A))
    f = g.overlay(GRASS_A, g.pic(["010", "131", "010"]), 5, 5)
    ART.meta("overworld", "grass_flowers_a", f)
    ART.meta("overworld", "bush", g.overlay(GRASS_A, g.pic("""
................
................
.....333333.....
...3311101133...
..311100011113..
..311000111113..
.31110001111123.
.31100011111123.
.31111111111223.
.31111111112223.
.31111111122223.
..3211111222233.
..3222222222233.
...33222222233..
.....3333333....
................
"""), 0, 0), flags=("solid", "cut", "becomes=grass_a"), bank=3)
    ART.meta("overworld", "rock_a", g.overlay(GRASS_A, g.pic("""
................
................
................
......33333.....
....333111133...
...31100011113..
..3110000111123.
..3100001111223.
..3111111112223.
..3211111122223.
...32222222233..
....333333333...
................
................
................
................
"""), 0, 0), flags=("solid",), bank=6)
    w = g.pic("""
1111111111111111
1111111111111111
1101111111111011
1000111111110001
1111111111111111
1111111111111111
1111111111111111
1111111111111111
1111101111111111
1111000111111111
1111111111111111
1111111111111111
1111111111111111
1110111111111101
1100011111111000
1111111111111111
""", 16, 16)
    ART.meta("overworld", "water_a", w, flags=("water",), bank=2)
    ART.meta("overworld", "water_b", g.shift(w, 3, 1), flags=("water",), bank=2)
    ART.animate("water", ["water_a", "water_b"], 40)
    ART.meta("overworld", "dirt_a", g.pic(["0000000000000000"] * 16, 16, 16), bank=1)
    ART.meta("overworld", "sand_a", g.overlay(g.pic(["0000000000000000"] * 16, 16, 16), g.pic(["1"]), 4, 4), bank=1)
    trunk = g.pic("""
................
................
................
................
................
.....333333.....
....32222223....
....32111123....
....32111123....
....32222223....
.....322223.....
.....322223.....
....33222233....
...3322222233...
................
................
""", 16, 16)
    canopy = g.pic("""
................
......33333.....
....333111133...
...31100011113..
..3110000111113.
..3100000011113.
..3110000111123.
..3111111111123.
..3211111111223.
...32211111223..
....332222233...
.....3333333....
................
................
................
................
""", 16, 16)
    ART.meta("overworld", "tree_trunk", g.overlay(GRASS_A, trunk), flags=("solid",), bank=3)
    ART.meta("overworld", "tree_top", GRASS_A, front=canopy, bank=3)
    ART.meta("overworld", "roof_m", g.pic(["3333333333333333", "3222222222222223", "3211111111111123", "3111111111111113"] * 4, 16, 16), flags=("solid",), bank=5)
    ART.meta("overworld", "door", g.pic(["3333333333333333"] + ["3222222222222223"] * 14 + ["3333333333333333"], 16, 16), flags=("door",), bank=4)


def register():
    hero_variants()
    tiles()


# ------------------------------------------------------------------ the status bar and the dialogue box (tileset "ui")
DIGITS = {
    "0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"], "2": ["111", "001", "111", "100", "111"],
    "3": ["111", "001", "111", "001", "111"], "4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
    "6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"], "8": ["111", "101", "111", "101", "111"],
    "9": ["111", "101", "111", "001", "111"],
}


def glyph8(rows, ink=3, paper=0):
    p = g.blank(8, 8, paper)
    for y, r in enumerate(rows):
        for x, c in enumerate(r):
            if c == "1":
                p[1 + y][2 + x] = ink
    return p


def ui_tiles():
    ART.tile8("ui", "hud_bg", g.blank(8, 8, 0))
    low = g.blank(8, 8, 0)
    low[7] = [3] * 8
    ART.tile8("ui", "hud_bg_low", low)
    heart = g.pic(["........", ".33..33.", "3223323.", "3222223.", ".32223..", "..323...", "...3....", "........"][0:8], 8, 8) if False else None
    full = g.pic(["........", ".33..33.", "32233223", "32222223", ".322223.", "..3223..", "...33...", "........"], 8, 8)
    half = g.pic(["........", ".33..33.", "32233003", "32222003", ".322003.", "..3003..", "...33...", "........"], 8, 8)
    empty = g.pic(["........", ".33..33.", "30033003", "30000003", ".300003.", "..3003..", "...33...", "........"], 8, 8)
    ART.tile8("ui", "heart_full", [r for r in g.text_of(full)])
    ART.tile8("ui", "heart_half", g.text_of(half))
    ART.tile8("ui", "heart_empty", g.text_of(empty))
    for d, rows in DIGITS.items():
        ART.tile8("ui", f"digit_{d}", g.text_of(glyph8(rows)))
    ART.tile8("ui", "icon_cherry", g.text_of(g.pic(["...33...", "..3.3...", ".33.33..", "3223.32.", "3223.32.", ".33..33.", "........", "........"], 8, 8)))
    ART.tile8("ui", "icon_pinyol", g.text_of(g.pic(["........", "..333...", ".32223..", ".32223..", "..333...", "........", "........", "........"], 8, 8)))
    ART.tile8("ui", "icon_key", g.text_of(g.pic(["..33....", ".3003...", "..33....", "..3.....", "..33....", "..3.....", "..33....", "........"], 8, 8)))
    ART.tile8("ui", "icon_bosskey", g.text_of(g.pic(["..3333..", ".300003.", ".300003.", "..3333..", "...33...", "..333...", "...33...", "..333..."], 8, 8)))
    ART.tile8("ui", "icon_map", g.text_of(g.pic(["........", ".333333.", ".31.1.3.", ".3.1.13.", ".31.1.3.", ".333333.", "........", "........"], 8, 8)))
    ART.tile8("ui", "icon_compass", g.text_of(g.pic(["..3333..", ".3....3.", "3..33..3", "3.3..3.3", "3..33..3", ".3....3.", "..3333..", "........"], 8, 8)))
    ART.tile8("ui", "slash", g.text_of(glyph8(["001", "001", "010", "100", "100"])))
    ART.tile8("ui", "icon_pit", g.text_of(g.pic(["........", "..333...", ".31113..", ".31113..", "..333...", "........", "........", "........"], 8, 8)))
    ART.tile8("ui", "icon_pit_empty", g.text_of(g.pic(["........", "..3.3...", ".3...3..", ".3...3..", "..3.3...", "........", "........", "........"], 8, 8)))
    ART.tile8("ui", "x", g.text_of(glyph8(["101", "010", "101"])))
    # the dialogue window: a double border with rounded corners
    f = g.blank(8, 8, 0)
    ART.tile8("ui", "dlg_fill", g.text_of(f))
    t = g.blank(8, 8, 0)
    t[5] = [3] * 8
    t[7] = [3] * 8
    t[6] = [0] * 8
    ART.tile8("ui", "dlg_t", g.text_of(g.flip_v(g.pic(g.text_of(t)))) if False else g.text_of(t))
    b = g.flip_v(t)
    ART.tile8("ui", "dlg_b", g.text_of(b))
    l = [[3 if x in (5, 7) else 0 for x in range(8)] for _ in range(8)]
    ART.tile8("ui", "dlg_l", g.text_of(l))
    r = [row[::-1] for row in l]
    ART.tile8("ui", "dlg_r", g.text_of(r))
    tl = [[0] * 8 for _ in range(8)]
    for i in range(8):
        tl[5][i] = 3 if i >= 5 else tl[5][i]
    corner = g.pic(["........", "........", "........", "........", "........", "..3333..", ".3.....", ".3.3333."][0:8] if False else
                   ["........", "........", "........", "........", "........", "..33333.", ".3......", ".3.33333"], 8, 8) if False else None
    c = g.blank(8, 8, 0)
    for i in range(5, 8):
        c[5][i] = 3
        c[i][5] = 3
    c[7][7] = 3
    c[6][6] = 0
    c[5][5] = 3
    c[6][5] = 3
    c[5][6] = 3
    ART.tile8("ui", "dlg_tl", g.text_of(c))
    ART.tile8("ui", "dlg_tr", g.text_of(g.flip_h(c)))
    ART.tile8("ui", "dlg_bl", g.text_of(g.flip_v(c)))
    ART.tile8("ui", "dlg_br", g.text_of(g.flip_v(g.flip_h(c))))
    # item boxes (16x16): a frame with a letter, and what is in it
    def box16(letter_rows=None, inner=None):
        p = g.blank(16, 16, 0)
        for i in range(16):
            p[0][i] = p[15][i] = p[i][0] = p[i][15] = 3
        if inner is not None:
            p = g.overlay(p, inner, 2, 2)
        return p
    ART.meta("ui", "box_empty", box16(), bank=5)
    pala = g.blank(12, 12)
    for i in range(9):
        pala[1 + i][5 + i // 3] = 3
    for y in range(7, 11):
        for x in range(2, 8):
            pala[y][x] = 1
    ART.meta("ui", "item_pala", box16(None, pala), bank=5)
    sl = g.blank(12, 12)
    for i in range(8):
        sl[2 + i][2 + i] = 3
        sl[2 + i][9 - i] = 3
    ART.meta("ui", "item_tirachinas", box16(None, sl), bank=5)
    lt = g.blank(12, 12)
    for y in range(3, 10):
        for x in range(3, 9):
            lt[y][x] = 3 if y in (3, 9) or x in (3, 8) else 0
    ART.meta("ui", "item_linterna", box16(None, lt), bank=5)


def sprites_misc():
    ui8 = ART.sheet("UI8", 8, 8, bank=5)
    for n in ["heart_pickup", "cherry_pickup", "pinyol_pickup", "spark_0", "spark_1", "spark_2", "dust_0", "dust_1", "dust_2",
              "leaf_0", "leaf_1", "splash_0", "splash_1", "splash_2", "poof_0", "poof_1", "poof_2", "poof_3",
              "petal_0", "petal_1", "petal_2", "flame_0", "flame_1", "shot_pinyol", "dirt_clod", "arrow_right", "shadow"]:
        p = g.blank(8, 8)
        for i in range(2, 6):
            for j in range(2, 6):
                p[i][j] = 3 if i in (2, 5) or j in (2, 5) else 1
        ui8.add(n, p)
    items = ART.sheet("ITEMS16", 16, 16, bank=5)
    for n in ["pala", "tirachinas", "linterna", "llave_pequena", "llave_jefe", "mapa", "brujula", "pinyol_dorado",
              "pieza_corazon", "contenedor_corazon", "cereza_dorada"]:
        p = g.blank(16, 16)
        for i in range(3, 13):
            for j in range(3, 13):
                p[i][j] = 3 if i in (3, 12) or j in (3, 12) else 1
        items.add(n, p)


def monsters():
    mon = ART.sheet("MON", 16, 16, bank=3)
    base = g.pic("""
................
................
................
....33333333....
...3211111123...
..321000001123..
..321030301123..
..321111111123..
..3221111112233.
...3322222233...
....33.33.33....
................
................
................
................
................
""", 16, 16)
    for n in ["pulgon_0", "pulgon_1", "pulgon_2", "caracol_0", "caracol_1", "caracol_hide", "cuervo_0", "cuervo_1", "cuervo_2",
              "cuervo_swoop", "topo_mound", "topo_up_0", "topo_up_1", "topo_throw", "topo_hurt", "oruga_head_0", "oruga_head_1",
              "oruga_body_0", "oruga_body_1", "avispa_0", "avispa_1", "avispa_2", "moho_0", "moho_1", "moho_2", "escarabajo_0",
              "escarabajo_1", "escarabajo_shell", "murcielago_0", "murcielago_1", "murcielago_2"]:
        mon.add(n, g.shift(base, 0, 1) if n.endswith("_1") else base)


def props_boss():
    props = ART.sheet("PROPS", 16, 16, bank=6)
    blk = g.pic(["3333333333333333"] + ["3222222222222223"] * 14 + ["3333333333333333"], 16, 16)
    for n in ["block", "pot", "statue_a", "statue_b", "bed", "skull"]:
        props.add(n, blk)
    boss = ART.sheet("BOSS", 32, 32, bank=7)
    base = g.blank(32, 32)
    for y in range(6, 28):
        for x in range(4, 28):
            base[y][x] = 3 if y in (6, 27) or x in (4, 27) else 1
    for n in ["rey_idle", "rey_up_0", "rey_up_1", "rey_up_2", "rey_throw_0", "rey_throw_1", "rey_dizzy_0", "rey_dizzy_1", "rey_hurt",
              "rey_down_0", "rey_down_1", "rey_down_2", "rey_roar_0", "rey_roar_1", "rey_dead_0", "rey_dead_1", "rey_dead_2", "rey_dead_3",
              "gesc_0", "gesc_1", "gesc_charge_0", "gesc_charge_1", "gesc_stun_0", "gesc_stun_1", "gesc_hurt", "gesc_dead_0",
              "gesc_dead_1", "gesc_dead_2"]:
        boss.add(n, base)


def npcs():
    npc = ART.sheet("NPC", 16, 16, bank=1)
    for who in ["yaya", "higuera", "bellota", "nogal", "sardina", "espantajo", "mostaza", "aldeano_a", "aldeano_b"]:
        for n in ["down_0", "down_1", "up_0", "side_0", "side_1"]:
            npc.add(f"{who}_{n}", g.shift(HERO16, 0, 1) if n.endswith("_1") else HERO16)


def dungeon_tiles():
    for n, fl in [("door_open", ()), ("door_shut", ("solid",)), ("door_locked", ("solid", "lock")), ("pit", ("pit",)),
                  ("pit_filled", ()), ("eye_off", ("solid", "switch")), ("eye_on", ("solid",)), ("switch_plate", ("switch_floor",))]:
        ART.meta("overworld", n, g.pic(["0000000000000000"] * 16, 16, 16) if n in ("door_open", "pit_filled") else
                 g.pic(["3333333333333333"] + ["3222222222222223"] * 14 + ["3333333333333333"], 16, 16), flags=fl, bank=4)


def chest_tiles():
    chest = g.pic(["0000000000000000"] * 16, 16, 16)
    body = g.pic("""
................
................
................
................
..333333333333..
..322222222223..
..321111111123..
..333333333333..
..322222222223..
..322230032223..
..322222222223..
..333333333333..
................
................
................
................
""", 16, 16)
    ART.meta("overworld", "chest_closed", g.overlay(GRASS_A, body), flags=("solid", "chest"), bank=4)
    op = g.pic("""
................
................
..333333333333..
..320000000023..
..322222222223..
..333333333333..
..300000000003..
..300000000003..
..322222222223..
..333333333333..
................
................
................
................
................
................
""", 16, 16)
    ART.meta("overworld", "chest_open", g.overlay(GRASS_A, op), flags=("solid",), bank=4)
    patch = g.pic("""
................
................
................
................
................
....33333333....
...3222222223...
..322122212223..
..322222122223..
...3222222223...
....33333333....
................
................
................
................
................
""", 16, 16)
    ART.meta("overworld", "dirt_loose", g.overlay(GRASS_A, patch), flags=("dig", "becomes=hole_dug"), bank=1)
    ART.meta("overworld", "hole_dug", g.overlay(GRASS_A, g.pic("""
................
................
................
................
................
....3333333.....
...322222223....
..32333333323...
..32333333323...
...322222223....
....3333333.....
................
................
................
................
................
""", 16, 16)), bank=1)


_old_register = register


def register():
    _old_register()
    ui_tiles()
    sprites_misc()
    monsters()
    props_boss()
    npcs()
    chest_tiles()
    dungeon_tiles()
