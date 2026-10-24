-- props: the things of the street that break: barrels, crates, lamps, clock cases, mailboxes, pipes. A blow breaks them (they are targets like the foes) and they leave a heap and
-- what was inside (a part, oil, a watch: the play module decides through `on_break`).
local C = require("core.const")
local U = require("core.util")
local S = require("core.spr")
local Fx = require("core.fx")
local Sound = require("core.sound")
local Run = require("core.run")
local P = {}

P.list = {}
P.on_break = nil
local HP = {barrel = 12, crate = 14, lamp = 20, clocks = 16, mailbox = 18, pipes = 14}

local E = {}
E.__index = E

function P.clear() for i = #P.list, 1, -1 do P.list[i] = nil end end

function P.add(kind, x, y)
  P.list[#P.list + 1] = setmetatable({kind = kind, x = x, y = y or math.random(C.Y_MIN + 6, C.Y_MAX - 6), z = 0, hw = 22, hp = HP[kind] or 12, alive = true, flash = 0, t = 0,
                                      last_atk = 0, ent = true}, E)
end

function E:hit(dmg, dir, flags, atkid)
  if not self.alive or (atkid > 0 and self.last_atk == atkid) then return false end
  self.last_atk = atkid
  self.hp = self.hp - dmg
  if U.blink(self) then self.flash = 4 end
  if self.hp <= 0 then
    self.alive = false
    self.t = 0
    Run.props = Run.props + 1
    Run.add(100)
    Sound.play("break_")
    Fx.add("gears", self.x, self.y, 50)
    Fx.add("dust", self.x, self.y, 20)
    if P.on_break then P.on_break(self) end
  else
    Sound.play("clank", 0.6)
  end
  return true
end

function P.update(cam)
  for i = #P.list, 1, -1 do
    local p = P.list[i]
    p.t = p.t + 1
    if p.flash > 0 then p.flash = p.flash - 1 end
    if (not p.alive and p.t > 240) or p.x < cam - 200 then table.remove(P.list, i) end
  end
end

function P.collect(out, cam)
  for _, p in ipairs(P.list) do
    if p.x > cam - 120 and p.x < cam + C.W + 120 then
      out[#out + 1] = {y = p.y - 1, draw = function()
        local sx = p.x - cam
        if p.alive then
          S.draw("props_a", p.kind, sx, p.y, {tint = p.flash > 0 and 0xFFFFFF or nil, dx = p.flash > 0 and (p.t % 2 * 2 - 1) or 0})
        else
          S.draw("props_b", p.kind .. "_b", sx, p.y, {alpha = p.t > 200 and ((p.t // 4) % 2 == 0 and 0.4 or 1) or nil})
        end
      end}
    end
  end
end

return P
