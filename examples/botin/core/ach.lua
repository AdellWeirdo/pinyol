-- ach: the achievements (game.json lists them) and the ending's words.
local Game = require("core.game")
local lang = require("lang")
local A = {}

function A.init() end

local function once(id) achieve(id) end

-- every tick of a level
function A.tick(run, hero)
  if run.broken >= 10 then once("rompetodo") end
  if run.chest then once("cofre") end
  if run.kills >= 5 then once("lanzador") end
  for i = 1, 4 do if run.jewels[i] then once("primera_pieza") end end
  if run.jewel_count() == 4 then once("joya_completa") end
end

function A.level_done(n, run, crown, hero)
  once("huida")
  if run.escape_t and run.escape_t < 300 and run.escape_total > 0 then once("por_los_pelos") end
  if run.hits == 0 then once("sin_rasgunos") end
  if crown == 3 then once("corona_de_oro") end
  if Game.jewel_total() >= 16 then once("coleccionista") end
end

function A.boss() once("gran_golem") end

function A.ending_text(t)
  panel(30, 16, 420, 112)
  text(lang.tr("end_title"), 240, 30, {font = "gba_title", align = "center", color = 0x8a3a08})
  text(lang.tr("end_text", {n = Game.jewel_total(), coins = Game.coins_total}), 240, 76, {font = "gba_small", align = "center", color = 0x3a1c08, width = 380})
  if t > 240 then text(lang.tr("res_press"), 240, 292, {font = "gba_small", align = "center", color = (t // 20) % 2 == 0 and 0xFFFFFF or 0xA0A0A0}) end
end

return A
