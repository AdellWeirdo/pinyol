-- input: the buttons the game reads. Normally the console's; in the title's attract mode a little player (`In.bot`) holds them instead, so the demo is the game
-- playing itself with the same code.
local In = {}

In.bot = nil          -- when set, a function(hero) returning a table of buttons held: {right = true, a = true}
local held, prev, buf = {}, {}, {}
In.hero = nil

local NAMES = {"left", "right", "up", "down", "a", "b", "start"}

function In.update()
  for _, n in ipairs(NAMES) do
    prev[n] = held[n]
    held[n] = In.bot and (In.bot_state and In.bot_state[n]) or (not In.bot and btn(n)) or false
    if held[n] and not prev[n] then buf[n] = 0 end
    if buf[n] then buf[n] = buf[n] + 1 end
  end
end

function In.btn(n)
  if In.bot then return held[n] == true end
  return btn(n)
end

function In.btnp(n)
  if In.bot then return held[n] == true and not prev[n] end
  return btnp(n)
end

-- true once if `n` was pressed in the last `window` ticks
function In.btnb(n, window)
  if In.bot then
    if buf[n] and buf[n] <= (window or 6) then buf[n] = nil return true end
    return false
  end
  return btnb(n, window)
end

return In
