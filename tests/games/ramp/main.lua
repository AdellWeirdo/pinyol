-- line_ramp (tests/ramp.script): the backdrop (palette entry 0) in three gradients, drawn either by line_ramp or by line_pal on every line
-- with the same arithmetic done here; the two pictures must be the same.
mode = "ramp" -- or "pal"
local RAMPS = { -- y0, y1, from, to, curve
  {0, 59, 0x102040, 0xF0C080, 1},
  {60, 119, 0x00FF00, 0xFF00FF, 1.5},
  {159, 120, 0xFFFFFF, 0x203010, 0.7},
}

local function round(x) return x >= 0 and math.floor(x + 0.5) or -math.floor(-x + 0.5) end

local function by_pal(y0, y1, a, b, curve)
  local ar, ag, ab = a >> 16 & 255, a >> 8 & 255, a & 255
  local br, bg, bb = b >> 16 & 255, b >> 8 & 255, b & 255
  local step, n = y1 >= y0 and 1 or -1, math.abs(y1 - y0)
  for i = 0, n do
    local k = n > 0 and i / n or 0
    if curve ~= 1 then k = k ^ curve end
    line_pal(y0 + i * step, 0, rgb(ar + round((br - ar) * k), ag + round((bg - ag) * k), ab + round((bb - ab) * k)))
  end
end

function _init() end
function _update() end
function _draw()
  line_off()
  for _, r in ipairs(RAMPS) do
    if mode == "ramp" then line_ramp(r[1], r[2], 0, r[3], r[4], r[5]) else by_pal(r[1], r[2], r[3], r[4], r[5]) end
  end
end
