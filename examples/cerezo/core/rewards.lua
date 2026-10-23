-- rewards: getting things. A chest, a buried treasure, a gift from someone: the hero holds the item over his head, the
-- jingle plays, a message says what it is, and what the item does is done.
local C = require("core.const")
local E = require("core.ents")
local W = require("core.world")
local Game = require("core.game")
local Sound = require("core.sound")
local Dialog = require("core.dialog")
local Pick = require("core.pickups")
local R = {}

-- each item: what getting it does (give), whether the whole island should hear (big: the long jingle)
local ITEMS = {
  pala = {big = true, give = function() Game.give("pala") end},
  tirachinas = {big = true, give = function() Game.give("tirachinas") Game.add_pinyoles(10) end},
  linterna = {big = true, give = function() Game.give("linterna") achieve("luz_en_la_raiz") end},
  llave_pequena = {give = function() local d = R.dungeon or "raiz" Game.keys[d] = (Game.keys[d] or 0) + 1 end},
  llave_jefe = {big = true, give = function() Game.bosskeys[R.dungeon or "raiz"] = true end},
  mapa = {give = function() Game.maps[R.dungeon or "raiz"] = (Game.maps[R.dungeon or "raiz"] or 0) | 1 end},
  brujula = {give = function() Game.maps[R.dungeon or "raiz"] = (Game.maps[R.dungeon or "raiz"] or 0) | 2 end},
  pinyol_dorado = {big = true, give = function()
    Game.pits = Game.pits + 1
    if Game.pits >= 3 then achieve("tres_pinyoles") end
  end},
  pieza_corazon = {give = function()
    Game.pieces = Game.pieces + 1
    if Game.pieces % 4 == 0 then
      Game.maxhp = math.min(16, Game.maxhp + 2)
      Game.hp = Game.maxhp
      achieve("corazon_de_oro")
    end
  end},
  contenedor_corazon = {big = true, give = function() Game.maxhp = math.min(16, Game.maxhp + 2) Game.hp = Game.maxhp end},
  cereza_dorada = {big = true, give = function() Game.setflag("cereza_dorada") end},
}

-- gives `item`: the pose, the sound, the message "item_<name>" of the story, then `done` runs
function R.get(item, done)
  local def = ITEMS[item]
  if not def then error("no item " .. tostring(item)) end
  def.give()
  local jingle, secs = "jingle_item", 3
  if item == "pieza_corazon" or item == "contenedor_corazon" then jingle, secs = "jingle_heart", 2
  elseif def.big then jingle, secs = "jingle_big", 6 end
  require("core.music").jingle(jingle, secs)
  local h = E.hero
  local hero = require("core.hero")
  if h then hero.set(h, "item", item) end
  Dialog.after(function()
    if h then hero.set(h, "walk") end
    if done then done() end
  end)
  Dialog.start("item_" .. item, {pose = true})
end

-- what a dig turned up: cherries and the like fall as pickups, an item is got
function R.buried(def, x, y)
  if def.flag and Game.flags[def.flag] then return end
  if def.flag then Game.flags[def.flag] = true end
  achieve("cavador")
  local what = def.item
  if what == "cherries" or what == "cherry" then
    for i = 1, def.n or 5 do Pick.drop("cherry", x + (i - 3) * 4, y, false) end
  elseif what == "heart" then
    Pick.drop("heart", x, y)
  else
    R.get(what)
  end
end

return R
