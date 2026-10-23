-- bot: a very small player for the title's attract mode: runs right, jumps what is in the way and gaps, rams brown blocks. It sets the buttons `In` reads.
local W = require("core.world")
local In = require("core.input")
local B = {}

local a_hold, b_hold, a_delay, t = 0, 0, 0, 0

function B.start() a_hold, b_hold, a_delay, t = 0, 0, 0, 0 In.bot_state = {} end

function B.step(h)
  t = t + 1
  local s = {right = true}
  local fx = math.floor(h.x + h.w + 8) // 16
  local fy = math.floor(h.y + h.h - 4) // 16
  local ahead_solid = W.is_solid(fx, fy) or W.is_solid(fx, fy - 1)
  local gap = h.ground and not W.is_solid(fx, fy + 1) and W.cell(fx, fy + 1) ~= "="
  local breakable = W.BREAKABLE[W.cell(fx, fy)] or W.BREAKABLE[W.cell(fx + 1, fy)]
  if h.ground and b_hold <= 0 and breakable then b_hold = 3 end
  if h.ground and a_hold <= 0 and a_delay <= 0 and (ahead_solid and not breakable or gap) then
    if gap then b_hold, a_delay = 3, 3 else a_hold = 22 end -- a gap is cleared with a run: ram, then jump
  end
  if a_delay > 0 then
    a_delay = a_delay - 1
    if a_delay == 0 then a_hold = 24 end
  end
  if a_hold > 0 then s.a = true a_hold = a_hold - 1 end
  if b_hold > 0 then s.b = true b_hold = b_hold - 1 end
  In.bot_state = s
end

return B
