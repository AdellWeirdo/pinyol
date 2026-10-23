-- explain: "Cómo funciona", from the console's menu: the tricks of the look, each with a switch where one makes sense, over the fight that goes on behind.
local lang = require("lang")
local F = require("fighter")
local View = require("view")
local Music = require("music")
local M = {}
local ROWS = {
  {key = "snap", get = function() return F.snap end, set = function(v) F.snap = v end},
  {key = "dither", get = function() return F.dither end, set = function(v) F.dither = v View.dither = v end},
  {key = "kinematics"}, {key = "flat"},
  {key = "music", get = function() return Music.on end, set = function(v) Music.on = v store("music", v) if not v then tone(0) tone(1) tone(2) end end},
}
M.sel = 1
function M.enter() M.sel = 1 end
function M.update()
  if btnp("up", 20, 6) then M.sel = (M.sel - 2) % #ROWS + 1; sfx("SFX_BLIP", 0.6) end
  if btnp("down", 20, 6) then M.sel = M.sel % #ROWS + 1; sfx("SFX_BLIP", 0.6) end
  local row = ROWS[M.sel]
  if row.set and (btnp("a") or btnp("left") or btnp("right")) then row.set(not row.get()) sfx("SFX_BLIP", 0.9) end
  return btnp("b")
end
function M.panel(faces)
  shade(12, 8, 456, 246) shade(12, 8, 456, 246)
  box(12, 8, 456, 246, 0xF0C860)
  text(lang.tr("how_title"), 240, 16, {font = "arcade", align = "center", color = 0xF0C860})
  for i, row in ipairs(ROWS) do
    local y = 40 + (i - 1) * 40
    if i == M.sel then rect(20, y - 3, 440, 38, 0x2A2418) box(20, y - 3, 440, 38, 0xF0C860) end
    text(lang.tr(row.key), 30, y, {font = "main", color = i == M.sel and 0xFFFFFF or 0xC8B888})
    if row.get then local on = row.get() text(lang.tr(on and "on" or "off"), 450, y, {font = "main", align = "right", color = on and 0x78E070 or 0xE06858}) end
    text(lang.tr(row.key .. "_d"), 30, y + 17, 0xA89870, "silk")
  end
  text(faces .. " " .. lang.tr("faces"), 22, 234, {font = "silk", color = 0x887850})
  shade(0, 254, 480, 66)
  text(lang.tr("toggle"), 240, 262, {font = "silk", align = "center", color = 0xF0C860})
  text(lang.tr("back"), 240, 280, {font = "silk", align = "center", color = 0xF0C860})
end
return M
