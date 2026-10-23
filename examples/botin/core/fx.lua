-- fx: the little pictures that live a moment (dust, sparks, debris, bubbles, an impact, a splash). Each is a run of frames of FX8 or FX16, moved by a
-- velocity and a gravity, and gone at the end of its frames (or of its life).
local S = require("core.spr")
local Fx = {}

-- kind = {sheet, prefix, frames, every, gravity, drag}
local KINDS = {
  dust = {"FX8", "dust", 4, 5, 0, 0.9}, spark = {"FX8", "spark", 4, 4, 0, 0.9}, smoke = {"FX8", "smoke", 4, 7, -0.01, 0.95},
  bubble = {"FX8", "bubble", 4, 9, -0.02, 0.96}, debris = {"FX8", "debris", 4, 6, 0.22, 0.99}, coin_spark = {"FX8", "coin_spark", 4, 4, 0, 0.9},
  ember = {"FX8", "ember", 4, 7, -0.03, 0.97}, stars = {"FX8", "star_stun", 4, 5, 0, 1},
  impact = {"FX16", "impact", 4, 3, 0, 1}, smash = {"FX16", "smash", 4, 3, 0, 1}, explode = {"FX16", "explode", 6, 4, 0, 1}, flame = {"FX16", "flame", 6, 5, -0.02, 1},
  splash = {"FX16", "splash", 4, 4, 0, 1}, ripple = {"FX16", "ripple", 4, 6, 0, 1}, speed = {"FX16", "speed", 3, 4, 0, 1}, poof = {"FX16", "poof", 4, 5, 0, 1},
  sparkle = {"FX16", "sparkle", 6, 5, 0, 1}, hit = {"FX16", "hit", 3, 3, 0, 1},
}

local list = {}
local keys = {}

function Fx.clear() for i = #list, 1, -1 do list[i] = nil end end

-- Fx.add("dust", x, y, {vx, vy, flip, behind}): x, y is the middle of the picture
function Fx.add(kind, x, y, o)
  local k = KINDS[kind]
  if not k then return end
  if #list > 48 then table.remove(list, 1) end
  o = o or {}
  list[#list + 1] = {k = k, x = x, y = y, vx = o.vx or 0, vy = o.vy or 0, t = 0, flip = o.flip, bank = o.bank, loop = o.loop, life = o.life}
end

function Fx.burst(kind, x, y, n, speed)
  for i = 1, n do
    local a = (i / n) * 6.2832 + (x + y) * 0.1
    Fx.add(kind, x, y, {vx = math.cos(a) * speed, vy = math.sin(a) * speed - 0.6})
  end
end

function Fx.update()
  for i = #list, 1, -1 do
    local f = list[i]
    f.t = f.t + 1
    f.vy = f.vy + f.k[5]
    f.vx, f.vy = f.vx * f.k[6], f.vy * f.k[6]
    f.x, f.y = f.x + f.vx, f.y + f.vy
    local n = f.k[3] * f.k[4]
    if (f.life and f.t >= f.life) or (not f.loop and not f.life and f.t >= n) then table.remove(list, i) end
  end
end

function Fx.draw(cx, cy)
  for _, f in ipairs(list) do
    local id, prefix, n, every = f.k[1], f.k[2], f.k[3], f.k[4]
    local sw = id == "FX8" and 8 or 16
    local frame = (f.t // every) % n
    S.draw(id, prefix .. "_" .. frame, f.x - cx - sw / 2, f.y - cy - sw / 2, {flip = f.flip, bank = f.bank, prio = 0})
  end
end

return Fx
