"""What was asked of the image model (gpt-image through the codex bridge) to make the characters, the enemies and the objects of Paella de combate: one canonical picture
of each character, then sheets of animation frames made WITH that picture as the only reference (so the character stays the same). The pictures of the backgrounds
set the style (a 480x280 crop of one is the style reference of every first picture).

    python3 gen/gpt_run.py refs            # the canonical pictures
    python3 gen/gpt_run.py sheets chef     # then the animation sheets of the chefs (resumes: what exists is not asked again)

Raw generations go to RAW_DIR (not in the repository); gen/gpt_make.py turns them into frames."""
from __future__ import annotations

STYLE = ("Metal Slug (SNK Neo Geo, 1996) hand-drawn 2D game sprite art: thick dark warm-brown outlines (never black), 3-tone cel shading with a rim light, saturated warm "
         "Mediterranean palette, clean readable shapes, expressive funny face, exaggerated proportions, hard pixel-art-like edges, no anti-aliasing blur.")
FLAT = "Plain flat transparent background, no ground, no shadow, no text, no labels, no numbers."
SHEET = ("exactly the same character and art style as the reference image. A SPRITE SHEET: all frames in ONE horizontal row, left to right, evenly spaced with wide empty gaps "
         "between them, every frame the same scale as the reference, the feet of every frame on the same baseline, facing right. " + FLAT)

CHEFS = {
    "estrella": {
        "ref": None,  # made in the pilot (raw/estrella_ref.png)
        "weapon": "a throwing kitchen knife", "fire": "throwing a kitchen knife forward",
        "die": "she spins backwards and her toque flies off and lands upright on her chest",
    },
    "espuma": {
        "ref": ("A wiry excitable mad-scientist chef: huge wild frizzy hair under a half-tilted short toque, round brass goggles pushed up on his forehead, a lab coat over a chef's "
                "jacket, a backpack of siphon tanks and tubes, holding a whipped-cream foam siphon like a gun, a manic grin. Full body, side view facing right, standing idle, about 90 pixels tall in the game."),
        "weapon": "a foam siphon", "fire": "spraying white foam forward from the siphon",
        "die": "he flashes twice as an X-ray skeleton, is charred with frizzy smoking hair, then falls flat on his face",
    },
    "pinche": {
        "ref": ("A very big jovial man, twice as wide as a normal person: black beret, enormous smile, round belly in a blue-and-white striped apron, rolled-up sleeves, holding a big frying pan "
                "with golden croquettes in it. Full body, side view facing right, standing idle, about 95 pixels tall in the game."),
        "weapon": "a frying pan with croquettes", "fire": "flinging a golden croquette forward out of the frying pan",
        "die": "he is flattened into a pancake (pan and all), pops back up dizzy, then flops onto his back with his beret on his belly",
    },
    "arrocero": {
        "ref": ("An old, proud, grumpy rice master: grey handlebar moustache, straw hat, red sash, espadrilles, a huge paella pan strapped on his back like a shield, holding a long wooden "
                "ladle. Full body, side view facing right, standing idle, about 90 pixels tall in the game."),
        "weapon": "a long wooden ladle", "fire": "flinging rice and hot oil forward with the ladle",
        "die": "his eyes spin, he sets his paella pan on the floor, sways and faints face first into it",
    },
    "brioche": {
        "ref": ("A round, sweet, fierce pastry chef woman in a pink uniform with a frilly cap and a big pink bow, a white apron, holding a whipped-cream piping gun, a sweet but dangerous smile. "
                "Full body, side view facing right, standing idle, about 85 pixels tall in the game."),
        "weapon": "a whipped-cream piping gun", "fire": "spraying a stream of whipped cream forward",
        "die": "she is covered in cream, slips, slides away on her back and a cherry lands on the cream pile",
    },
    "crianza": {
        "ref": ("A tall thin snooty sommelier: black tailcoat and bow tie, a tastevin medal on a chain, a white napkin over his arm, a pointy nose, holding a bottle of cava like a gun. "
                "Full body, side view facing right, standing idle, about 92 pixels tall in the game."),
        "weapon": "a bottle of cava", "fire": "popping a cork out of the cava bottle forward with a puff of fizz",
        "die": "he takes a cork in the eye, staggers, kneels while the bottle gushes foam, then lies spouting foam",
    },
}

# name: (frames in the sheet, what the frames are, the frames' names in order, index of the frame that sets the sheet's scale, its body height in px)
SHEETS = {
    "idle": (5, "four frames of a lively IDLE loop (breathing, small weight shifts, a blink, {weapon} held ready) and then one frame getting HIT (recoil, eyes shut)",
             ["idle_0", "idle_1", "idle_2", "idle_3", "hurt_0"], 0, 90),
    "run": (6, "a six-frame fast RUN CYCLE, energetic, leaning forward, arms pumping, {weapon} in hand",
            ["run_0", "run_1", "run_2", "run_3", "run_4", "run_5"], 0, 90),
    "runfire": (6, "four frames of a RUN-AND-SHOOT cycle (running while {fire}, the arm with {weapon} held straight out in front) and then two frames STANDING still {fire} (aim, then recoil)",
                ["runfire_0", "runfire_1", "runfire_2", "runfire_3", "fire_0", "fire_1"], 4, 90),
    "air": (5, "five frames in the air: jumping rising (knees tucked), the jump peak, falling (legs dangling), and then two frames JUMPING while {fire}",
            ["jump_0", "jump_1", "jump_2", "jumpfire_0", "jumpfire_1"], 1, 90),
    "aim": (5, "five frames: standing and {fire_up} straight UP at the sky twice (aim and recoil), then jumping with the body leaning forward {fire_down} straight DOWN twice, and one frame holding {weapon} aimed straight up",
            ["fire_up_0", "fire_up_1", "fire_down_0", "fire_down_1", "aim_up_0"], 0, 90),
    "crouch": (5, "five frames: first CROUCHING low behind the weapon (idle crouch), then two frames crouching and {fire}, then two frames CRAWLING forward low to the ground (two phases of the crawl)",
               ["crouch_0", "crouch_fire_0", "crouch_fire_1", "crawl_0", "crawl_1"], None, 90),
    "act": (6, "six frames: a GRENADE THROW of a round steel pressure-cooker pot (wind-up holding the pot behind the head, the throw, follow-through), then a quick STAB forward with a big carving knife (wind-up, the stab, recover)",
            ["throw_0", "throw_1", "throw_2", "stab_0", "stab_1", "stab_2"], 0, 90),
    "die": (6, "six frames of a COMIC DEATH, no blood: {die}; the last frame is a lying gag pose that stays",
            ["die_0", "die_1", "die_2", "die_3", "die_4", "die_5"], None, 90),
    "win": (6, "six frames: four frames of a VICTORY dance with {weapon} held high (a loop), then two frames of a big-attitude pose for a character-select screen (hands on hips, chin up, a wink)",
            ["win_0", "win_1", "win_2", "win_3", "select_0", "select_1"], 0, 90),
}

CHEF_FRAME = (176, 120)   # the size of a chef's frame in the game; feet at row 116, the body centred on column 88
CHEF_ANCHOR = (88, 116)


def ref_prompt(chef: str) -> str:
    return CHEFS[chef]["ref"] + " " + STYLE + " " + FLAT


def sheet_prompt(chef: str, sheet: str) -> str:
    n, what, _, _, _ = SHEETS[sheet]
    c = CHEFS[chef]
    what = what.format(weapon=c["weapon"], fire=c["fire"], fire_up=c["fire"].replace("forward", "straight up"), fire_down=c["fire"].replace("forward", "straight down"), die=c["die"])
    return f"{n} frames of this character: {what}. " + STYLE + " " + SHEET


# ---------------------------------------------------------------------------------------------------------------------------- enemies, allies, objects
# id: {"ref": the canonical picture's prompt, "frame": (w, h), "anchor": (x, y), "height": body height in px, "faces": "left"|"right",
#      "sheets": [(sheet name, frames in it, what they show, [frame names], index of the scale frame)]}
LEFT = ("exactly the same character and art style as the reference image, facing LEFT. A SPRITE SHEET: all frames in ONE horizontal row, left to right, evenly spaced with wide empty gaps "
        "between them, every frame the same scale as the reference, the feet of every frame on the same baseline. " + FLAT)
OBJ = ("A SPRITE SHEET of separate objects: all the pictures in ONE horizontal row, left to right, evenly spaced with wide empty gaps between them, every one the same scale, in the same art style as the reference. " + FLAT)

GULL = ("a mechanical seagull: white enamel belly and chrome-grey wings with black tips, a red visor eye with a mean yellow glint, a brass cannon-shaped beak, rivets, a wind-up key in its back, "
        "tough, comic and a bit stupid, never cute")

ENEMIES = {
    "gull_soldier": {
        "ref": None,  # the pilot's soldier_ref.png
        "frame": (144, 120), "anchor": (72, 116), "height": 100, "faces": "left",
        "sheets": [
            ("idle", 5, "four frames of an IDLE loop (shifting weight, the wind-up key turning, helmet bobbing, a sneer) and then one frame getting HIT (recoil, feathers flying)", ["idle_0", "idle_1", "idle_2", "idle_3", "hit_0"], 0),
            ("walk", 6, "a six-frame WALK cycle, heavy bird steps, the pea-shooter held in the wing", ["walk_0", "walk_1", "walk_2", "walk_3", "walk_4", "walk_5"], 0),
            ("shoot", 6, "three frames SHOOTING the pea-shooter forward (aim, a puff of smoke and recoil, recover), then three frames of a PECK attack lunging forward with the cannon beak (wind-up, lunge, recover)", ["shoot_0", "shoot_1", "shoot_2", "peck_0", "peck_1", "peck_2"], 0),
            ("die_a", 6, "six frames of a COMIC DEATH, no blood: it bursts into a fireball and a cloud of feathers, screws and cogs, the helmet spins off into the air, the two legs are left standing for a beat, then fall; the last frame is empty smoke", ["die_a_0", "die_a_1", "die_a_2", "die_a_3", "die_a_4", "die_a_5"], None),
            ("die_b", 5, "five frames of a COMIC DEATH: it is squashed flat as a pancake, pops up as a flat feather duster, wobbles, and then goes poof in a little cloud", ["die_b_0", "die_b_1", "die_b_2", "die_b_3", "die_b_4"], None),
            ("surrender", 4, "four frames of SURRENDERING: it drops the pea-shooter, raises both wings, sweats, and a white sock is tied to its wind-up key as a flag (a loop)", ["surrender_0", "surrender_1", "surrender_2", "surrender_3"], 0),
        ],
    },
    "gull_bazooka": {
        "ref": GULL + ", kneeling on its hocks with a long sardine-can rocket launcher on its shoulder and a sardine tucked in its helmet. Full body, side view facing LEFT, about 84 pixels tall in the game. ",
        "frame": (144, 120), "anchor": (72, 116), "height": 84, "faces": "left",
        "sheets": [
            ("idle", 5, "four frames of an IDLE loop (kneeling, breathing, the key turning) then one frame getting HIT", ["idle_0", "idle_1", "idle_2", "idle_3", "hit_0"], 0),
            ("fire", 6, "three frames AIMING the launcher (lifting it, steadying, squinting) then three frames FIRING (a big backblast of smoke and fire, recoil, recover)", ["aim_0", "aim_1", "aim_2", "fire_0", "fire_1", "fire_2"], 0),
            ("die", 6, "two frames RELOADING (pulling a new sardine rocket) then four frames of a COMIC DEATH, sooty and burnt, collapsing into a smoking pile of feathers", ["reload_0", "reload_1", "die_0", "die_1", "die_2", "die_3"], 0),
        ],
    },
    "gull_drone": {
        "ref": GULL + ", flying: a propeller instead of a beak cannon, an aviator cap, a rack of fish-shaped bombs under its belly. Full body, side view facing LEFT, wings out, about 80 pixels wide in the game. ",
        "frame": (160, 120), "anchor": (80, 60), "height": 70, "faces": "left",
        "sheets": [
            ("fly", 6, "a six-frame FLIGHT cycle, flapping wings and a spinning propeller", ["fly_0", "fly_1", "fly_2", "fly_3", "fly_4", "fly_5"], 0),
            ("drop", 5, "three frames DROPPING a fish-shaped bomb (the rack opens, the bomb falls, the rack closes) and two frames getting HIT", ["drop_0", "drop_1", "drop_2", "hit_0", "hit_1"], 0),
            ("die", 6, "six frames of a COMIC DEATH: smoking, spinning down, the propeller unscrews and bounces away, a final puff", ["die_0", "die_1", "die_2", "die_3", "die_4", "die_5"], None),
        ],
    },
    "gull_kamikaze": {
        "ref": GULL + ", wearing goggles and a long white scarf, strapped to a red rocket with a painted sardine, a wide grin. Full body, side view facing LEFT, about 70 pixels wide in the game. ",
        "frame": (128, 104), "anchor": (64, 52), "height": 62, "faces": "left",
        "sheets": [
            ("idle", 5, "four frames HOVERING with a grin (the scarf flapping) and then one frame getting HIT", ["idle_0", "idle_1", "idle_2", "idle_3", "hit_0"], 0),
            ("dive", 6, "three frames WINDING UP (shaking, sweating, the rocket sputtering) then three frames DIVING at top speed with the scarf streaming", ["windup_0", "windup_1", "windup_2", "dive_0", "dive_1", "dive_2"], 0),
        ],
    },
    "crab_tank": {
        "ref": ("A crab-shaped tank: a big red real-crab shell as armour with spikes, bumps and seaweed and a stencilled number 17, six arched legs, eye-stalk periscopes, a cannon between the "
                "pincers of one claw, and a small mechanical gull pilot with a helmet peeking out of the top. Full body, side view facing LEFT, about 110 pixels tall in the game. " + STYLE + " " + FLAT),
        "frame": (224, 144), "anchor": (112, 140), "height": 110, "faces": "left",
        "sheets": [
            ("move", 6, "a six-frame WALK cycle on the six legs, the shell rocking", ["move_0", "move_1", "move_2", "move_3", "move_4", "move_5"], 0),
            ("fire", 6, "two frames IDLE (the pilot looking around) then four frames FIRING the cannon claw (aim, a big blast, recoil, the pilot ducks)", ["idle_0", "idle_1", "fire_0", "fire_1", "fire_2", "fire_3"], 0),
            ("die", 6, "one frame getting HIT, then five frames of a COMIC DEATH: a huge explosion, the pilot ejected on a spring screaming, the shell rolling away", ["hit_0", "die_0", "die_1", "die_2", "die_3", "die_4"], 0),
        ],
    },
    "grandma": {
        "ref": ("A tied-up old grandmother from the market (headscarf, apron, cardigan, a shopping trolley beside her), sitting bound with ropes and muffled by a mechanical gull's beak-clamp over her mouth, "
                "furious eyes. Full body, side view facing LEFT, about 90 pixels tall in the game. " + STYLE + " " + FLAT),
        "frame": (128, 120), "anchor": (64, 116), "height": 90, "faces": "left",
        "sheets": [
            ("tied", 5, "five frames of being TIED UP: wriggling in the ropes, muffled shouts, a furious glare (a loop)", ["tied_0", "tied_1", "tied_2", "tied_3", "tied_4"], 0),
            ("free", 6, "three frames of the ropes BURSTING and jumping to her feet, then three frames handing over a wooden crate with a big smile and patting a cheek", ["free_0", "free_1", "free_2", "give_0", "give_1", "give_2"], 0),
            ("run", 6, "a six-frame RUN cycle running away shaking her handbag, happy", ["run_0", "run_1", "run_2", "run_3", "run_4", "run_5"], 0),
        ],
    },
    "fisherman": {
        "ref": ("A tied-up old fisherman (beanie, oilskin coat, a pipe, a fish under his arm), sitting bound with ropes to a bollard, muffled by a mechanical gull's beak-clamp, grumpy eyes. Full body, "
                "side view facing LEFT, about 90 pixels tall in the game. " + STYLE + " " + FLAT),
        "frame": (128, 120), "anchor": (64, 116), "height": 90, "faces": "left",
        "sheets": [
            ("tied", 5, "five frames of being TIED UP: wriggling in the ropes, muffled grumbles, a grumpy glare (a loop)", ["tied_0", "tied_1", "tied_2", "tied_3", "tied_4"], 0),
            ("free", 6, "three frames of the ropes BURSTING and jumping to his feet, then three frames handing over a wooden crate with a gap-toothed grin and a thumbs up", ["free_0", "free_1", "free_2", "give_0", "give_1", "give_2"], 0),
            ("run", 6, "a six-frame RUN cycle running away with the fish waving, happy", ["run_0", "run_1", "run_2", "run_3", "run_4", "run_5"], 0),
        ],
    },
}


# El Gran Gaviotrón, the final boss: one canonical picture (boss_ref.png: a clockwork seagull war-walker with a seagull pilot in its porthole and the paellera closed under an
# iron lid), then whole-body sheets, as an enemy. The lid is hinged open (never thrown away) so the silhouette keeps its height from sheet to sheet.
ENEMIES["boss"] = {
    "ref": None,  # boss_ref.png, made from the chosen design (boss_design.png)
    "frame": (448, 336), "anchor": (224, 332), "height": 288, "faces": "left",
    "sheets": [
        ("idle", 4, "four frames of an IDLE loop: steam puffing from the pipes, the wind-up key turning, the long neck bobbing a little, the tiny seagull pilot looking around in the porthole, heavy breathing",
         ["idle_0", "idle_1", "idle_2", "idle_3"], 0),
        ("walk", 6, "a six-frame heavy WALK cycle on its two long mechanical legs, the whole body bobbing and the neck swaying, steam puffs", ["walk_0", "walk_1", "walk_2", "walk_3", "walk_4", "walk_5"], 0),
        ("hit", 4, "two frames of getting HIT (the body jolts, sparks and popped rivets, the pilot flinches) and then two frames of an IDLE that is DAMAGED (dented plates, missing feathers, smoke pouring, a cracked porthole)",
         ["hurt_0", "hurt_1", "dmg_0", "dmg_1"], 0),
        ("gat", 4, "four frames of firing both wing GATLING guns forward: the barrels spinning, big muzzle flashes and flying shell casings, the body leaning back with recoil", ["gat_0", "gat_1", "gat_2", "gat_3"], 0),
        ("stomp", 4, "four frames of a STOMP: the front leg lifts high, hangs, then slams down with a cloud of dust and sparks while the whole body bounces", ["stomp_0", "stomp_1", "stomp_2", "stomp_3"], 3),
        ("beam", 6, "six frames: the head rears back and the beak opens wide showing a brass cannon barrel inside, charging with a growing orange glow (four frames), then firing with a big flash (two frames)",
         ["charge_0", "charge_1", "charge_2", "charge_3", "fire_0", "fire_1"], 0),
        ("pot_a", 4, "four frames: the iron lid on the back pan UNLATCHES, bursts open with steam and swings up on a hinge to stand open upright behind the pan, revealing the glowing orange saffron-rice core; the pilot ducks. "
                     "The lid stays attached on its hinge", ["opening_0", "opening_1", "opening_2", "opening_3"], 0),
        ("pot_b", 4, "four frames of a loop: the back pan wide open with its lid standing upright on its hinge, the glowing core pulsing and bubbling, flames licking and sparks, the pilot cowering behind the porthole",
         ["open_0", "open_1", "open_2", "open_3"], 0),
        ("dead", 6, "six frames of a COMIC DEATH, no blood: shaking, sparks and fire bursting from the seams, the lid blowing off, the tiny pilot ejected on a spring screaming, the legs folding and the machine "
                    "collapsing into a smoking heap of feathers, gears and brass pipes with the wind-up key still turning; the last frame is the heap and stays", ["dead_0", "dead_1", "dead_2", "dead_3", "dead_4", "dead_5"], None),
    ],
}

# object sheets (no canonical picture of their own: the first sheet sets the look, the style reference does the rest)
OBJECTS = {
    "items": {
        "frame": (56, 56), "anchor": (28, 52),
        "sheets": [
            ("pickups", 6, "six pickup objects: a wooden weapon crate stencilled with a red pepper, a wooden crate stencilled with a flaming chilli, a wooden crate stencilled with a bottle, a crate of pressure-cooker pots, "
                           "a tiny red-hot pepper shaped heart, a round shield made of a paella pan", ["crate_a", "crate_b", "crate_c", "ammo", "heart", "shield"]),
            ("food_a", 6, "six Spanish foods as score pickups: a whole cured ham leg, a wedge of cheese, a paella pan, a Spanish omelette, a slice of melon, a sardine", ["food_jamon", "food_cheese", "food_paella", "food_tortilla", "food_melon", "food_sardine"]),
            ("food_b", 6, "six Spanish foods as score pickups: an orange, a loaf of bread, a tin of olives, a leather wine skin, a churro, an ensaimada pastry", ["food_orange", "food_bread", "food_olive_can", "food_wine_skin", "food_churro", "food_ensaimada"]),
        ],
    },
    "explosions": {
        "frame": (192, 192), "anchor": (96, 96),
        "sheets": [
            ("small", 5, "a five-frame SMALL EXPLOSION animation: a chunky cauliflower of orange and yellow fire lobes shaded from a hot centre to a red rim, growing then breaking into smoke", ["boom_s_0", "boom_s_1", "boom_s_2", "boom_s_3", "boom_s_4"]),
            ("medium", 6, "a six-frame MEDIUM EXPLOSION animation: a bigger chunky fireball with flying feathers and screws, cooling into rising smoke", ["boom_m_0", "boom_m_1", "boom_m_2", "boom_m_3", "boom_m_4", "boom_m_5"]),
            ("large", 6, "a six-frame LARGE EXPLOSION animation with a mushroom cloud, flying feathers, cogs and screws, ending in drifting smoke. ONLY the explosion, NO birds and NO characters; each frame well separated from the next by a wide empty margin and no frame wider than its own cell", ["boom_l_0", "boom_l_1", "boom_l_2", "boom_l_3", "boom_l_4", "boom_l_5"]),
            ("grenade", 6, "a six-frame PRESSURE-COOKER BLAST: a big puff of steam first with the pot's lid flying off, then a shock ring and flying chickpeas, ending in thin steam. ONLY the blast, NO birds and NO characters; each frame well separated from the next by a wide empty margin", ["boom_grenade_0", "boom_grenade_1", "boom_grenade_2", "boom_grenade_3", "boom_grenade_4", "boom_grenade_5"]),
            ("smoke", 5, "a five-frame rising SMOKE PUFF animation, soft grey and brown cartoon smoke with a hot red underside fading out", ["smoke_0", "smoke_1", "smoke_2", "smoke_3", "smoke_4"]),
            ("feathers", 5, "a five-frame burst of loose white and grey FEATHERS and tiny brass gears falling and fluttering", ["feathers_0", "feathers_1", "feathers_2", "feathers_3", "feathers_4"]),
        ],
    },
    "shots": {
        "frame": (56, 56), "anchor": (28, 28),
        "sheets": [
            ("a", 6, "three frames of a spinning kitchen KNIFE in flight and three frames of a splat of white FOAM growing", ["knife_0", "knife_1", "knife_2", "foam_0", "foam_1", "foam_2"]),
            ("b", 6, "three frames of a golden tumbling CROQUETTE and three frames of a splash of flung RICE grains and oil", ["croqueta_0", "croqueta_1", "croqueta_2", "rice_0", "rice_1", "rice_2"]),
            ("c", 6, "three frames of a swirl of WHIPPED CREAM and three frames of a champagne CORK streaking with a fizzy trail", ["cream_0", "cream_1", "cream_2", "cork_0", "cork_1", "cork_2"]),
            ("d", 6, "six frames of a steel PRESSURE-COOKER POT tumbling through the air (it turns a half turn over the six frames)", ["pot_0", "pot_1", "pot_2", "pot_3", "pot_4", "pot_5"]),
            ("e", 6, "two frames of a small enemy seed PELLET, two frames of an enemy FISH-SHAPED BOMB falling with tail fins, two frames of an enemy SARDINE ROCKET flying with flame, all pointing right", ["pea_0", "pea_1", "bomb_0", "bomb_1", "rocket_0", "rocket_1"]),
        ],
    },
    "props": {
        "frame": (128, 128), "anchor": (64, 126),
        "sheets": [
            ("barrel", 6, "a wooden BARREL: first intact, then five stages of breaking apart into planks and a splash, ending as a few pieces on the floor", ["barrel_0", "barrel_1", "barrel_2", "barrel_3", "barrel_4", "barrel_5"]),
            ("crate", 6, "a wooden FISH CRATE full of sardines: first intact, then five stages of breaking apart with sardines flying, ending as a few pieces", ["crate_0", "crate_1", "crate_2", "crate_3", "crate_4", "crate_5"]),
            ("buoy", 3, "a red and white round BUOY rolling: three frames of it turning", ["buoy_0", "buoy_1", "buoy_2"]),
        ],
    },
}

TRACTOR = {
    "ref": ("A small red-and-cream fishing-village farm tractor, big rear wheels and small front wheels, an exhaust pipe puffing, armoured with plates made from fish boxes (stencilled PESCADOS Y VERDURAS PACO) "
            "and a burnt paella pan welded on the front as a shield, a long sardine-tin-and-drainpipe cannon on top and a small vulcan gun beside it, a brass bell and a bulb horn, with an empty driver's seat "
            "(the seat back visible, no driver). Side view facing RIGHT, about 150 pixels wide in the game. " + STYLE + " " + FLAT),
    "frame": (224, 144), "anchor": (112, 140), "height": 100, "faces": "right",
    "sheets": [
        ("a", 6, "three frames IDLE (engine shaking, exhaust puff) and three frames of the DRIVE cycle (wheels turning, body bouncing)", ["idle_0", "idle_1", "idle_2", "drive_0", "drive_1", "drive_2"], 0),
        ("b", 6, "three more frames of the DRIVE cycle and three frames of a HOP on the suspension (squash, rise, fall)", ["drive_3", "drive_4", "drive_5", "jump_0", "jump_1", "jump_2"], 0),
        ("c", 6, "three frames FIRING the sardine cannon forward (recoil, flame from the barrel) and three frames with the cannon RAISED 70 degrees (aiming, firing, recoil)", ["fire_0", "fire_1", "fire_2", "cannon_up_0", "cannon_up_1", "cannon_up_2"], 0),
        ("d", 5, "one frame getting HIT (a shudder), then four frames BURNING and about to blow (smoking, dented, flames, wobbling, one lamp hanging)", ["hit_0", "burning_0", "burning_1", "burning_2", "burning_3"], 0),
        ("e", 6, "six frames of a big COMIC EXPLOSION: the wheels, the pan and the cannon fly off, the pan lands on the wreck like a lid, the cannon sticks nose-down in the ground", ["explode_0", "explode_1", "explode_2", "explode_3", "explode_4", "explode_5"], 0),
    ],
}
