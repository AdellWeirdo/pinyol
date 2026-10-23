-- title: the first screen. The island at night, the name, and three things to do: a new game, go on, change the colours.
local Pal = require("core.pal")
local Sound = require("core.sound")
local Save = require("core.save")
local Music = require("core.music")
local lang = require("lang")
local UI = require("core.ui")
local T = {}

T.t = 0
T.sel = 1
T.items = {}

function T.enter()
  T.t, T.sel = 0, 1
  T.items = {}
  if Save.exists() then T.items[#T.items + 1] = "continue" end
  T.items[#T.items + 1] = "new"
  T.items[#T.items + 1] = "palette"
  T.sel = 1
  Music.play("title", 0)
  -- the night: the sky is the darkest tone; the name, the moon and the stars are tiles of the window layer
  UI.clear(0, 0, 30, 20)
  backdrop(Pal.tone(4))
  for r = 0, 1 do
    for c = 0, 13 do UI.meta(1 + c * 2, 2 + r * 2, "logo_" .. r .. "_" .. c) end
  end
  for c = 0, 3 do UI.meta(9 + c * 2, 6, "logo_isla_" .. c) end
  for r = 0, 1 do for c = 0, 1 do UI.meta(24 + c * 2, 6 + r * 2, "moon_" .. r .. "_" .. c) end end
end

-- leaving the title: the layer is for the game again
function T.leave() UI.clear(0, 0, 30, 20) end

local STARS = {{3, 0}, {5, 9}, {10, 15}, {19, 9}, {17, 0}, {2, 13}, {23, 14}, {28, 3}}

-- returns "new", "continue" when the player chose one
function T.update()
  T.t = T.t + 1
  local n = #T.items
  if btnp("up") then T.sel = (T.sel - 2) % n + 1 Sound.play("select") end
  if btnp("down") then T.sel = T.sel % n + 1 Sound.play("select") end
  local it = T.items[T.sel]
  if it == "palette" and (btnp("left") or btnp("right")) then
    Pal.set_mode(Pal.mode + (btnp("left") and -1 or 1))
    Sound.play("select")
  end
  if btnp("a") or btnp("start") then
    if it == "palette" then Pal.set_mode(Pal.mode + 1) Sound.play("select") return nil end
    Sound.play("confirm")
    return it
  end
end

function T.draw()
  local ink = Pal.tone(1)
  -- the stars twinkle in turn: three tiles, one lit more than the others
  for i, st in ipairs(STARS) do
    UI.set(st[1], st[2], "star_" .. ((T.t // 30 + i) % 3))
  end
  -- the island's edge, dark against the sky
  rect(0, 268, 480, 52, Pal.tone(3))
  rect(0, 268, 480, 2, Pal.tone(2))
  for i, it in ipairs(T.items) do
    local y = 176 + (i - 1) * 24
    local label = it == "palette" and lang.tr("menu_palette", {name = Pal.name()}) or lang.tr("title_" .. it)
    if i == T.sel and (T.t // 20) % 2 == 0 then tri(150, y + 3, 150, y + 15, 158, y + 9, ink) end
    text(label, 170, y, {font = "ps", color = ink})
  end
  text("pinyol", 240, 296, {font = "ps", color = Pal.tone(2), align = "center"})
end

return T
