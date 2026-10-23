"""The insides: Yaya's house (where the game begins), Tío Nogal's shop, the mayor's house, Bellota's treehouse (tileset "interior") and the
secret grotto in the northern forest (tileset "dungeon"). Each is one screen of 15 x 9 metatiles: the back wall is row 0, the side walls are
columns 0 and 14, the front wall row 8 with the door at (7, 8)."""
from __future__ import annotations

from world import Area, Canvas, STAMPS, block

STAMPS.update({
    "ibed": [["ibed_tl", "ibed_tr"], ["ibed_bl", "ibed_br"]], "itable": [["itable_l", "itable_r"]],
    "ishelf": [["ishelf_l", "ishelf_r"]], "ibook": [["ibookshelf_a", "ibookshelf_b"]], "idesk": [["idesk_l", "idesk_r"]],
    "icounter": [["icounter_l"] + ["icounter_m"] * 6 + ["icounter_r"]], "ishop": [["ishop_shelf_a", "ishop_shelf_b"]],
    "irug": block("irug", 3, 3) if False else [["irug_tl", "irug_t", "irug_tr"], ["irug_l", "irug_c", "irug_r"], ["irug_bl", "irug_b", "irug_br"]],
    "ifire": [["ifireplace_l", "ifireplace_r"]],
})

LEG = {
    ".": ["ifloor_wood_a", "ifloor_wood_b", "ifloor_wood_c"], ",": ["ifloor_stone_a", "ifloor_stone_b"], ";": ["ifloor_tile_a", "ifloor_tile_b"],
    "=": ["iwall_n_a", "iwall_n_b"], "W": "iwall_n_window", "K": "iwall_n_clock", "Q": "iwall_n_map", "J": "iwall_n_shelf",
    "[": "iwall_w", "]": "iwall_e", "_": "iwall_s", "7": "iwall_nw", "9": "iwall_ne", "3": "iwall_sw", "5": "iwall_se", "D": "idoor",
    "p": "iplant_a", "P": "iplant_b", "b": "ibarrel", "c": "icrate", "s": "istove", "u": "icupboard", "t": "itoys", "q": "ichest_closed",
    "l": "iladder", "m": "imap_table",
}

# the shop's floor is tiles: its loose pieces are the "_tile" versions that carry that floor
LEG_TILE = {**LEG, "p": "iplant_a_tile", "P": "iplant_b_tile", "b": "ibarrel_tile", "c": "icrate_tile", "t": "itoys_tile"}

SW, SH = 15, 9


def frame(floor=".", back=None, seed=1) -> Canvas:
    c = Canvas(floor, seed=seed)
    c.hline(0, 1, 13, "=").hline(8, 1, 13, "_").vline(0, 1, 7, "[").vline(14, 1, 7, "]")
    c.put(0, 0, "7").put(14, 0, "9").put(0, 8, "3").put(14, 8, "5").put(7, 8, "D")
    for x, ch in (back or {}).items():
        c.put(x, 0, ch)
    return c


# ---------------------------------------------------------------- Yaya's house: the game begins here
CY = Area("casa_yaya", "interior", 1, 1, LEG)
CY.notes.update({"music": "house", "bed_out": (3, 3), "bed_pillow": (1, 1), "yaya_talk": (6, 5), "name": "Casa de Yaya"})
c = frame(".", {3: "W", 7: "K", 11: "W"}, seed=2)
c.put(13, 1, "p").put(13, 6, "b").put(1, 6, "c").put(1, 7, "c").scatter("t", 1, salt=2)
CY.screen(0, 0, c.rows())
CY.stamp("ibed", 1, 1)
STAMPS["istove_cell"] = [["istove_wood"]]
CY.stamp("istove_cell", 11, 1)
CY.stamp("ishelf", 9, 1)
CY.stamp("itable", 6, 4)
CY.stamp("irug", 5, 5)
CY.thing("exit", 7, 8, to="overworld", tx=2, ty=13, face="down")
CY.thing("npc", 9, 5, id="yaya", face="left", knot="yaya_casa")
CY.thing("sign", 1, 2, text="cama")

# ---------------------------------------------------------------- Tío Nogal's shop
TI = Area("tienda", "interior", 1, 1, LEG_TILE)
TI.notes.update({"music": "shop", "name": "Tienda"})
c = frame(";", {3: "W", 11: "W"}, seed=3)
c.put(1, 1, "b").put(13, 1, "b").put(1, 6, "c").put(13, 6, "c").put(13, 7, "b").put(2, 7, "p")
TI.screen(0, 0, c.rows())
TI.stamp("ishop", 3, 1)
TI.stamp("ishop", 9, 1)
TI.stamp("icounter", 3, 4)
TI.thing("exit", 7, 8, to="overworld", tx=32, ty=13, face="down")
TI.thing("npc", 6, 3, id="nogal", face="down", reach=20)

# ---------------------------------------------------------------- the mayor's house
CH = Area("casa_higuera", "interior", 1, 1, LEG)
CH.notes.update({"music": "house", "name": "Casa de Doña Higuera"})
c = frame(".", {7: "Q", 3: "W", 11: "W"}, seed=4)
c.put(1, 6, "p").put(13, 6, "p").put(6, 4, "m")
CH.screen(0, 0, c.rows())
CH.stamp("ibook", 1, 1)
CH.stamp("ibook", 12, 1)
CH.stamp("idesk", 6, 2)
CH.stamp("irug", 5, 5)
CH.thing("exit", 7, 8, to="overworld", tx=37, ty=13, face="down")
CH.thing("sign", 1, 1, text="libro")
CH.thing("npc", 10, 4, id="aldeano_a", face="left")

# ---------------------------------------------------------------- Bellota's treehouse
CA = Area("casa_arbol", "interior", 1, 1, LEG)
CA.notes.update({"music": "house", "name": "La casa del árbol"})
c = frame(".", {5: "W", 9: "W"}, seed=5)
c.put(2, 2, "t").put(3, 5, "t").put(12, 6, "t").put(12, 2, "c").put(1, 6, "b")
CA.screen(0, 0, c.rows())
CA.stamp("itable", 10, 4)
CA.stamp("irug", 5, 4)
CA.thing("exit", 7, 8, to="overworld", tx=6, ty=3, face="down")
CA.thing("npc", 7, 3, id="bellota", face="down", knot="bellota_arbol")

# ---------------------------------------------------------------- the secret grotto (the dungeon's tiles)
GR = Area("cueva_secreta", "dungeon", 1, 1, {
    ".": ["floor_a", "floor_b", "floor_c"], "=": ["wall_n_a", "wall_n_b"], "_": ["wall_s_a", "wall_s_b"], "[": ["wall_w_a", "wall_w_b"],
    "]": ["wall_e_a", "wall_e_b"], "7": "wall_nw", "9": "wall_ne", "3": "wall_sw", "5": "wall_se", "D": "stairs_exit", "T": "torch_lit_a",
    "c": "chest_closed", "m": "mushroom_a", "S": "statue_a", "r": "roots_a", "u": "mushroom_b",
})
GR.notes.update({"music": "raiz", "name": "Una cueva escondida"})
c = Canvas(".", seed=6)
c.hline(0, 1, 13, "=").hline(8, 1, 13, "_").vline(0, 1, 7, "[").vline(14, 1, 7, "]")
c.put(0, 0, "7").put(14, 0, "9").put(0, 8, "3").put(14, 8, "5").put(7, 8, "D")
c.put(5, 1, "T").put(9, 1, "T").put(7, 2, "c").put(3, 3, "m").put(11, 3, "u").put(3, 6, "r").put(11, 6, "r").put(6, 2, "S").put(8, 2, "S")
GR.screen(0, 0, c.rows())
GR.thing("exit", 7, 8, to="overworld", tx=3, ty=7, face="down")
GR.thing("chest", 7, 2, item="pieza_corazon", flag="heart_grotto")
GR.thing("sign", 7, 4, text="cueva_secreta")

AREAS = [CY, TI, CH, CA, GR]
