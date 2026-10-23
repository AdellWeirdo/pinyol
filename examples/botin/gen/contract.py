"""The names the game uses, as data: what each artist must register (gen/check_art.py checks the real art against this) and what the stand-in art
(gen/stub_art.py) draws so the engine can be written and run while the art is made. Written from the briefs; keep them in step."""
from __future__ import annotations


def seq(prefix: str, n: int) -> list[str]:
    return [f"{prefix}_{i}" for i in range(n)]


def _many(*groups) -> list[str]:
    out: list[str] = []
    for g in groups:
        out += g if isinstance(g, list) else [g]
    return out


BIOMES = ["selva", "cristal", "galeon", "fragua"]

METAS_COMMON = _many(
    [f"ground_m{i}" for i in range(16)], [f"ground_alt{i}" for i in range(4)], ["ground_m1_b", "ground_m1_c"],
    ["ground_in_ne", "ground_in_nw", "ground_in_se", "ground_in_sw"], ["plat_l", "plat_m", "plat_r", "plat_s"],
    ["block_brown", "block_blue", "block_hard", "box_jewel", "box_coin", "spikes_up", "spikes_down"],
    [f"deco_{c}" for c in "abcdefgh"], [f"front_{c}" for c in "abcdefgh"], [f"back_{c}" for c in "abcd"],
)
METAS_EXTRA = {
    "selva": _many(["mud_top", "mud_fill", "spring_a", "spring_b", "tiki_block"], seq("waterfall", 4), seq("waterfall_top", 4),
                   ["vine_a", "vine_b", "leaf_plat_l", "leaf_plat_m", "leaf_plat_r"]),
    "cristal": _many(["crystal_a", "crystal_b", "crystal_c", "crystal_block", "lamp_off", "lamp_on", "glow_a", "glow_b"], seq("drip", 4),
                     ["ice_plat_l", "ice_plat_m", "ice_plat_r"]),
    "galeon": _many(["plank_a", "plank_b", "anchor_decor", "barrel", "cannon_decor", "seaweed_a", "seaweed_b", "seaweed_c"],
                    seq("current_l", 4), seq("current_r", 4), seq("current_u", 4), seq("vent", 4), seq("water_surface", 4),
                    ["water_fill", "ship_wall_a", "ship_wall_b"]),
    "fragua": _many(seq("lava_surface", 4), seq("lava_fill", 4), ["block_fire", "forge_pipe_a", "forge_pipe_b", "forge_pipe_c"], seq("gear", 4),
                    seq("steam", 4), ["anvil_decor", "magma_crack_a", "magma_crack_b", "chain_plat_l", "chain_plat_m", "chain_plat_r"]),
}
SCENERY = {b: [f"{b}_far", f"{b}_mid", f"{b}_near", f"{b}_agua"] for b in BIOMES}
SCENERY_SIZE = {"far": (256, 160), "mid": (256, 128), "near": (256, 96), "agua": (256, 160)}

HERO_FRAMES = _many(
    seq("idle", 6), seq("walk", 8), seq("run", 6), seq("ram", 4), ["jump_up", "jump_peak", "fall_0", "fall_1", "land_0", "land_1"],
    seq("smash", 3), seq("supersmash", 2), ["crouch"], seq("crawl", 6), seq("grab_idle", 2), seq("grab_walk", 6), seq("lift", 3), seq("throw", 4),
    seq("throw_up", 3), ["hurt_0", "hurt_1"], seq("die", 6), seq("swim_idle", 4), seq("swim", 8), seq("win", 6), seq("fire_run", 6), seq("puffy", 4),
    ["puffy_hurt"], seq("fat", 4), seq("fat_run", 4), seq("flat", 4), seq("flat_float", 2),
)

ENEMY16 = _many(
    [f"pelusa_{k}" for k in ("walk_0", "walk_1", "walk_2", "walk_3", "stun_0", "stun_1", "held_0", "held_1", "hurt")],
    [f"fogata_{k}" for k in ("idle_0", "idle_1", "idle_2", "idle_3", "angry_0", "angry_1", "angry_2", "hurt")],
    [f"gusanito_{k}" for k in ("walk_0", "walk_1", "walk_2", "walk_3", "stun_0", "stun_1", "held_0", "held_1", "hurt")],
    [f"bichito_{k}" for k in ("walk_0", "walk_1", "walk_2", "walk_3", "ball_0", "ball_1", "ball_2", "ball_3", "stun_0", "stun_1", "held_0", "held_1", "hurt")],
    seq("rock", 4), seq("coconut", 4), seq("bomb", 4),
)
ENEMY32 = _many(
    [f"serpiente_{k}" for k in ("idle_0", "idle_1", "idle_2", "idle_3", "strike_0", "strike_1", "strike_2", "stun_0", "stun_1", "held_0", "held_1", "hurt")],
    [f"mono_{k}" for k in ("idle_0", "idle_1", "idle_2", "idle_3", "throw_0", "throw_1", "throw_2", "throw_3", "stun_0", "stun_1", "held_0", "held_1", "hurt")],
    [f"murcielago_{k}" for k in ("fly_0", "fly_1", "fly_2", "fly_3", "fly_4", "fly_5", "hang_0", "hang_1", "swoop_0", "swoop_1", "swoop_2", "stun_0", "stun_1", "held_0", "held_1", "hurt")],
    [f"escarabajo_{k}" for k in ("walk_0", "walk_1", "walk_2", "walk_3", "shell_0", "shell_1", "shell_2", "stun_0", "stun_1", "held_0", "held_1", "hurt")],
    [f"pez_globo_{k}" for k in ("swim_0", "swim_1", "swim_2", "swim_3", "puff_0", "puff_1", "puff_2", "puff_3", "stun_0", "stun_1", "held_0", "held_1", "hurt")],
    [f"cangrejo_{k}" for k in ("walk_0", "walk_1", "walk_2", "walk_3", "claw_0", "claw_1", "claw_2", "stun_0", "stun_1", "held_0", "held_1", "hurt")],
    [f"medusa_{k}" for k in ("pulse_0", "pulse_1", "pulse_2", "pulse_3", "pulse_4", "pulse_5", "stun_0", "stun_1", "held_0", "held_1", "hurt")],
    [f"golem_chico_{k}" for k in ("walk_0", "walk_1", "walk_2", "walk_3", "smash_0", "smash_1", "smash_2", "smash_3", "stun_0", "stun_1", "held_0", "held_1", "hurt")],
)
BOSS64 = _many(seq("torso", 3), ["torso_hurt"], seq("torso_crack", 3))
BOSS32 = _many(seq("head_idle", 4), seq("head_laugh", 2), seq("head_open", 2), seq("head_hurt", 3), seq("head_dead", 4), ["fist_open", "fist_closed"], seq("fist_slam", 2),
               ["arm_a", "arm_b"], seq("shield", 2), seq("debris", 4), seq("egg", 4), seq("duck", 4), seq("lips", 2))

ITEMS16 = _many(*[seq(p, 6) for p in ("coin_s", "coin_m", "coin_l", "gem_a", "gem_b", "diamond")], seq("heart_item", 4), seq("heart_small", 4),
                *[seq(f"jewel_{i}", 4) for i in range(1, 5)], [f"jewel_ghost_{i}" for i in range(1, 5)], ["chest_closed"], seq("chest_open", 3), seq("bag", 4),
                seq("key", 4), seq("carry_rock", 4), seq("crate", 2))
ITEMS32 = _many(seq("keyzer", 6), seq("keyzer_flee", 4), seq("frog_off", 2), seq("frog_hit", 3), seq("frog_on", 4), seq("vortex_open", 8), seq("vortex_close", 6),
                seq("vortex_closed", 2), seq("treasure", 4))
UI8 = _many([f"d_{i}" for i in range(10)], ["x", "slash", "colon", "dot", "heart_mini_full", "heart_mini_empty", "coin_mini"],
            [f"jewel_mini_empty_{i}" for i in range(1, 5)], [f"jewel_mini_full_{i}" for i in range(1, 5)], ["key_mini", "clock_mini"])
UI16 = _many(seq("heart_full", 2), ["heart_empty"], seq("heart_break", 3), ["crown_gold", "crown_silver", "crown_bronze"], seq("frog_alarm", 4), seq("arrow_right", 3), seq("skull", 2))
FX8 = _many(*[seq(p, 4) for p in ("star_stun", "dust", "spark", "smoke", "bubble", "debris", "coin_spark", "ember")])
FX16 = _many(seq("impact", 4), seq("smash", 4), seq("explode", 6), seq("flame", 6), seq("splash", 4), seq("ripple", 4), seq("speed", 3), seq("poof", 4), seq("sparkle", 6), seq("hit", 3))
MAPA16 = _many(seq("node_idle", 4), seq("node_done", 4), ["node_locked"], seq("node_boss", 4), seq("token", 6), seq("arrow_up", 3), seq("arrow_down", 3))

SHEETS = {"HERO": (32, 32, HERO_FRAMES), "ENEMY16": (16, 16, ENEMY16), "ENEMY32": (32, 32, ENEMY32), "BOSS64": (64, 64, BOSS64), "BOSS32": (32, 32, BOSS32),
          "ITEMS16": (16, 16, ITEMS16), "ITEMS32": (32, 32, ITEMS32), "UI8": (8, 8, UI8), "UI16": (16, 16, UI16), "FX8": (8, 8, FX8), "FX16": (16, 16, FX16),
          "MAPA16": (16, 16, MAPA16)}
TITULO_SCENERY = {"titulo_logo": (160, 48), "titulo_fondo": (256, 160), "mapa_fondo": (256, 160)}
OBJ_BANKS = ["zurron", "zurron_fuego", "zurron_golpe", "zurron_hinchado", "enemigo_a", "enemigo_b", "enemigo_c", "enemigo_d", "jefe_a", "jefe_b",
             "objetos", "joyas", "ui", "fx", "mapa", "extra"]


def metas_of(biome: str) -> list[str]:
    return METAS_COMMON + METAS_EXTRA[biome]
