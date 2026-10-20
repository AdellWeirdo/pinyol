-- title: a new descent, or the day's (the same chasm for everyone that day, when the machine knows the date), and how deep the best got.
-- A new descent is seeded with the ticks it took to press A: a person never presses on the same one twice, and a test always does.
local scene = require("scene")
local ui = require("ui")

local T = {}
local t, choice, today

function T.enter()
  bg(0) bg(1) bg(2) bg(3)
  backdrop(0x08060C)
  local c = clock()
  today = c and c.days
  t, choice = 0, 1
end

function T.update()
  t = t + 1
  if today and (btnp("up") or btnp("down")) then choice = 3 - choice end
  if btnp("a") then
    local daily = choice == 2
    scene.go(require("play"), {seed = daily and today or ticks(), daily = daily}, {fade = 0.4})
  end
end

function T.draw()
  for i = 0, 7 do -- the mouth of the chasm: rings going down into the dark
    local w = 420 - i * 52
    rect(240 - w // 2, 120 + i * 14 - (i * i), w, 6 + i, ({0x2A2030, 0x231A2A, 0x1C1524, 0x16101E, 0x110C18, 0x0C0912, 0x09070E, 0x06050A})[i + 1])
  end
  text("SIMA", 240, 40, {font = "large_bold", scale = 2, align = "center", color = ui.SEL, outline = 0x101830, shadow = 0x000000})
  text("cinco pisos, y el amuleto al fondo", 240, 92, {font = "bold", align = "center", color = ui.INK})
  text((choice == 1 and "> " or "  ") .. "Bajada nueva", 240, 196, {font = "bold", align = "center", color = choice == 1 and ui.SEL or ui.INK})
  if today then
    text((choice == 2 and "> " or "  ") .. "La sima del día", 240, 220, {font = "bold", align = "center", color = choice == 2 and ui.SEL or ui.INK})
  end
  local best, wins = stored("best"), stored("wins")
  if best then
    text("lo más hondo: piso " .. best .. (wins and ("   amuletos: " .. wins) or ""), 240, 256, {font = "main", align = "center", color = ui.SUB})
  end
  text("cruceta andar   A esperar   B poción", 240, 292, {font = "main", align = "center", color = ui.INK})
end

return T
