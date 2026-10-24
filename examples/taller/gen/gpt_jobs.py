"""What was asked of the image model (gpt-image through the codex bridge) to make the art of Taller de los Autómatas: one canonical picture of each character, then sheets of
animation frames made WITH that picture as the only reference. Every character ends in 15 colours (a CPS2 sprite's palette).

    python3 gen/gpt_run.py refs                 # the canonical pictures
    python3 gen/gpt_run.py sheets char [id ..]  # the animation sheets (resumes: what exists is not asked again)
    python3 gen/gpt_run.py sheets obj [id ..]   # pickups, props, effects
    python3 gen/gpt_make.py char | obj          # raw sheets -> art/<id>.png + .json"""
from __future__ import annotations

STYLE = ("Mid-1990s Capcom CPS2 arcade sprite art (Armored Warriors, Battle Circuit, Darkstalkers): hand-pixelled, bold dark outline, cel shading with 3 to 4 tones per material, "
         "only about 15 colours in total, anime-influenced proportions, saturated clean colours, crisp pixel edges, no anti-aliasing blur. World: a Victorian city of clockmakers, "
         "all brass, gears, springs, copper and steam, 1890.")
FLAT = "Plain flat transparent background, no ground, no shadow, no text, no labels, no numbers."
SHEET = ("exactly the same character and art style as the reference image. A SPRITE SHEET: all frames in ONE horizontal row, left to right, evenly spaced with wide empty gaps "
         "between them, every frame the same scale as the reference, the feet of every frame on the same baseline, facing right. " + FLAT)
OBJ = ("A SPRITE SHEET of separate objects: all the pictures in ONE horizontal row, left to right, evenly spaced with wide empty gaps between them, every one the same scale, in "
       "the same art style as the reference. " + FLAT)

# the heroes: three clockmakers in clockwork exo-frames (their exo-piece changes what they can do)
HEROES = {
    "vera": {"look": ("VERA, a young inventor clockmaker woman, short messy hair under brass goggles, a leather apron over a teal work jacket, a big brass clockwork EXO-ARM on her "
                      "right side with a wrench-shaped fist and exposed gears, a fierce confident grin; a balanced fighter"),
             "special": "a SPINNING WHIRLWIND with her wrench exo-arm held out, spinning her whole body three times with a ring of sparks and gears flying off",
             "hit": "punching with the wrench fist"},
    "tomas": {"look": ("TOMAS, a huge old bearded master clockmaker, bald with a white beard, enormous shoulders, a red waistcoat and rolled sleeves, a heavy steam-powered EXO-ARM "
                       "ending in a giant hammer fist, a jeweller's loupe on his brow; a slow, powerful bruiser"),
              "special": "a GROUND-POUND: he raises the hammer fist high over his head, slams it into the floor with a shock ring of dust and steam spreading out",
              "hit": "punching with the giant hammer fist"},
    "mina": {"look": ("MINA, a lean agile teenage clockmaker apprentice, a long BLACK ponytail with a bright green ribbon, dark skin, a mustard vest and short trousers, clockwork spring-loaded EXO-LEGS with coiled "
                      "springs and brass shin plates, a cheeky smirk; a fast acrobatic fighter"),
             "special": "a FLYING DRILL KICK: she coils the springs, launches up and forward spinning with one foot out like a drill, and lands in a skid",
             "hit": "kicking and punching quickly"},
}
HERO_FRAME, HERO_ANCHOR, HERO_H = (256, 240), (128, 196), 124

# name: (frames, what, frame names, index of the frame that sets the sheet's scale)
HERO_SHEETS = {
    "idle": (5, "four frames of a lively FIGHTING IDLE loop (bouncing on the toes, breathing, the exo-piece ticking and steaming) and then one frame getting HIT (recoil, eyes shut)",
             ["idle_0", "idle_1", "idle_2", "idle_3", "hurt_0"], 0),
    "walk": (6, "a six-frame WALK cycle, confident, the fists up", ["walk_0", "walk_1", "walk_2", "walk_3", "walk_4", "walk_5"], 0),
    "punch": (6, "six frames of a three-hit COMBO, two frames each (wind-up and impact): a jab, a second strike with the other side, and a big finisher; {hit}",
              ["atk_0", "atk_1", "atk_2", "atk_3", "atk_4", "atk_5"], 0),
    "air": (5, "five frames: JUMPING rising, the jump peak (tucked), falling, and two frames of a JUMP ATTACK (a flying kick, then the follow-through)",
            ["jump_0", "jump_1", "jump_2", "jumpatk_0", "jumpatk_1"], None),
    "special": (6, "six frames of the SIGNATURE SPECIAL MOVE: {special}", ["special_0", "special_1", "special_2", "special_3", "special_4", "special_5"], 0),
    "grab": (5, "five frames: GRABBING an enemy by the collar, holding him up, and a THROW over the shoulder (wind-up, release, follow-through); the enemy is not drawn, just the hero's pose with empty hands",
             ["grab_0", "grab_1", "throw_0", "throw_1", "throw_2"], 0),
    "down": (6, "six frames of being KNOCKED DOWN: flying back, hitting the floor, lying flat on the back dazed, then getting up in three frames (a push-up, a crouch, standing ready)",
             ["fall_0", "fall_1", "lie_0", "getup_0", "getup_1", "getup_2"], None),
    "win": (4, "four frames: a VICTORY pose (arms up, a cheer, a wink, hands on hips, chin up) for the end of a stage and the character select screen",
            ["win_0", "win_1", "win_2", "select_0"], 3),
}

# the enemies and the boss: autómatas
AUTO = ("a rebel clockwork automaton: riveted copper and brass plates, visible cog wheels and springs, a wind-up key in its back, glowing yellow lamp eyes, tough, comic and a bit stupid")
CHARS: dict = {}
for hid, h in HEROES.items():
    CHARS[hid] = {
        "ref": h["look"] + ". Full body, side view facing RIGHT, a dynamic fighting idle stance, about 124 pixels tall in the game. " + STYLE + " " + FLAT,
        "frame": HERO_FRAME, "anchor": HERO_ANCHOR, "height": HERO_H, "faces": "right",
        "sheets": [(n, c, w.format(special=h["special"], hit=h["hit"]), names, kf) for n, (c, w, names, kf) in HERO_SHEETS.items()],
    }

CHARS["rodete"] = {
    "ref": ("RODETE, " + AUTO + ": a stocky humanoid with a round tin-bucket head with two lamp eyes and a grilled mouth, big gloved pipe fists; the basic street thug. Full body, side view "
            "facing RIGHT, fists up, about 116 pixels tall in the game. " + STYLE + " " + FLAT),
    "frame": (256, 196), "anchor": (128, 156), "height": 116, "faces": "right",
    "sheets": [
        ("move", 6, "six frames: two of an IDLE loop (swaying, the key turning) and a four-frame heavy WALK cycle", ["idle_0", "idle_1", "walk_0", "walk_1", "walk_2", "walk_3"], 0),
        ("fight", 5, "three frames of a big PUNCH (wind-up, impact, recovery) and two frames of getting HIT (recoil, sparks)", ["atk_0", "atk_1", "atk_2", "hurt_0", "hurt_1"], 0),
        ("die", 6, "six frames of a COMIC DEFEAT, no blood: knocked flat on its back, lying with a dizzy spinning eye, then bursting in a pop of gears, springs and a flying bucket head", ["fall_0", "fall_1", "lie_0", "die_0", "die_1", "die_2"], None),
    ],
}
CHARS["resorte"] = {
    "ref": ("RESORTE, " + AUTO + ": a thin bouncy one with huge coiled springs for legs, a small head like a bell with a bowler hat, long wiry arms with scissor hands, a manic grin; a jumping "
            "enemy that pounces from above. Full body, side view facing RIGHT, crouched on its springs, about 112 pixels tall in the game. " + STYLE + " " + FLAT),
    "frame": (256, 196), "anchor": (128, 156), "height": 112, "faces": "right",
    "sheets": [
        ("move", 6, "six frames: two of an IDLE loop (bouncing on the springs) and a four-frame HOP cycle forward (crouch, launch, in the air, land)", ["idle_0", "idle_1", "hop_0", "hop_1", "hop_2", "hop_3"], 0),
        ("fight", 5, "three frames of a POUNCE attack (coiling down on its springs, leaping forward with the scissor hands out, landing in a crouch) and two frames of getting HIT (recoiling, standing at its normal height) Draw ONLY the character, every frame at exactly the SAME size and scale as the reference, standing on the same ground line; NO smoke or steam clouds, NO dust, NO motion lines, NO swoosh, NO shock rings, NO sparks around it.", ["atk_0", "atk_1", "atk_2", "hurt_0", "hurt_1"], 3),
        ("die", 6, "six frames of a COMIC DEFEAT, no blood: knocked flat, lying with the springs twitching, then boing, springs flying everywhere in a pop", ["fall_0", "fall_1", "lie_0", "die_0", "die_1", "die_2"], None),
    ],
}
CHARS["caldero"] = {
    "ref": ("CALDERO, " + AUTO + ": a huge round-bellied heavy built around a riveted steam boiler with a pressure gauge, a stovepipe chimney on its head letting out steam, tiny legs "
            "and enormous arms with piston fists, a furious scowl; the slow mid-boss bruiser. Full body, side view facing RIGHT, about 150 pixels tall in the game. " + STYLE + " " + FLAT),
    "frame": (288, 248), "anchor": (144, 204), "height": 150, "faces": "right",
    "sheets": [
        ("move", 6, "six frames: two of an IDLE loop (steam puffing from the chimney, the gauge needle shaking) and a four-frame slow heavy WALK cycle", ["idle_0", "idle_1", "walk_0", "walk_1", "walk_2", "walk_3"], 0),
        ("fight", 6, "four frames of a SLAM attack (both fists raised high over its head, the fists coming down, both fists planted on the ground with the body bent over them, standing back up) and two frames of getting HIT (recoiling, leaning back) Draw ONLY the character, every frame at exactly the SAME size and scale as the reference, standing on the same ground line; NO smoke or steam clouds, NO dust, NO motion lines, NO swoosh, NO shock rings, NO sparks around it.", ["atk_0", "atk_1", "atk_2", "atk_3", "hurt_0", "hurt_1"], 0),
        ("die", 6, "six frames of a COMIC DEFEAT, no blood: staggering back, falling backwards, lying flat on its back dazed, then the boiler swelling, bursting apart into a few separate big plates and pipes, ending as a low heap of plates and pipes lying on the ground Draw ONLY the character, every frame at exactly the SAME size and scale as the reference, standing on the same ground line; NO smoke or steam clouds, NO dust, NO motion lines, NO swoosh, NO shock rings, NO sparks around it.", ["fall_0", "fall_1", "lie_0", "die_0", "die_1", "die_2"], None),
    ],
}
CHARS["pendulo"] = {
    "ref": ("PENDULO, the final boss: a towering grandfather-clock golem, its body a tall dark-wood clock case with a glowing round clock-face for a chest and a pendulum swinging behind a glass "
            "door, huge iron arms with brass gear shoulders, a crown of bells on its head, chains hanging, glowing red clock-hands as angry eyebrows, a wind-up key on its back. Full body, side "
            "view facing RIGHT, about 210 pixels tall in the game. " + STYLE + " " + FLAT),
    "frame": (384, 340), "anchor": (192, 296), "height": 210, "faces": "right",
    "sheets": [
        ("move", 6, "six frames: three of an IDLE loop (the pendulum swinging in the chest, the bells chiming, steam) and a three-frame heavy WALK", ["idle_0", "idle_1", "idle_2", "walk_0", "walk_1", "walk_2"], 0),
        ("swing", 6, "six frames: three of a huge SWEEPING ARM swing (wind-up, the arm sweeping across, follow-through; NO motion-blur streaks, NO swoosh arcs, NO trails, just the posed arm) and three of the bells ringing with simple concentric shock rings drawn as solid yellow arcs", ["swing_0", "swing_1", "swing_2", "chime_0", "chime_1", "chime_2"], 0),
        ("slam", 4, "four frames of a JUMP SLAM: crouching, leaping up, crashing down with both iron fists and a burst of debris and gears, recovery", ["slam_0", "slam_1", "slam_2", "slam_3"], 3),
        ("hit", 4, "two frames of getting HIT (the glass cracks, sparks) and two frames of an ENRAGED idle (the clock-face glowing red, the hands spinning, steam from the seams)", ["hurt_0", "hurt_1", "rage_0", "rage_1"], 0),
        ("die", 6, "six frames of a COMIC DEFEAT, no blood: staggering, the chest glass shattering and the pendulum flying out, bells ringing wildly, the clock striking a last time and collapsing into a heap of wood, gears and bells", ["fall_0", "fall_1", "die_0", "die_1", "die_2", "die_3"], None),
    ],
}

OBJECTS = {
    "parts": {
        "frame": (56, 56), "anchor": (28, 52),
        "sheets": [("a", 6, "six pickup items floating, each with a soft glow: a brass hammer-fist exo-arm, a pair of coiled spring exo-legs, a wrench-fist exo-arm, a steam-boiler exo-chest, a "
                           "little oil can (health), a pocket watch (a score bonus)", ["part_hammer", "part_springs", "part_wrench", "part_boiler", "oil", "watch"])],
    },
    "props_a": {
        "frame": (160, 192), "anchor": (80, 188),
        "sheets": [("a", 6, "six breakable street props standing: a wooden barrel with brass hoops, a crate of gears, a gas street lamp, a stack of three small clock cases, a mailbox, a pile of copper pipes",
                    ["barrel", "crate", "lamp", "clocks", "mailbox", "pipes"])],
    },
    "props_b": {
        "frame": (160, 192), "anchor": (80, 188),
        "sheets": [("a", 6, "the same six street props BROKEN into debris heaps: splintered barrel staves with hoops, a crate burst open with gears spilling, a bent gas lamp lying down, "
                           "smashed clock cases with springs, a dented mailbox with letters, bent copper pipes", ["barrel_b", "crate_b", "lamp_b", "clocks_b", "mailbox_b", "pipes_b"])],
    },
    "fx_a": {
        "frame": (128, 128), "anchor": (64, 64),
        "sheets": [("a", 6, "six FRAMES of hit effects: three frames of a bright yellow-white HIT SPARK burst growing, and three frames of a cloud of STEAM puffing and fading", ["hit_0", "hit_1", "hit_2", "steam_0", "steam_1", "steam_2"]),
                   ("b", 6, "six frames: three frames of a burst of flying brass GEARS and screws, and three frames of a rising ring of dust", ["gears_0", "gears_1", "gears_2", "dust_0", "dust_1", "dust_2"])],
    },
    "fx_b": {
        "frame": (192, 192), "anchor": (96, 96),
        "sheets": [("a", 6, "a six-frame EXPLOSION animation: a chunky fireball of orange and yellow with flying gears and springs, growing then cooling into smoke. ONLY the explosion, no characters", ["boom_0", "boom_1", "boom_2", "boom_3", "boom_4", "boom_5"])],
    },
}
