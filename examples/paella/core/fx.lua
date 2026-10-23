-- fx: the effects that live a moment: explosions, smoke, feathers, hit stars. Each is a run of frames of a sheet, drawn centred (their anchor is the centre).
local S = require("core.spr")
local Fx = {}

local KINDS = {
  boom_s = {"explosions", "boom_s", 8, 2}, boom_m = {"explosions", "boom_m", 10, 2}, boom_l = {"explosions", "boom_l", 12, 3}, boom_grenade = {"explosions", "boom_grenade", 10, 3},
  smoke = {"explosions", "smoke", 8, 4}, feathers = {"explosions", "feathers", 8, 5}, hit = {"shots", "hit", 4, 2},
}
local list = {}

function Fx.clear() for i = #list, 1, -1 do list[i] = nil end end

-- Fx.add("boom_m", x, y [, {vx, vy, flip, behind}])
function Fx.add(kind, x, y, o)
  local k = KINDS[kind]
  if not k then return end
  if #list > 60 then table.remove(list, 1) end
  list[#list + 1] = {k = k, x = x, y = y, vx = o and o.vx or 0, vy = o and o.vy or 0, t = 0, flip = o and o.flip}
end

function Fx.update()
  for i = #list, 1, -1 do
    local f = list[i]
    f.t = f.t + 1
    f.x, f.y = f.x + f.vx, f.y + f.vy
    if f.t >= f.k[3] * f.k[4] then table.remove(list, i) end
  end
end

function Fx.draw(cam)
  for _, f in ipairs(list) do
    S.draw(f.k[1], f.k[2] .. "_" .. (f.t // f.k[4]), f.x - cam, f.y, {flip = f.flip})
  end
end

return Fx
