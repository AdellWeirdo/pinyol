-- props: barrels and fish crates that break when shot (and may hold food), and a buoy that rolls. Scenery you can play with, as Metal Slug's crates.
local C = require("core.const")
local S = require("core.spr")
local Fx = require("core.fx")
local Sound = require("core.sound")
local Run = require("core.run")
local P = {}

P.list = {}
P.items = nil

function P.clear() for i = #P.list, 1, -1 do P.list[i] = nil end end

function P.add(kind, x)
  P.list[#P.list + 1] = {kind = kind, x = x, hp = kind == "buoy" and 99 or 3, st = 0, t = 0, vx = 0}
end

function P.hit(x, y, r)
  for _, p in ipairs(P.list) do
    if p.kind ~= "buoy" and p.hp > 0 and x > p.x - 32 and x < p.x + 32 and y > C.FLOOR - 64 and y < C.FLOOR + 4 then
      p.hp = p.hp - 1
      p.shake = 6
      Sound.play("clank", 0.4)
      if p.hp <= 0 then
        Run.add(50)
        Fx.add("boom_s", p.x, C.FLOOR - 24)
        Fx.add("feathers", p.x, C.FLOOR - 30)
        Sound.play("boom", 0.5)
        if P.items then P.items.drop(p.x, C.FLOOR, "prop") end
      end
      return true
    end
  end
  return false
end

function P.blast(x, y, r)
  for _, p in ipairs(P.list) do
    if p.kind ~= "buoy" and p.hp > 0 and math.abs(p.x - x) < r + 20 and math.abs(C.FLOOR - y) < r + 30 then
      p.hp = 0
      Run.add(50)
      Fx.add("boom_s", p.x, C.FLOOR - 24)
      if P.items then P.items.drop(p.x, C.FLOOR, "prop") end
    end
  end
end

function P.update(chef)
  for i = #P.list, 1, -1 do
    local p = P.list[i]
    p.t = p.t + 1
    if p.shake and p.shake > 0 then p.shake = p.shake - 1 end
    if p.hp <= 0 then
      p.st = p.st + 1
      if p.st > 24 then table.remove(P.list, i) end
    elseif p.kind == "buoy" then
      -- a buoy rolls away from a chef who walks into it
      if math.abs(chef.x - p.x) < 34 and chef.y > C.FLOOR - 30 then p.vx = (p.x > chef.x and 1 or -1) * 2 end
      p.x = p.x + p.vx
      p.vx = p.vx * 0.97
    end
  end
end

function P.draw(cam)
  for _, p in ipairs(P.list) do
    local sx = p.x - cam
    if sx > -80 and sx < C.W + 80 then
      if p.kind == "buoy" then
        S.draw("props", "buoy_" .. (math.floor(p.x / 12) % 4), sx, C.FLOOR, {})
      else
        local k = p.hp <= 0 and math.min(5, 3 + p.st // 8) or (3 - p.hp)
        S.draw("props", p.kind .. "_" .. k, sx + ((p.shake or 0) % 2 == 1 and 2 or 0), C.FLOOR, {})
      end
    end
  end
end

return P
