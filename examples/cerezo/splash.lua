-- splash: the first thing: the way a Game Boy opened. A light screen, the maker's mark falls from the top, lands in the middle with
-- its two-note ding and stays a moment. (The engine puts its own seal, POWERED BY PINYOL, over every careta.)
local careta = {}

local LIGHT, MID, DARK, INK = 0x9BBC0F, 0x8BAC0F, 0x306230, 0x0F380F
local LAND = 112  -- screen pixel row where the mark stops
local FALL = 5    -- pixels a tick

-- a cherry pair, drawn with shapes: two stones on bent stems and a leaf
local function cherries(x, y)
  line(x, y - 22, x - 10, y - 2, INK) line(x, y - 22, x + 10, y - 2, INK)
  line(x + 1, y - 22, x - 9, y - 2, INK) line(x + 1, y - 22, x + 11, y - 2, INK)
  circ(x - 10, y + 4, 8, INK, true) circ(x + 10, y + 4, 8, INK, true)
  circ(x - 10, y + 4, 6, DARK, true) circ(x + 10, y + 4, 6, DARK, true)
  circ(x - 12, y + 1, 2, LIGHT, true) circ(x + 8, y + 1, 2, LIGHT, true)
  tri(x, y - 22, x + 16, y - 28, x + 10, y - 18, INK)
  tri(x + 2, y - 22, x + 13, y - 26, x + 9, y - 20, MID)
end

function careta.update(t)
  if t == 1 then
    sound("SPLASH_A", {wave = "square", duty = 0.5, freq = 1046, sustain = 0.08, decay = 0.2, volume = 0.3})
    sound("SPLASH_B", {wave = "square", duty = 0.5, freq = 1568, sustain = 0.25, decay = 0.5, volume = 0.3})
  end
  local land_t = (LAND + 40) // FALL
  if t == land_t then sfx("SPLASH_A") end
  if t == land_t + 8 then sfx("SPLASH_B") end
  return t >= 170
end

function careta.draw(t)
  rect(0, 0, 480, 320, LIGHT)
  local y = math.min(LAND, -30 + t * FALL)
  cherries(240, y)
  if y >= LAND then
    text("pinyol", 240, LAND + 32, {font = "ps", color = INK, align = "center"})
  end
end

return careta
