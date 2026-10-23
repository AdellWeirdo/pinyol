-- npc: the people of the island. Each stands in a cell, looks about, turns to whoever speaks to them, and answers with
-- the story knot of their name (which decides what to say from what has happened). Some wander near where they stand.
local C = require("core.const")
local U = require("core.util")
local W = require("core.world")
local S = require("core.spr")
local E = require("core.ents")
local Dialog = require("core.dialog")
local Npc = {}

local FACES = {down = "down", up = "up", left = "side", right = "side"}

function Npc.spawn(def)
  local n = {kind = "npc", id = def.id, x = def.cx * C.T, y = def.cy * C.T - 4, face = def.face or "down", t = math.random(60),
             home_x = def.cx * C.T, home_y = def.cy * C.T - 4, solid = true, hx = 3, hy = 8, hw = 10, hh = 7, sort = 15,
             wander = def.wander, knot = def.knot or def.id, step = 0, wait = 60 + math.random(120), def = def,
             reach = def.reach or 0}
  n.ix, n.iy, n.iw, n.ih = n.x - n.reach, n.y - n.reach, 16 + 2 * n.reach, 16 + 2 * n.reach
  function n.interact(self, hero)
    -- turns to look at him
    local dx, dy = hero.x - self.x, hero.y - self.y
    self.face = U.dir_of(dx, dy)
    self.talking = true
    Dialog.after(function() self.talking = false end)
    Dialog.start(self.knot)
  end
  function n.update(self)
    self.t = self.t + 1
    if self.talking or not self.wander then return end
    if self.step > 0 then
      self.step = self.step - 1
      local d = U.DIRS[self.face]
      local nx, ny = self.x + d[1] * 0.5, self.y + d[2] * 0.5
      local fx, fy = math.floor(nx), math.floor(ny)
      if not W.blocked(fx + 3, fy + 8, 10, 7) and not E.solid_at(fx + 3, fy + 8, 10, 7, self)
         and math.abs(nx - self.home_x) <= self.wander * C.T and math.abs(ny - self.home_y) <= self.wander * C.T then
        self.x, self.y = nx, ny
        self.ix, self.iy = nx - self.reach, ny - self.reach
      else
        self.step = 0
      end
    else
      self.wait = self.wait - 1
      if self.wait <= 0 then
        local dirs = {"down", "up", "left", "right"}
        self.face = dirs[math.random(4)]
        self.step = 8 + math.random(16)
        self.wait = 50 + math.random(120)
      end
    end
  end
  function n.draw(self)
    local sx, sy = W.to_screen(self.x, self.y)
    local view = FACES[self.face]
    local frame = view == "side" and ((self.step > 0 and (self.t // 10) % 2 == 0) and "_1" or "_0") or "_0"
    if view == "down" and self.step == 0 and (self.t // 40) % 2 == 1 then frame = "_1" end -- breathing
    S.draw("NPC", self.id .. "_" .. view .. frame, sx, sy, {flip = self.face == "left"})
  end
  return E.add(n)
end

return Npc
