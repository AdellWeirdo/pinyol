-- moves: the frame data of every attack, in ticks (60 a second): startup (before it can hurt), active (while it can), recovery (before the fighter is free).
-- level: high (a crouch ducks it), mid, low (a jump clears it, a stand block does not stop it), air. reach: how far in front of the hips it lands.
-- hh: the heights it reaches. A punch that lands can be followed by another (chain).
local M = {}

M.punch = {name = "punch", startup = 5, active = 3, rec = 9, dmg = 5, level = "high", reach = 9.4, hh = {10, 17.5}, hitstun = 13, blockstun = 9, knock = 1.6,
           windup = "punch_a", strike = "punch_b", chain = true}
M.kick = {name = "kick", startup = 9, active = 4, rec = 15, dmg = 9, level = "mid", reach = 11.5, hh = {4, 13}, hitstun = 17, blockstun = 12, knock = 3.2,
          windup = "kick_a", strike = "kick_b"}
M.sweep = {name = "sweep", startup = 11, active = 4, rec = 20, dmg = 8, level = "low", reach = 11, hh = {0, 4}, hitstun = 20, blockstun = 12, knock = 2, down = true,
           windup = "sweep_a", strike = "sweep_b"}
M.jkick = {name = "jkick", startup = 3, active = 14, rec = 0, dmg = 8, level = "air", reach = 9.6, hh = {1, 11}, hitstun = 16, blockstun = 10, knock = 2.6,
           windup = "jump", strike = "jkick", air = true}

return M
