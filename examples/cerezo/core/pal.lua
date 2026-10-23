-- pal: the four tones and how they are shown. A mode is a set of palettes (data/palettes.lua), the Game Boy's greens,
-- the Pocket's greys, a Super Game Boy's colours, or the Color's banks; a fade is the console's way: every tone moves
-- toward the lightest or the darkest one step, four steps in all, which is what writing the palette register did.
local D = require("data.palettes")
local P = {}

P.modes = D.modes
P.mode = 1
P.kind, P.level = "light", 0 -- the fade: "light" or "dark", 0 (none) to 3 (all the way)

-- tone i (1 lightest .. 4 darkest) shows tone MAP[level][i]
local MAPS = {
  light = {{1, 2, 3, 4}, {1, 1, 2, 3}, {1, 1, 1, 2}, {1, 1, 1, 1}},
  dark = {{1, 2, 3, 4}, {2, 3, 4, 4}, {3, 4, 4, 4}, {4, 4, 4, 4}},
}

local function apply()
  local m = P.modes[P.mode]
  local map = MAPS[P.kind][P.level + 1]
  for b = 0, 7 do
    for i = 1, 4 do
      pal(16 * b + i, m.bg[b + 1][map[i]])
      pal(16 * b + i, m.obj[b + 1][map[i]], true)
    end
  end
  backdrop(m.bg[1][map[1]])
end

function P.set_mode(i)
  P.mode = (i - 1) % #P.modes + 1
  apply()
end

-- a fade to white (kind "light") or to the darkest tone ("dark"), level 0 to 3
function P.fade(kind, level)
  P.kind, P.level = kind, level
  apply()
end

function P.init(mode)
  P.mode, P.kind, P.level = mode or 1, "light", 0
  apply()
end

-- the colour a tone has now (for text and shapes drawn over the world): 1 lightest .. 4 darkest
function P.tone(i)
  local map = MAPS[P.kind][P.level + 1]
  return P.modes[P.mode].bg[1][map[i]]
end

function P.name() return P.modes[P.mode].name end

return P
