-- menu: START. A window over the whole playfield, made of the same tiles as the status bar: the things he carries (A is
-- always the pala, the others go on B), the pits and the pieces of heart, a map of the island with where he is, and
-- the few things you do between games: change the colours, save, go on.
local Game = require("core.game")
local UI = require("core.ui")
local Pal = require("core.pal")
local Sound = require("core.sound")
local Save = require("core.save")
local lang = require("lang")
local E = require("core.ents")
local W = require("core.world")
local M = {}

M.open_ = false
local sel_item, sel_opt, zone = 1, 1, "items"  -- zone: "items" (the row of things) or "opts" (the list below)
local SLOTS = {"pala", "tirachinas", "linterna"}
local OPTIONS = {"palette", "save", "resume"}
local saved_msg = 0

function M.open()
  M.open_ = true
  sel_item, sel_opt, zone = 1, #OPTIONS, "opts"
  Sound.play("select")
  M.draw_tiles()
end

function M.close()
  M.open_ = false
  UI.clear(0, 2, 30, 18)
  require("core.hud").reset()
  Sound.play("select")
end

-- the tiles: the window, the item boxes, the pits
function M.draw_tiles()
  UI.window(0, 2, 30, 18)
  for i, name in ipairs(SLOTS) do
    local tx = 1 + (i - 1) * 3
    UI.meta(tx, 4, Game.has(name) and ("box_" .. name) or "box_none")
  end
  for i = 1, 3 do UI.set(1 + (i - 1) * 2, 8, i <= Game.pits and "icon_pit" or "icon_pit_empty") end
end

local function option_text(o)
  if o == "palette" then return lang.tr("menu_palette", {name = Pal.name()}) end
  return lang.tr("menu_" .. o)
end

function M.update()
  if btnp("start") or btnp("b") then M.close() return end
  if saved_msg > 0 then saved_msg = saved_msg - 1 end
  if zone == "items" then
    if btnp("left") then sel_item = (sel_item - 2) % #SLOTS + 1 Sound.play("select") end
    if btnp("right") then sel_item = sel_item % #SLOTS + 1 Sound.play("select") end
    if btnp("down") then zone = "opts" Sound.play("select") end
    if btnp("a") then
      local name = SLOTS[sel_item]
      if name ~= "pala" and Game.has(name) then Game.b = name Sound.play("confirm") end
    end
  else
    if btnp("up") then
      if sel_opt == 1 then zone = "items" else sel_opt = sel_opt - 1 end
      Sound.play("select")
    end
    if btnp("down") then sel_opt = math.min(#OPTIONS, sel_opt + 1) Sound.play("select") end
    local o = OPTIONS[sel_opt]
    if o == "palette" and (btnp("left") or btnp("right") or btnp("a")) then
      Pal.set_mode(Pal.mode + (btnp("left") and -1 or 1))
      Game.tried = Game.tried or {}
      Game.tried["m" .. Pal.mode] = true -- string keys, store() refuses sparse number keys
      local n = 0
      for _ in pairs(Game.tried) do n = n + 1 end
      if n >= #Pal.modes then achieve("colorista") end
      Sound.play("select")
    elseif btnp("a") then
      if o == "save" then Save.write() saved_msg = 90 Sound.play("confirm")
      elseif o == "resume" then M.close() end
    end
  end
end

function M.draw()
  if not M.open_ then return end
  local ink = Pal.tone(4)
  text(lang.tr("menu_items"), 16, 40, {font = "ps", color = ink})
  -- a frame round the chosen thing
  if zone == "items" then
    local tx = 1 + (sel_item - 1) * 3
    box(tx * 16 - 2, 4 * 16 - 2, 36, 36, ink)
  end
  text(lang.tr("menu_pits"), 16, 106, {font = "ps", color = ink})
  text(lang.tr("menu_pieces", {n = Game.pieces % 4}), 16, 180, {font = "ps", color = ink})
  for i, o in ipairs(OPTIONS) do
    local y = 240 + (i - 1) * 24
    local on = zone == "opts" and i == sel_opt
    if on then tri(24, y + 3, 24, y + 15, 32, y + 9, ink) end
    text(option_text(o), 44, y, {font = "ps", color = ink})
  end
  if saved_msg > 0 then text(lang.tr("menu_saved"), 300, 296, {font = "ps", color = ink}) end
end

return M
