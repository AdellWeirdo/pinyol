-- explain: "Cómo funciona", from the console's menu. The game keeps running behind (the fox plays itself) and a panel lists the tricks of
-- the look with a switch for each: turn one off and the scene changes under the panel, which is the explanation.
local View = require("view")
local lang = require("lang")
local M = {}

local ROWS = {
  {key = "snap", get = function() return View.snap end, set = function(v) View.snap = v end},
  {key = "dither", get = function() return View.dither end, set = function(v) View.dither = v end},
  {key = "fog", get = function() return View.fog end, set = function(v) View.fog = v end},
  {key = "affine"}, -- (no switch: texture mapping without perspective is how the quads are drawn; the far slabs show it)
}
M.sel = 1

function M.enter() M.sel = 1 end

-- returns true when the player is done
function M.update()
  if btnp("up", 20, 6) then M.sel = (M.sel - 2) % #ROWS + 1; sfx("SFX_BLIP", 0.6) end
  if btnp("down", 20, 6) then M.sel = M.sel % #ROWS + 1; sfx("SFX_BLIP", 0.6) end
  local row = ROWS[M.sel]
  if row.set and (btnp("a") or btnp("left") or btnp("right")) then
    row.set(not row.get())
    sfx("SFX_BLIP", 0.9)
  end
  return btnp("b")
end

function M.panel(faces)
  shade(12, 8, 456, 232)
  shade(12, 8, 456, 232)
  box(12, 8, 456, 232, 0xF0A858)
  text(lang.tr("how_title"), 240, 16, {font = "arcade", align = "center", color = 0xF0A858})
  for i, row in ipairs(ROWS) do
    local y = 42 + (i - 1) * 46
    local on = row.get and row.get()
    if i == M.sel then rect(20, y - 3, 440, 43, 0x3A2214) box(20, y - 3, 440, 43, 0xF0A858) end
    text(lang.tr(row.key), 30, y, {font = "main", color = i == M.sel and 0xFFE8B8 or 0xC8B898})
    if row.get then
      text(lang.tr(on and "on" or "off"), 450, y, {font = "main", align = "right", color = on and 0x78E070 or 0xE06858})
    end
    text(lang.tr(row.key .. "_d"), 30, y + 19, 0xB0A080, "silk")
  end
  text(lang.tr("faces") .. ": " .. faces, 22, 220, {font = "silk", color = 0x998A6C})
  text(lang.tr("toggle"), 240, 244, {font = "silk", align = "center", color = 0xE4D4B4})
  text(lang.tr("back"), 240, 262, {font = "silk", align = "center", color = 0xE4D4B4})
end

return M
