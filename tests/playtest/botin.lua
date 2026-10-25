-- playtest-gate: win   (tests/playtest_gate.py: the perfect player must finish the game; ctest runs it)
-- playtest adapter for Botín (see docs/playtest.md).
--
-- The perfect player plays one TAPE per level: the exact buttons, tick by tick from the moment the vortex opens (Run.t = 0), found by a search that runs the game's own
-- hero / enemy / thing / boss code forward (a planner kept outside the repo: ~/pinyol-playtests/botin/plan). The game is deterministic from its input, so a tape that
-- worked once works again; if the game's physics, levels or enemies change, a tape stops matching and the player gets stuck or dies: run the planner again
-- (`plan/mk.sh N`) and paste the new tape. What the tapes do: level 1 (Selva) all 4 jewel pieces and the frog, back to the vortex; level 2 (Cristal) the 4 pieces
-- (the fourth by a ram-jump from the ledge under the roof); level 3 (Galeón) pieces 1 and 2; level 4 (Fragua) pieces 1, 3 and 4; the Golem with stone eggs thrown
-- into its open head. The boss's door needs 10 of the 16 pieces: levels 1, 2 and 4 give 11.
--
-- LEVEL 3: its tape needs two fixes the game does not have yet (see the notes in ~/pinyol-playtests/botin/NOTES.md): a swimming hero cannot get out of the water
-- (a kick gives -1.5 and the swim clamp -2.4: the best he reaches is 10 px short of the dock where the vortex is) and the column of BLUE blocks at x = 76..78 (rows 3-9)
-- cannot be broken from the water (only a smash from the air breaks blue blocks, and a swimmer cannot smash). Until then this player is stuck in level 3 and the gate fails.
--
-- Botín reads its buttons through In.btnb (the engine's buffered press), which the bot does not replace (it only replaces btn / btnp): the adapter gives In the same
-- buffer from the bot's btn.
local Run = require("core.run")
local Game = require("core.game")
local Play = require("core.play")
local Boss = require("core.boss")
local Trans = require("core.trans")
local In = require("core.input")
local Map = require("core.map")
local W = require("core.world")
local C = require("core.const")

-- ---------------------------------------------------------------- the input buffer In.btnb needs
local NAMES = {"left", "right", "up", "down", "a", "b", "start"}
local was, age, used = {}, {}, {}
local real_update, real_btnb = In.update, In.btnb
In.update = function()
  real_update()
  if In.bot then return end
  for _, n in ipairs(NAMES) do
    local on = btn(n) == true
    if on and not was[n] then age[n], used[n] = 0, false elseif age[n] then age[n] = age[n] + 1 end
    was[n] = on
  end
end
In.btnb = function(n, window)
  if In.bot then return real_btnb(n, window) end
  if age[n] and not used[n] and age[n] < (window or 6) then used[n] = true return true end
  return false
end

-- ---------------------------------------------------------------- the tapes: "mask:ticks ..." with mask = left 1, right 2, up 4, down 8, a 16, b 32
local TAPE_TEXT = {
  [1] = "0:41 2:3 32:3 16:9 0:24 16:9 0:15 32:3 0:12 16:6 0:21 33:3 16:3 0:18 16:3 0:12 16:3 0:3 32:3 16:3 0:9 16:3 0:21 33:3 16:9 0:12 2:6 17:3 1:6 0:3 16:3 17:12 1:9 0:6 2:6 0:3 32:3 0:15 16:15 0:27 33:3 16:6 0:3 16:3 0:3 16:3 0:3 16:6 0:3 33:3 0:12 16:3 0:9 2:12 0:6 2:12 18:3 0:3 2:3 0:3 18:18 2:18 0:6 18:9 2:6 18:3 0:3 2:3 0:3 2:3 0:3 2:18 32:3 0:3 1:6 2:3 0:6 32:3 16:3 0:21 33:3 0:30 16:3 18:6 2:3 18:3 2:9 32:3 16:3 0:3 2:9 32:3 0:24 2:24 0:3 1:6 2:9 0:6 2:3 1:3 17:3 1:9 2:6 32:3 16:9 0:24 16:9 0:15 2:6 0:6 17:9 1:6 0:3 2:6 18:3 2:3 0:3 1:3 16:15 0:3 2:9 18:3 0:6 1:6 16:3 34:3 0:3 16:3 0:33 1:9 32:3 0:24 32:3 0:24 1:18 17:3 0:12 16:3 0:3 32:3 16:9 0:15 2:12 33:3 16:3 1:12 32:3 0:24 1:24 0:3 2:6 1:3 17:3 1:9 0:3 1:18 17:3 16:3 1:3 0:3 1:3 0:3 1:39 0:6 1:30 0:6 1:3 2:3 0:3 33:3 16:3 0:30 16:3 0:18 32:3 16:6 0:21 16:3 1:15 32:3 0:24 32:3 0:24 1:21 0:3 16:3 0:18 32:3 0:24 32:3 0:24 1:18 32:3",
  [2] = "0:41 2:3 32:3 0:24 32:3 0:24 2:6 32:3 16:6 0:36 1:21 0:3 8:3 2:21 18:3 0:6 2:3 0:6 8:3 0:21 32:3 0:18 16:3 0:6 33:3 16:3 0:6 33:3 0:6 16:6 17:3 1:9 0:3 1:3 34:3 16:3 0:3 2:12 32:3 0:24 32:3 0:6 10:3 2:6 18:3 2:21 18:3 2:27 1:3 2:3 18:3 2:24 18:3 2:69 18:3 0:6 2:3 0:6 18:3 32:3 16:3 0:21 16:3 0:9 2:24 0:9 2:24 0:3 16:3 2:3 1:15 0:3 2:27 0:6 2:3 32:3 0:24 32:3 0:24 16:3 0:15 16:3 32:3 16:3 0:18 16:3 0:3 2:24 18:3 16:6 2:3 0:6 2:6 18:3 16:6 2:3 0:3 2:21 18:3 1:6 0:3 32:3 16:9 0:18 16:3 8:3 0:15 18:3 0:3 2:3 0:3 1:6 2:3 32:3 0:9 16:6 0:33 17:3 1:24 17:3 0:9 1:3 32:3 0:24 1:3 32:3 0:24 32:3 0:27 32:3 0:24 32:3 0:24 1:6 17:3 0:18 17:3 0:9 1:24 2:3 1:3 0:3 17:3 0:6 1:3 0:6 1:3 17:3 16:3 0:3 1:3 0:3 1:3 0:3 1:27 0:3 1:3 0:3 1:12 32:3 0:18 16:9 0:12 2:21 33:3 0:12 2:3 0:3 9:3 1:18 17:3 1:15 17:3 1:126 32:3 0:24 32:3 0:15 16:3 1:15 32:3 0:24 32:3 0:12 16:3 0:18 1:3 16:6 0:21 1:24 32:3 0:24 32:3 0:18",
  [3] = "0:41 2:3 32:3 0:24 32:3 0:12 1:5 0:2 34:2 0:24 32:2 0:18 1:2 2:2 1:2 34:2 1:2 2:2 1:2 2:2 1:2 2:2 1:2 0:4 2:2 1:2 2:2 33:2 2:2 1:2 2:2 1:2 2:2 1:2 0:2 2:2 1:2 2:2 1:2 2:2 33:2 2:2 1:2 2:2 0:6 1:2 2:2 1:2 2:2 0:2 16:1 0:1 33:2 2:2 0:22 32:2 0:14 16:1 0:3 16:1 0:5 16:1 0:1 32:2 0:4 16:1 0:5 16:1 0:5 16:1 0:5 16:1 0:5 16:1 0:7 16:1 0:5 16:1 0:5 16:1 0:5 16:1 0:5 16:1 0:7 16:1 0:5 16:1 0:5 16:1 0:3 32:2 16:1 0:15 8:2 0:6 32:2 0:2 8:2 0:20 32:2 0:24 32:2 0:16 1:2 2:2 1:2 2:2 33:2 2:2 16:1 0:1 16:1 0:5 16:1 0:5 16:1 0:5 16:1 0:1 32:2 0:4 16:1 0:5 16:1 0:5 16:1 0:5 16:1 0:1 32:2 0:2 16:1 0:5 8:2 0:6 16:1 0:11 2:3 32:2 0:18 8:2 0:4 32:2 0:2 8:2 0:12 16:1 0:5 8:2 32:2 0:6 8:2 0:12 8:2 0:2 40:2 0:2 8:2 0:20 32:2 0:2 16:1 0:3 8:2 0:8 8:4 0:4 32:2 0:4 8:2 0:2 8:2 0:2 8:2 0:10 32:2 0:24 32:2 0:8 8:2 0:10 8:2 0:2 32:2 0:24 32:2 0:2 16:1 0:5 8:2 0:10 8:4 40:2 0:2 8:2 0:2 1:2 2:2 1:2 10:2 0:10 32:2 0:30 33:2 0:2 2:2 1:2 0:8 2:2 1:2 2:2 1:2 2:2 33:2 2:2 1:2 2:2 1:2 2:2 0:2 25:1 9:1 2:2 9:2 2:2 8:2 0:2 32:2 9:2 2:2 1:2 2:2 1:2 16:1 0:5 16:1 0:5 16:1 0:1 32:2 0:2 16:1 0:5 16:1 0:5 16:1 0:5 16:1 0:3 32:2 0:2 16:1 0:5 16:1 0:5 16:1 0:5 16:1 0:3 32:2 16:1 0:5 8:2 16:1 0:5 16:1 0:7 16:1 0:1 32:2 0:2 16:1 0:5 8:2 0:10 8:2 0:2 40:2 0:4 8:2 0:8 8:2 0:2 16:1 0:5 40:2 0:10 8:4 0:6 8:2 0:2 32:2 0:4 8:2 0:10 16:1 0:5 8:2 32:2 0:8 8:2 0:10 8:2 0:2 32:2 0:4 8:2 0:10 16:1 0:1 8:2 0:2 16:1 0:1 32:2 0:2 8:4 0:6 8:2 0:6 8:2 0:2 32:2 0:6 16:1 0:1 8:4 0:13 32:2 0:16 8:2 0:6 32:2 0:4 16:1 0:3 8:2 0:6 8:2 0:7 17:1 1:1 32:2 8:2 0:6 8:2 0:7 16:1 0:3 8:2 0:2 32:2 0:2 8:2 0:7 16:1 0:5 8:2 0:4 8:2 1:3 32:2 16:1 0:5 8:2 0:15 16:1 0:1 32:2 0:2 8:2 0:3 16:1 0:16 32:2 0:24 40:2 0:10 8:2 0:12 32:2 0:84 32:2 16:1 0:1 16:1 0:1 16:1 0:1 16:1 0:1 16:1 0:1 16:1 0:1 16:1 0:1 16:1 0:1 16:1 0:1 16:1 0:1 16:1 0:1 16:1 0:1 16:1 0:1 16:1 0:1 32:2 16:1 0:5 16:1 0:7 16:1 0:3 2:2 17:1 1:1 0:2 32:2 16:1 0:5 16:1 0:5 16:1 0:7 16:1 0:3 34:2 17:1 1:1 2:2 1:2 18:1 2:1 1:2 2:2 17:1 1:1 2:2 1:2 16:1 0:5 32:2 16:1 0:5 16:1 0:5 16:1 0:11 8:2 16:3 0:3 1:60 32:3",
  [4] = "0:41 2:3 32:3 0:21 33:3 0:6 33:3 0:6 33:3 0:3 33:3 0:9 2:12 16:3 0:9 17:3 1:6 18:3 2:6 0:3 2:3 17:3 1:3 18:3 2:3 0:3 2:30 0:6 2:3 18:3 2:6 0:3 2:6 18:3 2:3 18:3 0:3 2:3 0:3 2:27 0:3 2:3 0:3 32:3 0:9 16:3 0:36 33:3 0:6 33:3 0:6 32:3 0:24 16:3 0:15 16:3 18:6 2:3 16:3 0:9 2:3 18:3 0:6 2:3 0:6 18:3 2:3 16:3 0:3 2:3 1:3 0:3 2:24 0:6 2:30 0:6 2:6 32:3 16:3 1:3 2:36 32:3 0:24 32:3 0:24 32:3 0:24 2:15 17:6 16:9 17:18 1:6 0:6 18:3 2:3 0:3 2:3 17:12 0:3 1:3 0:3 1:21 16:3 2:6 0:3 18:6 17:9 0:3 2:15 0:3 2:3 32:3 16:9 0:18 32:3 0:39 17:3 0:12 1:6 32:3 0:9 16:3 0:15 16:18 18:3 2:21 33:3 0:24 1:3 2:3 18:3 2:3 18:6 2:15 33:3 0:24 32:3 0:24 1:15 32:3 0:24 1:21 17:3 0:12 1:9 17:3 16:3 0:3 1:3 0:3 1:3 0:3 1:30 0:6 1:30 0:6 1:15 32:3 0:24 32:3 0:24 32:3 0:24 32:3 0:3 16:3 0:18 1:3 17:3 0:12 1:15 0:9 1:9 17:3 16:3 1:3 0:3 1:3 0:3 1:33 0:6 1:15 32:3 0:9 16:3 0:18 32:3 0:24 32:3 0:18",
  [5] = "0:41 17:3 1:3 34:3 0:3 16:3 0:6 16:6 0:3 16:18 1:6 17:3 1:3 17:6 1:3 17:6 16:3 0:3 18:3 0:3 17:3 2:3 1:3 0:3 18:3 17:3 18:3 17:3 18:3 1:3 2:3 1:3 18:3 17:3 18:3 17:3 18:3 17:3 18:3 17:3 18:3 17:3 2:3 17:3 18:3 17:3 18:3 17:3 18:3 17:3 18:3 17:3 18:3 17:3 18:3 17:3 18:3 17:3 18:3 17:3 18:3 17:3 18:3 17:3 18:3 17:3 18:3 17:3 18:3 1:3 18:3 17:3 18:3 17:3 2:3 17:3 18:3 17:3 2:3 17:3 2:3 17:3 18:3 1:3 18:3 17:3 18:3 17:3 2:3 1:3 18:3 1:3 18:3 1:3 18:3 2:3 1:3 0:3 16:6 17:3 16:6 2:3 1:3 18:3 1:3 18:3 1:3 2:3 1:3 2:3 17:3 18:3 17:3 2:3 17:3 2:3 1:3 18:3 1:3 18:3 17:3 18:3 17:3 0:3 16:15 0:3 16:15 18:24 17:6 16:6 18:3 50:4 18:2 16:9 0:3 16:15 2:3 34:1 2:2 17:3 0:3 18:3 2:3 18:3 1:3 32:3 0:3 16:3 0:6 16:3 0:3 16:6 0:18 2:6 32:3 16:6 0:6 16:12 0:3 18:3 33:3 0:3 16:3 0:3 16:3 0:3 16:3 0:3 16:15 0:3 2:3 18:3 2:3 18:3 2:3 18:6 2:3 18:6 17:6 1:3 17:3 1:3 18:6 0:3 1:3 2:3 1:3 2:3 17:3 18:3 17:3 18:3 17:3 18:3 1:3 18:3 17:3 2:3 1:3 18:3 17:3 18:3 17:3 18:3 1:3 2:3 1:3 2:3 17:3 18:3 17:3 2:3 1:3 18:3 1:3 2:3 1:3 2:3 17:3 18:3 0:3 16:3 0:15 16:6 0:3 16:3 0:6 16:3 0:3 16:3 0:3 16:9 0:6 16:6 0:12 16:6 0:3 16:3 0:3 16:3 0:3 16:3 0:3 16:3 0:3 16:9 0:3 16:9 0:3 16:6 18:24 16:6 18:3 16:3 18:3 50:4 18:2 16:6 1:3 2:3 16:15 2:3 34:1 2:2 18:3 0:3 18:3 16:3 2:3 17:3 32:3 16:3 0:6 16:3 0:6 16:21 2:6 18:3 2:3 18:12 2:3 0:6 1:3 0:3 16:3 0:3 16:3 0:9 16:9 0:3 16:3 0:3 16:3 0:6 16:9 0:3 16:30 0:9 16:6 0:12 16:3 0:3 16:3 0:6 16:6 0:6 16:6 0:3 16:6 0:3 16:15 0:3 16:3 0:12 16:3 0:3 16:12 0:18 16:6 0:3 16:12 0:3 16:6 0:3 16:3 0:3 16:3 0:6 16:15 0:3 16:9 0:6 16:12 0:3 16:15 0:6 16:3 0:9 16:3 0:3 16:12 0:3 16:3 0:3 16:9 0:9 16:6 0:3 16:15 0:6 16:15 0:3 16:9 0:3 16:12 0:3 16:9 0:3 16:12 0:9 16:9 0:3 16:6 0:3 16:6 0:6 16:21 0:3 16:6 0:3 16:3 0:6 16:9 0:3 16:12 0:9 16:3 0:9 16:6 0:3 16:18 0:12 16:3 0:6 16:15 0:3 16:3 0:12 16:6 0:6 16:18 0:12 16:3 18:24 16:6 18:3 16:3 18:3 50:3 49:1 17:5 18:3 17:3 0:3 16:15 18:3 50:1 18:2 17:3 0:3 18:3 1:3 2:3 17:3 18:3 49:3 16:39 2:3 32:3 0:3 16:3 0:15 16:3 18:6 16:3 49:3 16:39 18:12 2:3 18:3 0:6 17:3 2:3 0:3 16:3 0:3 17:3 0:3 16:3 0:9 16:6 0:3 16:6 0:3 16:3 0:3 16:3 0:6 16:3 0:3 16:9 0:3 16:3 0:3 16:6 0:3 16:3 0:3 16:3 0:6 16:3 0:3 16:3 0:3 16:18 0:6 16:3 0:3 16:6 0:3 16:9 0:3 16:3 0:3 16:6 0:9 16:9 0:3 16:18 0:3 16:15 0:3 16:6 0:3 16:12 0:3 16:18 0:3 16:12 0:9 16:18 0:3 16:3 0:9 16:12 0:3 16:6 0:3 16:3 0:3 16:9 0:6 16:9 0:6 16:3 0:9 16:6 0:3 16:9 0:3 16:3 0:3 16:3 0:3 16:3 2:6 18:9 2:9 17:6 1:3 17:3 18:3 50:4 18:2 16:9 0:3 16:15 2:3 50:1 18:5 0:3 17:3 18:3 1:3 18:3 16:9 0:3 2:6 0:9 2:3 0:3 16:3 18:3 17:3 18:3 1:6 18:3 0:3 17:3 16:3 1:3 17:9 18:3 2:3 16:3 17:3 18:6 2:3 16:3 0:3 17:3 1:6 2:3 18:3 17:6 16:3 18:3 17:6 18:3 0:3 16:3 0:3 18:3 17:3 1:6 2:3 0:3 1:3 16:3 17:3 16:3 0:6 18:3 2:3 18:3 16:3 2:3 1:3 0:3 1:9 0:3 2:3 16:6 17:3 1:3 0:3 18:6 0:3",
}
local tapes = {}
local function tape(level)
  local t = tapes[level]
  if t then return t end
  t = {}
  for m, n in TAPE_TEXT[level]:gmatch("(%d+):(%d+)") do
    local mask = tonumber(m)
    for _ = 1, tonumber(n) do t[#t + 1] = mask end
  end
  tapes[level] = t
  return t
end

-- A human-like player (tools/playtest_bot.lua) presses what the perfect player would press `delay` ticks ago, a reaction time of 5 to 30 ticks. The tape is a run learnt by
-- heart, not a reaction, so for those players it reads `delay` ticks ahead: the delay cancels and what is left of them are their slips (late or early presses, stray
-- buttons, a moment looking away).
local CFG = PT_CFG or {}
local LEAD = CFG.mode == "human" and math.floor(30 - 25 * (CFG.skill or 0.5) + 0.5) or 0

local function buttons(mask)
  return {left = mask & 1 ~= 0, right = mask & 2 ~= 0, up = mask & 4 ~= 0, down = mask & 8 ~= 0, a = mask & 16 ~= 0, b = mask & 32 ~= 0}
end

-- the map: put the cursor on the first level not done (the golem's door when the four are), and confirm
local function map_intent(pt)
  local target = 5
  for i = 1, 4 do if not Game.levels[i].done then target = i break end end
  if target == 5 and not Game.boss_open() then target = 1 end -- (not enough pieces: no way on, play the first level again)
  local out = {}
  if Map.sel < target then out.right = pt.t % 6 == 0
  elseif Map.sel > target then out.left = pt.t % 6 == 0
  else out.a = pt.t % 6 < 3 end
  return out
end

local function levels_done()
  local n = 0
  for i = 1, 4 do if Game.levels[i].done then n = n + 1 end end
  return n + (Game.boss_done and 1 or 0)
end

PLAYTEST = {
  stuck_ticks = 5400,
  playing = function() return (G.state == "play" or G.state == "map") and not Trans.active() end,
  progress = levels_done,
  done = function() if G.state == "ending" then return "win" end end,
  deaths = function() return Game.stats.deaths end,
  where = function()
    if G.state == "play" or G.state == "over" or G.state == "results" then return "level_" .. tostring(G.level) end
    return G.state
  end,
  probe = function()
    local h = Play.hero
    return {n_hearts = h and h.hearts or 0, n_jewels = Game.jewel_total(), n_cell = h and math.max(0, math.floor(h.x / 64)) or 0, n_boss_hp = Boss.hp}
  end,
  invariants = function()
    if G.state ~= "play" then return nil end
    local h = Play.hero
    if not h then return nil end
    if h.hearts > C.HEARTS then return "hearts_over_max" end
    if h.state ~= "dead" and (h.x < -64 or h.x > W.px_w + 64 or h.y < -200 or h.y > W.px_h + 200) then return "hero_out_of_level" end
    if Run.coins < 0 then return "coins_negative" end
    return nil
  end,
  perfect = function(pt)
    if G.state == "map" then return map_intent(pt) end
    if G.state ~= "play" then return {} end
    local t = tape(G.level)
    return buttons(t[Run.t + 1 + LEAD] or 0)
  end,
}
