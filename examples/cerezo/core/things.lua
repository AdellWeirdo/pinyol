-- things: what the maps say lives in an area (npc, enemy, chest, sign...) and the function that makes each.
local C = require("core.const")
local T = {}

T.kinds = {}

function T.spawn(def)
  local make = T.kinds[def.kind]
  if not make then return nil end
  return make(def)
end

T.kinds.enemy = function(def)
  require("core.enemies")
  return require("core.enemy").spawn(def)
end

-- an exit: a cell that leads to another place (a door, a stair, a cave mouth). `to` is the area, `tx, ty` the cell the
-- hero arrives at; it works when he steps on it (`dir`, if given, only when he walks that way into it).
T.kinds.exit = function(def)
  local e = {kind = "exit", x = def.cx * C.T, y = def.cy * C.T, solid = false, hw = 16, hh = 16, hx = 0, hy = 0}
  local U = require("core.util")
  function e.update(self)
    local h = require("core.ents").hero
    if not h or h.state ~= "walk" then return end
    if U.overlap(h.x + 4, h.y + 9, 8, 5, self.x + 2, self.y + 2, 12, 12) and (not def.dir or (h.face == def.dir and h.moving)) then
      require("core.sound").play("door")
      require("core.play").go(def.to, def.tx, def.ty, def.face or "down")
    end
  end
  return require("core.ents").add(e)
end

T.kinds.npc = function(def) return require("core.npc").spawn(def) end

-- a sign: invisible, you read it (its text is the story knot of its name)
T.kinds.sign = function(def)
  local e = {kind = "sign", x = def.cx * C.T, y = def.cy * C.T, solid = false, hw = 16, hh = 16, hx = 0, hy = 0}
  function e.interact(self, hero) require("core.dialog").start(def.text or def.id) end
  return require("core.ents").add(e)
end

-- a chest: its picture is a tile; opening it changes the tile and gives what is in it, once
T.kinds.chest = function(def)
  local Game = require("core.game")
  local e = {kind = "chest", x = def.cx * C.T, y = def.cy * C.T, solid = false, hw = 16, hh = 16, hx = 0, hy = 0}
  function e.interact(self, hero)
    if def.flag and Game.flags[def.flag] then return end
    if def.flag then Game.flags[def.flag] = true end
    require("core.world").set(def.cx, def.cy, require("core.world").area.tileset == "interior" and "ichest_open" or "chest_open")
    require("core.sound").play("chest")
    require("core.rewards").get(def.item)
  end
  return require("core.ents").add(e)
end

-- a buried treasure: nothing to see; the pala finds it (core/interact.lua, `dug`)
T.kinds.buried = function() return nil end

-- the nest in a tall tree: a pinyol of gold shines in it. Only a shot from the tirachinas reaches it.
T.kinds.nest = function(def)
  local Game = require("core.game")
  if def.flag and Game.flags[def.flag] then return nil end
  local E = require("core.ents")
  local W = require("core.world")
  local e = {kind = "nest", team = "enemy", x = def.cx * C.T, y = def.cy * C.T - 8, t = 0, bx = 2, by = 2, bw = 12, bh = 12, ranged_only = true,
             hw = 0, hh = 0}
  function e.update(self)
    self.t = self.t + 1
    if self.t % 90 == 0 then require("core.fx").spark(self.x + 8, self.y + 6) end -- something shines up there
  end
  function e.hit(self, dmg, dir, source)
    if self.dead then return false end
    self.dead = true
    if def.flag then Game.flags[def.flag] = true end
    require("core.fx").spark(self.x + 8, self.y + 8)
    require("core.sound").play("secret")
    require("core.pickups").drop("cherry", self.x + 8, self.y + 8)
    require("core.rewards").get("pinyol_dorado")
    return true
  end
  return E.add(e)
end

return T
