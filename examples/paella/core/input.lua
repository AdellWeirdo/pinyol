-- input: the buttons the game reads: the console's, or, in the title's attract mode, the little player `Bot` holds them (the demo is the game playing itself).
local In = {}
In.bot = nil
In.state = {}
local held, prev = {}, {}
local NAMES = {"left", "right", "up", "down", "a", "b", "c", "start"}

function In.update()
  for _, n in ipairs(NAMES) do
    prev[n] = held[n]
    if In.bot then held[n] = In.state[n] == true else held[n] = btn(n) end
  end
end

function In.btn(n) if In.bot then return held[n] == true end return btn(n) end
function In.btnp(n) if In.bot then return held[n] == true and not prev[n] end return btnp(n) end

return In
