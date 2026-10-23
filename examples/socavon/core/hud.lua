-- hud: the status under the room: the room's name on a yellow band, the air, the score and the lives, and the border.
local R = require("core.room")
local Z = require("core.zx")
local lang = require("lang")
local H = {}

local F = {title = "zx_spectrum_title", body = "zx_spectrum_body", small = "zx_spectrum_small"}
H.F = F
local OX, OY = 16, 16 -- the room's corner on the screen (the border is 8 world pixels all round)
H.OX, H.OY = OX, OY

function H.border(colour)
  rect(0, 0, 480, 16, colour)
  rect(0, 304, 480, 16, colour)
  rect(0, 0, 16, 320, colour)
  rect(464, 0, 16, 320, colour)
end

function H.status(g)
  local y = OY + R.H * 16
  rect(OX, y, 448, 32, Z.BLACK)
  rect(OX, y, 448, 16, Z.BYELLOW)
  text(lang.tr("room_" .. g.room), 240, y + 1, {font = F.title, align = "center", color = Z.BLACK})
  text(lang.tr("air"), OX + 4, y + 20, {font = F.small, color = Z.BWHITE})
  local a = math.max(0, g.air)
  rect(OX + 52, y + 21, math.floor(200 * a), 8, a > 0.25 and Z.BGREEN or Z.BRED)
  text(string.format("%06d  x%d", g.score, g.lives), OX + 444, y + 20, {font = F.small, align = "right", color = Z.BYELLOW})
end

return H
