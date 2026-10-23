-- glass: the case and the glass of the handheld, drawn once: the plate with its printed names and buttons, the picture printed behind the glass (a circus),
-- and every figure as a ghost (what is off still shows faintly). main.lua shows the result as one picture (assets/LCD, made by gen/make_glass.py): a
-- full-screen canvas costs ~100 ms a frame on the console, a picture ~1 ms.
local S = require("shapes")
local G = {}

local GX, GY, GW, GH = S.GX, S.GY, S.GW, S.GH
local GLASS, GHOST = 0xC4C9B0, 0xB4BAA2
local PLATE, PLATE_D, PLATE_L = 0xE2B83A, 0xB8902A, 0xF4D868

local function bezel() -- the plate of the case, with the printed names and the buttons
  rect(0, 0, 480, 320, PLATE)
  rect(0, 0, 480, 6, PLATE_L) rect(0, 314, 480, 6, PLATE_D)
  rect(GX - 8, GY - 8, GW + 16, GH + 16, 0x3A3226)          -- the recess round the glass
  rect(GX - 4, GY - 4, GW + 8, GH + 8, 0x1E1A14)
  text("MALABARISTA", 240, 6, {font = "pocket_lcd_title", align = "center", color = 0x8A1E1E})
  text("PINYOL", GX + GW, 268, {font = "pocket_lcd_small", align = "right", color = 0x6A5818})
  -- buttons: GAME A, GAME B, TIME, and the two hands
  local function button(x, y, r, label)
    circ(x, y, r + 3, PLATE_D) circ(x, y, r, 0x7A1818) circ(x - 2, y - 2, r - 4, 0xA82A2A)
    if label then text(label, x, y + r + 4, {font = "pocket_lcd_small", align = "center", color = 0x6A5818}) end
  end
  button(76, 286, 10, "GAME A") button(136, 286, 10, "GAME B") button(196, 286, 10, "TIME")
  button(350, 286, 20) button(420, 286, 20)
  text("<", 350, 278, {font = "pocket_lcd_title", align = "center", color = 0xE8D8B0})
  text(">", 420, 278, {font = "pocket_lcd_title", align = "center", color = 0xE8D8B0})
end

local function printed() -- the picture printed behind the glass: the circus
  rect(GX, GY, GW, GH, GLASS)
  for i = 0, 13 do -- the tent's stripes, from its top
    local a, b = GX + i * (GW / 14), GX + (i + 1) * (GW / 14)
    poly({240, GY + 4, a, GY + 70, b, GY + 70}, i % 2 == 0 and 0xC8604A or 0xE4D8A4)
  end
  rect(GX, GY + 70, GW, 10, 0x8C4636)
  for i = 0, 13 do circ(GX + i * (GW / 14) + 14, GY + 80, 8, i % 2 == 0 and 0xE4D8A4 or 0xC8604A) end
  rect(GX, GY + 94, 38, GH - 94, 0x7A4E50) rect(GX + GW - 38, GY + 94, 38, GH - 94, 0x7A4E50)      -- the curtains
  for i = 0, 3 do rect(GX + 6 + i * 8, GY + 94, 3, GH - 94, 0x5E3A3E) rect(GX + GW - 34 + i * 8, GY + 94, 3, GH - 94, 0x5E3A3E) end
  rect(GX, GY + GH - 22, GW, 22, 0x9A7A4A)                                                          -- the ring's floor
  for i = 0, 7 do circ(GX + 22 + i * 48, GY + GH - 14, 9, 0x8A6A3A) end
  for i = 0, 5 do -- a star banner
    local x = GX + 56 + i * 56
    poly({x, GY + 100, x + 8, GY + 116, x - 8, GY + 116}, i % 2 == 0 and 0xE8C040 or 0x7AA0B0)
  end
  rect(158, 42, 124, 44, 0xD2D6BE) -- (a pale plate behind the digits so they read)
end

function G.paint() -- the printed picture and every figure as a ghost, once
  bezel()
  printed()
  S.juggler(GHOST, true, false) S.juggler(GHOST, false, true) -- (both ghosts: the arms in each pose)
  for k = 1, 5 do for _, dir in ipairs({1, -1}) do local x, y = S.arc(k, dir) S.ball(x, y, GHOST) end end
  S.ball(S.HL[1] - 10, S.HL[2] - 4, GHOST) S.ball(S.HR[1] + 10, S.HR[2] - 4, GHOST)
  for side = 1, 2 do for k = 1, 3 do local x, y = S.drop_at(side, k) S.ball(x, y, GHOST) end end
  S.digits("8888", GHOST) S.colon(GHOST)
  for i = 1, 3 do text("X", GX + GW - 40 + (i - 1) * 0, GY + 8 + (i - 1) * 0, {font = "pocket_lcd_small", color = GLASS}) end
  for i = 1, 3 do circ(GX + GW - 84 + i * 22, GY + 22, 7, GHOST) end
end


return G
