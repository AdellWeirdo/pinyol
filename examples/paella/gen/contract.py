"""The names the game uses, as data: every sheet the art must provide (art/<name>.png + art/<name>.json), its frame size, its anchor and its frame names, written from
the briefs. gen/check_art.py checks the real art against it; gen/stub_art.py draws stand-ins from it so the engine can run before the art exists."""
from __future__ import annotations

CHEFS = ["estrella", "espuma", "pinche", "arrocero", "brioche", "crianza"]


def seq(prefix: str, n: int) -> list[str]:
    return [f"{prefix}_{i}" for i in range(n)]


def cat(*groups) -> list[str]:
    out: list[str] = []
    for g in groups:
        out += g if isinstance(g, list) else [g]
    return out


LEGS = cat(["idle"], seq("run", 8), seq("jump", 4), ["crouch"], seq("crawl", 6))
TORSO = cat(seq("idle", 4), seq("run", 8), seq("jump", 2), seq("crouch", 2), ["aim_fwd", "aim_up", "aim_down"], seq("fire_fwd", 3), seq("fire_up", 3), seq("fire_down", 3),
            seq("crouch_fire", 3), seq("throw", 4), seq("stab", 4), ["crouch_aim"])
FULL = cat(seq("hurt", 2), seq("die", 8), seq("win", 6), seq("select", 4))

# name: (frame w, frame h, anchor, frames)
SHEETS: dict[str, tuple[int, int, tuple[int, int], list[str]]] = {}
for c in CHEFS:
    SHEETS[f"chef_{c}_legs"] = (96, 72, (48, 14), LEGS)
    SHEETS[f"chef_{c}_torso"] = (128, 112, (64, 96), TORSO)
    SHEETS[f"chef_{c}_full"] = (128, 112, (64, 108), FULL)

SHEETS["gull_soldier"] = (112, 104, (56, 102), cat(seq("idle", 4), seq("walk", 8), seq("shoot", 4), seq("peck", 4), seq("hit", 2), seq("jump", 4), seq("die_a", 8), seq("die_b", 8), seq("surrender", 4)))
SHEETS["gull_bazooka"] = (112, 104, (56, 102), cat(seq("idle", 4), seq("aim", 3), seq("fire", 4), seq("reload", 4), seq("die", 8), seq("hit", 2)))
SHEETS["gull_drone"] = (128, 112, (64, 56), cat(seq("fly", 6), seq("drop", 4), seq("hit", 2), seq("die", 8)))
SHEETS["gull_kamikaze"] = (112, 96, (56, 48), cat(seq("idle", 4), seq("windup", 4), seq("dive", 4), seq("explode", 8), seq("hit", 2)))
SHEETS["crab_tank"] = (192, 128, (96, 126), cat(seq("idle", 4), seq("move", 8), seq("fire", 6), seq("hit", 2), seq("die", 10)))
POW = cat(seq("tied", 6), seq("free", 4), seq("give", 6), seq("run", 8), seq("salute", 4))
SHEETS["grandma"] = (96, 104, (48, 102), POW)
SHEETS["fisherman"] = (96, 104, (48, 102), POW)
FOODS = ["jamon", "cheese", "paella", "tortilla", "melon", "sardine", "orange", "bread", "olive_can", "wine_skin", "churro", "ensaimada"]
SHEETS["items"] = (48, 48, (24, 46), cat(seq("crate_a", 4), seq("crate_b", 4), seq("crate_c", 4), seq("ammo", 4), seq("heart", 4), seq("shield", 4), *[seq(f"food_{f}", 2) for f in FOODS]))
SHEETS["explosions"] = (192, 192, (96, 96), cat(seq("boom_s", 8), seq("boom_m", 10), seq("boom_l", 12), seq("boom_grenade", 10), seq("smoke", 8), seq("feathers", 8)))
SHEETS["shots"] = (40, 40, (20, 20), cat(seq("knife", 4), seq("foam", 4), seq("croqueta", 4), seq("rice", 4), seq("cream", 4), seq("cork", 4), seq("pot", 8), seq("pea", 4), seq("bomb", 4),
                                          seq("rocket", 4), seq("hit", 4)))
SHEETS["props"] = (128, 128, (64, 126), cat(seq("barrel", 6), seq("crate", 6), seq("buoy", 4)))
SHEETS["tractor"] = (224, 144, (112, 140), cat(seq("idle", 4), seq("drive", 8), seq("jump", 4), seq("crouch", 3), seq("fire", 4), seq("vulcan", 2), seq("cannon_up", 3), seq("cannon_down", 3),
                                               seq("hit", 2), seq("damaged_idle", 4), seq("burning", 6), seq("explode", 12), seq("enter", 6), seq("exit", 6)))
SHEETS["boss_body"] = (384, 320, (192, 300), cat(seq("idle", 6), seq("hurt", 2), seq("damaged", 3), seq("dead", 4)))
SHEETS["boss_head"] = (192, 160, (150, 120), cat(seq("idle", 4), seq("open", 4), seq("fire", 3), seq("hurt", 3), seq("laugh", 4), seq("dead", 4)))
SHEETS["boss_wing"] = (256, 192, (200, 40), cat(seq("rest", 4), seq("open", 4), seq("fire", 4), seq("hurt", 2), seq("broken", 2)))
SHEETS["boss_leg"] = (160, 192, (80, 20), cat(["stand"], seq("step", 8), seq("stomp", 4), seq("broken", 2)))
SHEETS["boss_pot"] = (224, 192, (112, 176), cat(["closed"], seq("opening", 6), seq("open", 4), seq("hit", 3), seq("cracked", 3), seq("destroyed", 4)))
SHEETS["boss_fx"] = (128, 128, (64, 64), cat(seq("charge", 6), seq("beam", 4), seq("spark", 4), seq("bolt", 4)))

# pictures that are not sprite rows: name: (w, h)
BACKGROUNDS = {}
for z in ("puerto", "calle", "playa"):
    BACKGROUNDS[f"far_{z}"] = (614, None)
    BACKGROUNDS[f"near_{z}_a"] = (960, 320)
    BACKGROUNDS[f"near_{z}_b"] = (960, 320)
BACKGROUNDS["arena_playa"] = (480, 320)
BACKGROUNDS["title"] = (480, 320)
BACKGROUNDS["select"] = (480, 320)
