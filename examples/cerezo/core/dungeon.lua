-- dungeon: what makes a dungeon a dungeon: doors that shut until the room is cleared or a switch is pressed, doors
-- that want a key, blocks that are pushed onto switches and into pits, a key that falls when the last pest does, rooms
-- so dark that the lantern is what you see by. Everything here is a "thing" of the room's map (core/things.lua).
local C = require("core.const")
local U = require("core.util")
local W = require("core.world")
local S = require("core.spr")
local E = require("core.ents")
local Game = require("core.game")
local FX = require("core.fx")
local Sound = require("core.sound")
local Things = require("core.things")
local D = {}

-- the pests alive in the screen now (the ones that count to clear a room)
function D.enemies_left()
  local n = 0
  for e in E.each("enemy") do if not e.dead and not e.def_ignore then n = n + 1 end end
  for e in E.each("boss") do if not e.dead then n = n + 1 end end
  return n
end

-- ------------------------------------------------------------------ gates: shut until their rule is met
-- def: cx, cy (the door's cell), shut = metatile when shut, open = metatile when open,
--      rule = "clear" (no pests left) or "flag" (Game.flags[def.flag])
Things.kinds.gate = function(def)
  local e = {kind = "gate", x = def.cx * C.T, y = def.cy * C.T, hw = 0, hh = 0, state = nil}
  local function met()
    if def.rule == "flag" then return Game.flags[def.flag] == true end
    return D.enemies_left() == 0
  end
  local function hero_in_door() -- a door does not shut on the hero standing in it
    local h = E.hero
    return h and U.overlap(h.x + 3, h.y + 8, 10, 7, def.cx * C.T, def.cy * C.T, C.T, C.T)
  end
  function e.update(self)
    local ok = met()
    if self.state == nil then
      if not ok and hero_in_door() then return end
      self.state = ok and "open" or "shut"
      W.show(def.cx, def.cy, self.state == "open" and def.open or def.shut)
      W.cells[W.index(def.cx, def.cy)] = W.id_of(self.state == "open" and def.open or def.shut)
      return
    end
    if ok and self.state == "shut" then
      self.state = "open"
      W.cells[W.index(def.cx, def.cy)] = W.id_of(def.open)
      W.show(def.cx, def.cy, def.open)
      Sound.play("secret")
    elseif not ok and self.state == "open" and def.rule == "flag" and not hero_in_door() then
      self.state = "shut"
      W.cells[W.index(def.cx, def.cy)] = W.id_of(def.shut)
      W.show(def.cx, def.cy, def.shut)
    end
  end
  return E.add(e)
end

-- ------------------------------------------------------------------ doors that want a key
-- def: cx, cy, open = the metatile once opened, boss = true for the boss key
Things.kinds.lock = function(def)
  local e = {kind = "lock", x = def.cx * C.T, y = def.cy * C.T, solid = false, hx = 0, hy = 0, hw = 16, hh = 16}
  local dungeon = def.dungeon or "raiz"
  function e.interact(self, hero)
    local have = def.boss and Game.bosskeys[dungeon] or (Game.keys[dungeon] or 0) > 0
    if have then
      if def.boss then Game.bosskeys[dungeon] = nil else Game.keys[dungeon] = Game.keys[dungeon] - 1 end
      W.set(def.cx, def.cy, def.open)
      Sound.play("door")
      FX.dust(self.x + 8, self.y + 8)
      self.dead = true
    else
      Sound.play("deny")
      require("core.dialog").start(def.boss and "puerta_jefe" or "puerta_cerrada")
    end
  end
  return E.add(e)
end

-- ------------------------------------------------------------------ a key that falls when the room is cleared
Things.kinds.keydrop = function(def)
  if def.flag and Game.flags[def.flag] then return nil end
  local e = {kind = "keydrop", x = def.cx * C.T, y = def.cy * C.T, t = 0, shown = false, hw = 16, hh = 16, hx = 0, hy = 0, sort = 8}
  function e.update(self)
    if not self.shown then
      if D.enemies_left() == 0 then
        self.shown, self.z = true, 60
        Sound.play("secret")
      end
      return
    end
    self.t = self.t + 1
    if self.z > 0 then self.z = math.max(0, self.z - 3) end
    local h = E.hero
    if self.z == 0 and U.overlap(self.x + 2, self.y + 2, 12, 12, h.x + 4, h.y + 6, 8, 8) then
      if def.flag then Game.flags[def.flag] = true end
      self.dead = true
      require("core.rewards").get(def.item or "llave_pequena")
    end
  end
  function e.draw(self)
    if not self.shown then return end
    local sx, sy = W.to_screen(self.x, self.y - self.z + math.floor(math.sin(self.t / 10) * 1.5))
    S.draw("ITEMS16", def.item or "llave_pequena", sx, sy)
  end
  return E.add(e)
end

-- ------------------------------------------------------------------ pits: the hero falls, loses half a heart, and
-- is put back where he last stood safe
function D.update_hero_pit(h)
  if h.state ~= "walk" then return end
  local fx, fy = h.x + 8, h.y + 12
  local f = W.cell_flags(math.floor(fx / C.T), math.floor(fy / C.T))
  if f and f.pit then
    local fc = require("core.hero")
    h.fall_from = h.safe or {h.x, h.y}
    fc.set(h, "fall")
    Sound.play("hurt")
  else
    h.safe_t = (h.safe_t or 0) + 1
    if h.safe_t > 8 and h.moving then h.safe = {h.x, h.y} h.safe_t = 0 end
  end
end

-- ------------------------------------------------------------------ blocks to push
-- def: cx, cy. A block moves one cell at a time when he leans on it, onto a floor, a switch or into a pit (which it fills).
Things.kinds.block = function(def)
  local e = {kind = "block", id = "block", x = def.cx * C.T, y = def.cy * C.T, solid = true, hx = 0, hy = 0, hw = 16, hh = 16, push = 0,
             sort = 8, move_t = 0}
  function e.update(self)
    if self.move_t > 0 then
      self.move_t = self.move_t - 1
      self.x, self.y = self.x + self.mvx, self.y + self.mvy
      if self.move_t == 0 then
        self.x, self.y = math.floor(self.x + 0.5), math.floor(self.y + 0.5)
        local gx, gy = math.floor((self.x + 8) / C.T), math.floor((self.y + 8) / C.T)
        local f = W.cell_flags(gx, gy)
        if f and f.pit then
          W.set(gx, gy, "pit_filled")
          Sound.play("chest")
          self.dead = true
        elseif f and f.switch_floor then
          D.press(def.flag or ("sw_" .. gx .. "_" .. gy))
        end
      end
      return
    end
    local h = E.hero
    if h.state == "walk" and h.moving then
      local d = U.DIRS[h.face]
      -- is he leaning on it, from the front?
      local bx, by = h.x + 3 + d[1] * 2, h.y + 8 + d[2] * 2
      if U.overlap(bx, by, 10, 7, self.x, self.y, 16, 16) then
        self.push = self.push + 1
        h.pushing, h.pushing_t = true, 2
        if self.push >= 26 then
          self.push = 0
          local nx, ny = self.x + d[1] * C.T, self.y + d[2] * C.T
          local f = W.cell_flags(math.floor((nx + 8) / C.T), math.floor((ny + 8) / C.T))
          if f and not f.solid and not f.water and not E.solid_at(nx + 2, ny + 2, 12, 12, self) then
            self.mvx, self.mvy, self.move_t = d[1], d[2], 16
            Sound.play("dig")
          end
        end
      else
        self.push = 0
      end
    else
      self.push = 0
    end
  end
  function e.draw(self)
    local sx, sy = W.to_screen(self.x, self.y)
    S.draw("PROPS", "block", sx, sy)
  end
  return E.add(e)
end

-- a floor switch pressed: its flag is set for good (a gate watches it)
function D.press(flag)
  if not Game.flags[flag] then
    Game.flags[flag] = true
    Sound.play("secret")
    FX.shake(1, 6)
  end
end

-- the eye in the wall: hit it with a pinyol (core/shot.lua calls this)
require("core.switches")

return D
