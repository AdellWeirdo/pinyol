-- ¡GIRA!: turn the arrow (left and right) till it points where the pale one does, and press A. (It leaves a blend and turned sprites.)
local pad = require("pad")
local G = {verb = "¡GIRA!", time = 5, bg = "BG3", timeout = "lose"}
local target, angle, sheet_

function G.enter(level, spd)
  sheet_ = sheet("THINGS")
  target = math.random(2, 10) * 30 % 360
  angle = 0
  blend(OBJ, BG3, 8, 8)
end

function G.update()
  local d = (pad.btn("right") and 1 or 0) - (pad.btn("left") and 1 or 0)
  angle = (angle + d * 3) % 360
  if pad.btnp("a") then
    local diff = math.abs((angle - target + 180) % 360 - 180)
    return diff < 10 and "win" or "lose"
  end
end

function G.bot(lose)
  if lose then return {} end
  local diff = (target - angle + 180) % 360 - 180
  if math.abs(diff) < 4 then return {a = true} end
  return diff > 0 and {right = true} or {left = true}
end

function G.draw()
  mat(1, target, 3, 3)
  spr(1, sheet_, 3, 96, 56, prio(1) | spr_mat(1) | DOUBLE | BLEND)
  mat(0, angle, 3, 3)
  spr(0, sheet_, 3, 96, 56, prio(0) | spr_mat(0) | DOUBLE)
end

return G
