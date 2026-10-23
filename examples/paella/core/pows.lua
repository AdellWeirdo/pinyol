-- pows: the people the gulls tied up (an abuela, a fisherman). Shoot or stab their ropes and they jump up, hand over a crate that upgrades the chef's weapon, and run off. At the end
-- the mission gives a bonus for each one freed; they cannot be hurt.
local C = require("core.const")
local S = require("core.spr")
local Fx = require("core.fx")
local Sound = require("core.sound")
local Music = require("core.music")
local Run = require("core.run")
local P = {}

P.list = {}
P.items = nil

function P.clear() for i = #P.list, 1, -1 do P.list[i] = nil end end

function P.add(kind, x, crate)
  P.list[#P.list + 1] = {kind = kind, x = x, crate = crate, state = "tied", st = 0, t = 0}
  Run.pows_total = Run.pows_total + 1
end

function P.hit(x, y, r)
  for _, p in ipairs(P.list) do
    if p.state == "tied" and x > p.x - 34 and x < p.x + 34 and y > C.FLOOR - 94 and y < C.FLOOR + 4 then
      p.state, p.st = "free", 0
      Sound.play("rescue", 0.6)
      Fx.add("boom_s", p.x, C.FLOOR - 40)
      return true
    end
  end
  return false
end

function P.update(chef)
  for i = #P.list, 1, -1 do
    local p = P.list[i]
    p.t = p.t + 1
    p.st = p.st + 1
    if p.state == "tied" then
      -- a chef's knife frees them too
      if chef.state == "play" and chef.stab_t > 0 and math.abs(chef.x - p.x) < 80 then P.hit(p.x, C.FLOOR - 40, 10) end
    elseif p.state == "free" then
      if p.st >= 24 then p.state, p.st = "give", 0 end
    elseif p.state == "give" then
      if p.st == 20 then
        if P.items then P.items.crate(p.crate or "a", p.x + 30) end
        Run.pows = Run.pows + 1
        Run.add(500)
        Music.jingle("rescate", 2)
      end
      if p.st >= 36 then p.state, p.st = "run", 0 end
    elseif p.state == "run" then
      p.x = p.x - 3
      if p.x < (P.cam or 0) - 120 then table.remove(P.list, i) end
    end
  end
end

function P.draw(cam)
  for _, p in ipairs(P.list) do
    local sx = p.x - cam
    if sx > -100 and sx < C.W + 100 then
      local f
      if p.state == "tied" then f = "tied_" .. (p.t // 8) % 6
      elseif p.state == "free" then f = "free_" .. math.min(3, p.st // 6)
      elseif p.state == "give" then f = "give_" .. math.min(5, p.st // 6)
      else f = "run_" .. (p.t // 3) % 8 end
      S.draw(p.kind, f, sx, C.FLOOR, {flip = p.state == "run" and false or false})
    end
  end
end

return P
