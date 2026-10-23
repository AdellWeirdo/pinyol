-- tape: the loading, as a Spectrum showed it: the border in red and cyan stripes while the pilot tone sounds, then blue and yellow
-- as the data comes; the picture's bitmap arrives in the machine's own order (a third at a time, a line of each character row
-- before the next), black on white, and then its colours, row by row. A skips it. With "less flashing" on, the border does not
-- strobe: it is one plain colour.
local Z = require("core.zx")
local H = require("core.hud")
local T = {}

T.PILOT, T.DATA, T.COLOURS = 120, 240, 60
T.TOTAL = T.PILOT + T.DATA + T.COLOURS

local function stripes(t, a, b, h, calm)
  if calm then rect(0, 0, 480, 320, a) return end
  local y = -(t * 7 % (2 * h))
  local k = 0
  while y < 320 do
    local hh = h > 4 and h or 1 + (noise(y, t) * 4 + 4) // 1
    rect(0, y, 480, hh, k % 2 == 0 and a or b)
    y, k = y + hh, k + 1
  end
end

-- the picture, `lines` of it come and `rows` of block rows coloured
function T.picture(lines, rows)
  rect(16, 16, 448, 288, Z.BWHITE) -- the paper before anything comes
  local run = nil
  for y = 0, 144 do
    local come = y < 144 and (y // 48) * 48 + (y % 8) * 6 + (y % 48) // 8 < lines
    if come and not run then run = y end
    if not come and run then
      clip(16, 16 + run * 2, 448, (y - run) * 2)
      img("LOAD_MONO", 16, 16)
      run = nil
    end
  end
  if rows > 0 then
    clip(16, 16, 448, rows * 16)
    img("LOAD", 16, 16)
  end
  clip()
end

function T.draw(t, calm)
  if t < T.PILOT then stripes(t, Z.rgb("red", false), Z.rgb("cyan", false), 12, calm)
  elseif t < T.TOTAL then stripes(t, Z.rgb("blue", false), Z.rgb("yellow", false), 3, calm)
  else rect(0, 0, 480, 320, Z.BLACK) end
  local lines = math.max(0, math.min(144, (t - T.PILOT) * 144 // T.DATA))
  local rows = math.max(0, math.min(18, (t - T.PILOT - T.DATA) * 18 // T.COLOURS))
  T.picture(lines, rows)
end

return T
