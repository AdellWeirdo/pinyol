-- fx: the effects that live a moment: hit sparks, steam, flying gears, dust, explosions. Each is a run of frames of a sheet, drawn centred (their anchor is the centre),
-- on the street at (x, y) and z high, painted with the characters by depth.
local S = require("core.spr")
local Fx = {}

-- kind = {sheet, prefix, ticks a frame}; how many frames each has is the sheet's (the art decides)
local KINDS = {
  hit = {"fx_a", "hit", 3}, steam = {"fx_a", "steam", 5}, gears = {"fx_a", "gears", 4}, dust = {"fx_a", "dust", 5}, boom = {"fx_b", "boom", 4},
}
local list = {}

function Fx.clear() for i = #list, 1, -1 do list[i] = nil end end

-- Fx.add("hit", x, y, z [, {vx, vz}])
function Fx.add(kind, x, y, z, o)
  local k = KINDS[kind]
  if not k then return end
  if #list > 50 then table.remove(list, 1) end
  list[#list + 1] = {k = k, x = x, y = y, z = z or 0, vx = o and o.vx or 0, vz = o and o.vz or 0, t = 0}
end

function Fx.update()
  for i = #list, 1, -1 do
    local f = list[i]
    f.t = f.t + 1
    f.x, f.z = f.x + f.vx, f.z + f.vz
    if f.t >= S.n(f.k[1], f.k[2]) * f.k[3] then table.remove(list, i) end
  end
end

-- the effects as things to paint: {y = depth, draw = function(cam)}
function Fx.collect(out, cam)
  for _, f in ipairs(list) do
    out[#out + 1] = {y = f.y + 60, draw = function()
      S.draw(f.k[1], f.k[2] .. "_" .. math.min(S.n(f.k[1], f.k[2]) - 1, f.t // f.k[3]), f.x - cam, f.y - f.z, {})
    end}
  end
end

return Fx
