-- ¡PULSA!: press A while the marker is over the green. (It leaves the picture darkening: fade.)
local pad = require("pad")
local G = {verb = "¡PULSA!", time = 4, bg = "BG1", timeout = "lose"}
local x, dir, centre, width, speed, t

function G.enter(level, spd)
  x, dir, t = 0, 1, 0
  centre, width, speed = 0.25 + math.random() * 0.5, math.max(0.08, 0.2 - 0.015 * level), (1.1 + 0.15 * level) * spd
end

function G.update()
  t = t + 1
  x = x + dir * speed / 60
  if x > 1 then x, dir = 1, -1 elseif x < 0 then x, dir = 0, 1 end
  fade("dark", ALL, math.min(8, t // 20))
  if pad.btnp("a") then return math.abs(x - centre) < width / 2 and "win" or "lose" end
end

function G.bot(lose)
  if lose then return {} end
  return math.abs(x - centre) < 0.02 and {a = true} or {}
end

function G.draw()
  rect(60, 150, 360, 26, 0x101830)
  rect(60 + 360 * (centre - width / 2), 150, 360 * width, 26, 0x40D060)
  rect(60 + 360 * x - 3, 142, 6, 42, 0xFFE070)
  text("A", 240, 196, {font = "bold", align = "center", color = 0xFFFFFF})
end

return G
