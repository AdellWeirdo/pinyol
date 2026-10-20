-- ¡JEFE!: the last one, with no time limit: A, sixty times. (It leaves a mosaic that grows with the effort.)
local pad = require("pad")
local G = {verb = "¡JEFE!", time = nil, bg = "BG3", boss = true}
local count, need, k, sheet_

function G.enter()
  sheet_ = sheet("THINGS")
  count, need, k = 0, 60, 0
end

function G.update()
  if pad.btnp("a") then count = count + 1 end
  local m = 1 + count // 10
  mosaic(m, m, m, m)
  if count >= need then return "win" end
end

function G.bot(lose)
  k = k + 1
  if lose then return {} end
  return k % 3 == 0 and {a = true} or {}
end

function G.draw()
  spr(0, sheet_, 6, 104 + (count % 2) * 2, 56, prio(1) | MOSAIC)
  rect(60, 270, 360, 20, 0x101830)
  rect(60, 270, math.floor(360 * count / need), 20, 0xFFB030)
  text("A  A  A  A", 240, 296, {font = "bold", align = "center", color = 0xFFFFFF})
end

return G
