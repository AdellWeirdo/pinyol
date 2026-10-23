-- ach: the achievements (game.json lists them).
local Run = require("core.run")
local Game = require("core.game")
local A = {}

function A.tick(play)
  if Run.kills >= 1 then achieve("primer_plato") end
  if Run.tractor_used then achieve("conductor") end
  if Run.tractor_kills >= 5 then achieve("triturador") end
  if Run.food_n >= 12 then achieve("banquete") end
  if Run.score >= 100000 then achieve("pluma_dorada") end
  if Run.pows >= 1 then achieve("abuela_a_salvo") end
end

function A.mission(chef)
  achieve("gaviotron")
  if Run.pows_total > 0 and Run.pows >= Run.pows_total then achieve("rescatador") end
  if Run.continues == 0 then achieve("sin_continuar") end
  if Run.deaths == 0 then achieve("sin_una_mancha") end
  if Game.won_count() >= 3 then achieve("menu_degustacion") end
  if Game.won_count() >= 6 then achieve("carta_completa") end
end

return A
