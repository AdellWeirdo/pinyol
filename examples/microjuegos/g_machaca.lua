-- ¡MACHACA!: A, as many times as you can, before the picture closes round the middle. (It leaves a round window: line_window.)
local pad = require("pad")
local fx = require("fx")
local G = {verb = "¡MACHACA!", time = 4, bg = "BG1", timeout = "lose"}
local need, count, t, k, total, sheet_

function G.enter(level, spd)
  sheet_ = sheet("THINGS")
  need, count, t, k = 8 + 2 * level, 0, 0, 0
  total = math.floor(4 * 60 / spd)
end

function G.update()
  t = t + 1
  if pad.btnp("a") then count = count + 1 end
  fx.circle(120, 80, 140 * (1 - t / total) + 8)
  if count >= need then return "win" end
end

function G.bot(lose)
  k = k + 1
  if lose then return {} end
  return k % 4 == 0 and {a = true} or {}
end

function G.draw()
  spr(0, sheet_, 0, 112, 72, prio(1))
  rect(80, 270, 320, 20, 0x101830)
  rect(80, 270, math.floor(320 * count / need), 20, 0xFF7050)
  text(string.format("%d/%d", count, need), 240, 296, {font = "bold", align = "center", color = 0xFFFFFF})
end

return G
