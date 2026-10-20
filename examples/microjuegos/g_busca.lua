-- ¡BUSCA!: a spot of light, and one star that is not like the others; move the light and choose it. (It leaves a round window.)
local pad = require("pad")
local fx = require("fx")
local G = {verb = "¡BUSCA!", time = 7, bg = "BG2", timeout = "lose"}
local cols, rows, odd, cx, cy, t, k, sheet_

function G.enter(level, spd)
  sheet_ = sheet("THINGS")
  cols, rows, t, k = 4, 3, 0, 0
  odd = {x = math.random(0, cols - 1), y = math.random(0, rows - 1)}
  cx, cy = 0, 0
end

function G.update()
  t = t + 1
  if pad.btnp("right") then cx = math.min(cols - 1, cx + 1) elseif pad.btnp("left") then cx = math.max(0, cx - 1) end
  if pad.btnp("down") then cy = math.min(rows - 1, cy + 1) elseif pad.btnp("up") then cy = math.max(0, cy - 1) end
  fx.circle(40 + cx * 53 + 8, 34 + cy * 40 + 8, 26)
  if pad.btnp("a") then return (cx == odd.x and cy == odd.y) and "win" or "lose" end
end

function G.bot(lose)
  k = k + 1
  if k % 8 ~= 0 then return {} end
  if lose then return {a = true} end
  if cx < odd.x then return {right = true} elseif cx > odd.x then return {left = true} end
  if cy < odd.y then return {down = true} elseif cy > odd.y then return {up = true} end
  return {a = true}
end

function G.draw()
  local i = 0
  for y = 0, rows - 1 do
    for x = 0, cols - 1 do
      spr(i, sheet_, (x == odd.x and y == odd.y) and 5 or 4, 40 + x * 53, 34 + y * 40, prio(1))
      i = i + 1
    end
  end
end

return G
