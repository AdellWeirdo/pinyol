-- zx: the Spectrum's colours. Eight colours, each normal or bright (a block is one or the other, both its ink and its paper:
-- the BRIGHT bit of the attribute). A room's scheme says "ink/paper" for each kind of block, with a "+" for bright.
local Z = {}

local N = {black = {0, 0, 0}, blue = {0, 0, 1}, red = {1, 0, 0}, magenta = {1, 0, 1}, green = {0, 1, 0}, cyan = {0, 1, 1},
           yellow = {1, 1, 0}, white = {1, 1, 1}}
Z.NAMES = {"black", "blue", "red", "magenta", "green", "cyan", "yellow", "white"}

function Z.rgb(name, bright)
  local c = N[name]
  if not c then error("no colour " .. tostring(name), 2) end
  local v = bright and 0xFF or 0xD7
  return (c[1] * v << 16) | (c[2] * v << 8) | c[3] * v
end

-- "+green/black" -> ink, paper (as 0xRRGGBB)
function Z.attr(s)
  local bright = s:sub(1, 1) == "+"
  local ink, paper = s:match("^%+?(%a+)/(%a+)$")
  if not ink then error("a colour pair is ink/paper, not " .. s, 2) end
  return Z.rgb(ink, bright), Z.rgb(paper, bright)
end

-- the colour of the border: a plain name
Z.BLACK, Z.WHITE, Z.BYELLOW, Z.BWHITE, Z.BRED, Z.BGREEN, Z.BCYAN = 0x000000, 0xD7D7D7, 0xFFFF00, 0xFFFFFF, 0xFF0000, 0x00FF00, 0x00FFFF

return Z
