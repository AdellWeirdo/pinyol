-- explain: "Cómo funciona", from the console's menu: the tricks of the look, each with a switch, over the stage that keeps going behind.
local lang = require("lang")
local Stage = require("stage")
local Puppet = require("puppet")
local Music = require("music")
local M = {}

M.flags = {bend = true, shadow = true, layers = true}
local ROWS = {
  {key = "bend", get = function() return M.flags.bend end, set = function(v) M.flags.bend = v Puppet.flex = v end},
  {key = "shadow", get = function() return M.flags.shadow end, set = function(v) M.flags.shadow = v end},
  {key = "layers", get = function() return M.flags.layers end, set = function(v) M.flags.layers = v end},
  {key = "music", get = function() return Music.on end, set = function(v) Music.on = v store("music", v) if not v then tone(0) tone(1) tone(2) tone(3) end end},
}
M.sel = 1

function M.enter() M.sel = 1 end

function M.update()
  if btnp("up", 20, 6) then M.sel = (M.sel - 2) % #ROWS + 1; sfx("SFX_BLIP", 0.6) end
  if btnp("down", 20, 6) then M.sel = M.sel % #ROWS + 1; sfx("SFX_BLIP", 0.6) end
  local row = ROWS[M.sel]
  if btnp("a") or btnp("left") or btnp("right") then row.set(not row.get()) sfx("SFX_BLIP", 0.9) end
  return btnp("b")
end

function M.panel(quads)
  shade(12, 8, 456, 206)
  shade(12, 8, 456, 206)
  box(12, 8, 456, 206, 0xFFE8B0)
  text(lang.tr("how_title"), 240, 16, {font = "arcade", align = "center", color = 0xFFE8B0})
  for i, row in ipairs(ROWS) do
    local y = 42 + (i - 1) * 40
    local on = row.get()
    if i == M.sel then rect(20, y - 3, 440, 38, 0x3A2A1A) box(20, y - 3, 440, 38, 0xFFE8B0) end
    text(lang.tr(row.key), 30, y, {font = "main", color = i == M.sel and 0xFFFFFF or 0xD8C8A8})
    text(lang.tr(on and "on" or "off"), 450, y, {font = "main", align = "right", color = on and 0x78E070 or 0xE06858})
    text(lang.tr(row.key .. "_d"), 30, y + 17, 0xB8A888, "silk")
  end
  text(quads .. " " .. lang.tr("quads"), 22, 200, {font = "silk", color = 0xA09070})
  shade(0, 254, 480, 66)
  text(lang.tr("toggle"), 240, 262, {font = "silk", align = "center", color = 0xFFE8B0})
  text(lang.tr("back"), 240, 280, {font = "silk", align = "center", color = 0xFFE8B0})
end

return M
