-- hud: the status bar, two rows of tiles at the top of the ui layer: hearts, cherries, pinyoles, the items on A and B.
-- It writes a tile only when what it shows has changed, so it costs nothing on the frames when nothing does.
local Game = require("core.game")
local UI = require("core.ui")
local Hud = {}

local shown = {}

local COL_HEARTS, COL_CHERRY, COL_PINYOL, COL_A, COL_B, COL_R = 1, 1, 6, 10, 13, 17
local W = require("core.world")

local function number(tx, ty, n, digits)
  local s = string.format("%0" .. digits .. "d", n)
  for i = 1, digits do UI.set(tx + i - 1, ty, "digit_" .. s:sub(i, i)) end
end

function Hud.reset() shown = {} end

function Hud.init()
  UI.fill(0, 0, 30, 1, "hud_bg")
  UI.fill(0, 1, 30, 1, "hud_bg_low")
  UI.set(COL_CHERRY, 1, "icon_cherry")
  UI.set(COL_PINYOL, 1, "icon_pinyol")
  Hud.reset()
  Hud.update()
end

function Hud.update()
  local hp, max = Game.hp, Game.maxhp
  if shown.hp ~= hp or shown.maxhp ~= max then
    for i = 1, 8 do
      local name = "hud_bg"
      if i * 2 <= max then
        name = hp >= i * 2 and "heart_full" or (hp == i * 2 - 1 and "heart_half" or "heart_empty")
      end
      UI.set(COL_HEARTS + i - 1, 0, name)
    end
    shown.hp, shown.maxhp = hp, max
  end
  if shown.cherries ~= Game.cherries then
    number(COL_CHERRY + 1, 1, Game.cherries, 3)
    shown.cherries = Game.cherries
  end
  if shown.pinyoles ~= Game.pinyoles then
    number(COL_PINYOL + 1, 1, Game.pinyoles, 2)
    shown.pinyoles = Game.pinyoles
  end
  if shown.b ~= (Game.b or false) then
    UI.meta(COL_B, 0, Game.b and ("item_" .. Game.b) or "box_empty")
    shown.b = Game.b or false
  end
  if not shown.a then
    UI.meta(COL_A, 0, "item_pala")
    shown.a = true
  end
  -- the right side: the golden pits on the island; the keys, the boss key and the map in the cave
  local dungeon = W.area and W.area.notes and W.area.notes.dungeon
  local keys = dungeon and (Game.keys[dungeon] or 0) or 0
  local boss = dungeon and Game.bosskeys[dungeon] and true or false
  local maps = dungeon and (Game.maps[dungeon] or 0) or 0
  local sig = (dungeon or "-") .. ":" .. keys .. ":" .. tostring(boss) .. ":" .. maps .. ":" .. Game.pits
  if shown.right ~= sig then
    shown.right = sig
    UI.fill(COL_R, 0, 13, 1, nil)
    UI.fill(COL_R, 0, 13, 1, "hud_bg")
    UI.fill(COL_R, 1, 13, 1, "hud_bg_low")
    if dungeon then
      UI.set(COL_R, 0, "icon_key")
      UI.set(COL_R + 1, 0, "x")
      UI.set(COL_R + 2, 0, "digit_top_" .. math.min(9, keys))
      if boss then UI.set(COL_R + 4, 0, "icon_bosskey") end
      if maps & 1 ~= 0 then UI.set(COL_R + 6, 0, "icon_map") end
      if maps & 2 ~= 0 then UI.set(COL_R + 7, 0, "icon_compass") end
    else
      for i = 1, 3 do UI.set(COL_R + (i - 1), 0, i <= Game.pits and "icon_pit" or "icon_pit_empty") end
    end
  end
end

return Hud
