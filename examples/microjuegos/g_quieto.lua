-- ¡NO TOQUES!: nothing at all, until the time is out. (It leaves the LED red, a synthesised note sounding and the backdrop hidden: scene.clean puts them back.)
local pad = require("pad")
local G = {verb = "¡NO TOQUES!", time = 3, bg = "BG1", timeout = "win"}
local t

function G.enter()
  t = 0
  led(0xFF2000)
  show(OBJ) -- (only the sprites: the backdrop goes dark)
  tone(0, "A4", {wave = "square", vol = 0.15, sustain = 1})
end

function G.update()
  t = t + 1
  if t > 12 and pad.any() then return "lose" end
end

function G.bot(lose)
  if lose and t == 20 then return {a = true} end
  return {}
end

function G.draw()
  text("quieto...", 240, 150, {font = "large_bold", align = "center", color = 0xFFFFFF})
end

return G
