-- ach: the achievements (game.json lists them).
local Run = require("core.run")
local Game = require("core.game")
local A = {}

function A.tick(play)
  if Run.kills >= 1 then achieve("primer_golpe") end
  if Run.props >= 10 then achieve("demoledor") end
  if Run.parts >= 1 then achieve("pieza_nueva") end
  local n = 0
  for _ in pairs(Run.parts_kinds) do n = n + 1 end
  if n >= 4 then achieve("coleccionista") end
  if Run.throws >= 5 then achieve("lanzador") end
  if Run.specials >= 1 then achieve("vapor") end
  if Run.score >= 50000 then achieve("cincuenta_mil") end
  if Run.alt then achieve("colorista") end
end

function A.finish(hero)
  achieve("pendulo")
  if Run.continues == 0 then achieve("sin_continuar") end
  if Game.won_count() >= 3 then achieve("trio") end
end

return A
