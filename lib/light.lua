-- light: a palette lit by a lamp. Pixel art that is to be lit is drawn with a palette whose entries mean surfaces
-- (this index faces up and left, that one faces the viewer, that one down), as the "normal map palettes" of the
-- GBA and DS era did; the library turns the lamp's direction into the entries' colours, so a ball, a cave or a
-- face turns towards a torch that moves, with no shading drawn by hand.
--
--   local light = require("light")
--   local ball = light.new({
--     bank = 2, obj = true,                           -- the sprites' palette, bank 2 (entries 32..47); obj = false: the backgrounds'
--     base = {[1] = 0xD04030, [2] = 0xD04030, [3] = 0xD04030, [4] = 0x402020},  -- each entry's colour in flat light
--     normals = {[1] = {0, -1, 0.3}, [2] = {0.7, -0.7, 0.3}, [3] = {0, 0, 1}, [4] = {0, 1, 0.3}},  -- which way each faces: x right, y down, z out
--     ambient = 0.25,                                 -- how lit a surface facing away still is
--   })
--   ball:set(lamp_x - ball_x, lamp_y - ball_y, 40)    -- the lamp, from the thing's centre (any scale: it is normalised)
--   ball:set(nil)                                     -- flat light: the base colours
--
-- light.shade(normal, dir, ambient) -> 0..1 is the lighting of one surface, for a game that wants the number.
local M = {}
local L = {}
L.__index = L

local function unit(x, y, z)
  local n = math.sqrt(x * x + y * y + z * z)
  if n < 1e-6 then return 0, 0, 1 end
  return x / n, y / n, z / n
end

function M.shade(normal, dir, ambient)
  local nx, ny, nz = unit(normal[1], normal[2], normal[3])
  local lx, ly, lz = unit(dir[1], dir[2], dir[3])
  local d = nx * lx + ny * ly + nz * lz
  if d < 0 then d = 0 end
  ambient = ambient or 0.25
  return ambient + (1 - ambient) * d
end

local function scaled(colour, k) -- a 0xRRGGBB colour times k (over 1 brightens towards white)
  local r, g, b = colour >> 16 & 255, colour >> 8 & 255, colour & 255
  if k <= 1 then
    r, g, b = r * k, g * k, b * k
  else
    local w = math.min(1, k - 1)
    r, g, b = r + (255 - r) * w, g + (255 - g) * w, b + (255 - b) * w
  end
  return math.floor(r + 0.5) << 16 | math.floor(g + 0.5) << 8 | math.floor(b + 0.5)
end

function M.new(opts)
  assert(opts and opts.base and opts.normals, "light.new: base colours and normals are needed")
  local l = setmetatable({bank = opts.bank or 0, obj = opts.obj ~= false, base = opts.base, normals = opts.normals,
                          ambient = opts.ambient or 0.25, gain = opts.gain or 1, lit = {}}, L)
  l:set(nil)
  return l
end

-- set(x, y, z): the lamp's direction from the thing (or nil: flat light); the palette's entries are written
function L:set(x, y, z)
  local o = self.bank * 16
  for i, colour in pairs(self.base) do
    local k = 1
    if x then
      local n = self.normals[i]
      k = n and M.shade(n, {x, y, z}, self.ambient) * self.gain or 1
    end
    local c = scaled(colour, k)
    self.lit[i] = c
    pal(o + i, c, self.obj)
  end
end

return M
