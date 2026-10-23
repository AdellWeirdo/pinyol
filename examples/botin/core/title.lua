-- title: the logo wavers line by line over a sky that drifts, Zurrón celebrates on the ground, jewels turn round the logo. After a while without a button it plays
-- the game by itself (the attract mode).
local C = require("core.const")
local S = require("core.spr")
local Game = require("core.game")
local Sound = require("core.sound")
local Music = require("core.music")
local lang = require("lang")
local T = {}

T.sel = 1
T.t = 0
T.idle = 0
T.items = {}
local ATTRACT = 60 * 14

function T.enter()
  T.t, T.idle, T.sel = 0, 0, 1
  bg(3, {map = "TITULO_FONDO", prio = 3, wrap = true})
  bg(2, {map = "TITULO_LOGO", prio = 2, wrap = false})
  bg(1) bg(0)
  fx_off() line_off() window_off(0)
  T.items = {}
  if Game.exists() then T.items[#T.items + 1] = "continue" end
  T.items[#T.items + 1] = "new"
  T.items[#T.items + 1] = "how"
  Music.play("titulo", 200)
end

-- returns "new", "continue", "how" or "demo" when something is picked
function T.update()
  T.t = T.t + 1
  T.idle = T.idle + 1
  if btnp("up") then T.sel = (T.sel - 2) % #T.items + 1 T.idle = 0 Sound.play("select") end
  if btnp("down") then T.sel = T.sel % #T.items + 1 T.idle = 0 Sound.play("select") end
  if btnp("a") or btnp("start") then
    Sound.play("confirm")
    return T.items[T.sel]
  end
  if btnp("b") or btnp("left") or btnp("right") then T.idle = 0 end
  if T.idle > ATTRACT then return "demo" end
  return nil
end

function T.draw()
  S.begin()
  local t = T.t
  scroll(3, math.floor(t * 0.25), 0)
  scroll(2, -40, -14)
  for y = 0, C.H - 1 do
    local k = y - 14
    if k >= 0 and k < 48 then line_scroll(2, y, -40 + math.floor(math.sin((y + t * 0.9) / 4) * 2 + 0.5), -14) else line_scroll(2, y, -40, -14) end
  end
  -- jewels turning round the logo
  for i = 1, 4 do
    local a = t / 50 + i * 1.5708
    S.draw("ITEMS16", "jewel_" .. i .. "_" .. ((t // 7) % 4), 112 + math.cos(a) * 88 - 8, 38 + math.sin(a) * 14 - 8, {})
  end
  S.draw("HERO", "win_" .. ((t // 6) % 6), 104, 112, {})
end

function T.draw_text()
  local t = T.t
  text(lang.tr("title_sub"), 240, 156, {font = "gba_small", align = "center", color = 0xFFE9A8, outline = 0x402010})
  for i, it in ipairs(T.items) do
    local y = 214 + (i - 1) * 24
    local on = i == T.sel
    text(lang.tr("title_" .. it), 240, y, {font = "gba_body", align = "center", color = on and 0xFFFFFF or 0xC8C0A8, outline = 0x301808, shadow = 0x000000})
    if on then
      text(">", 150, y, {font = "gba_body", color = 0xFFD040, outline = 0x301808})
      text("<", 316, y, {font = "gba_body", color = 0xFFD040, outline = 0x301808})
    end
  end
end

return T
