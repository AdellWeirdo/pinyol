-- save: the game kept between sessions: everything in Game, and where he stands. One slot. `store` writes the file a
-- second after the last call on the console, so it is called at the moments a player expects (a bed, the menu).
local Game = require("core.game")
local E = require("core.ents")
local W = require("core.world")
local S = {}

function S.write()
  local h = E.hero
  if h then
    Game.area, Game.cx, Game.cy, Game.face = W.aid, math.floor((h.x + 8) / 16), math.floor((h.y + 12) / 16), h.face
  end
  store("save", Game.snapshot())
  store("saved_at", clock() and clock().days or 0)
end

function S.exists() return stored("save") ~= nil end

function S.read()
  local s = stored("save")
  if not s then return false end
  Game.restore(s)
  return true
end

function S.clear() store("save", nil) end

return S
