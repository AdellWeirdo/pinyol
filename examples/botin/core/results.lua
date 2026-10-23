-- results: after a level. The coins count up, the pieces of the jewel are shown, then the crown the score earned drops in.
local S = require("core.spr")
local Run = require("core.run")
local Game = require("core.game")
local Sound = require("core.sound")
local lang = require("lang")
local R = {}

R.t = 0
R.crown = 0
R.shown = 0
R.record = false

function R.enter(level, crown)
  R.t, R.crown, R.shown = 0, crown, 0
  R.level = level
  R.record = Run.coins > Game.levels[level].best
  bg(3, {map = "MAPA_FONDO", prio = 3, wrap = true})
  bg(2) bg(1) bg(0)
  fx_off() line_off() window_off(0)
end

function R.update()
  R.t = R.t + 1
  if R.shown < Run.coins and R.t > 20 then
    R.shown = math.min(Run.coins, R.shown + math.max(1, math.ceil((Run.coins - R.shown) / 12)))
    if R.t % 2 == 0 then Sound.play("coin", 0.4) end
  end
  if R.t == 120 and R.crown > 0 then Sound.play("jewel") end
  if R.t > 90 and (btnp("a") or btnp("start")) then return true end
  return false
end

function R.draw()
  S.begin()
  local t = R.t
  for i = 1, 4 do
    local x = 84 + (i - 1) * 20
    if t > 30 + i * 12 then
      local f = Run.jewels[i] and ("jewel_" .. i .. "_" .. ((t // 7) % 4)) or ("jewel_ghost_" .. i)
      S.draw("ITEMS16", f, x, 88, {prio = 0})
    end
  end
  if t > 120 and R.crown > 0 then
    local y = math.min(116, -20 + (t - 120) * 6)
    S.draw("UI16", ({"crown_bronze", "crown_silver", "crown_gold"})[R.crown], 112, y, {prio = 0})
  end
  S.draw("HERO", "win_" .. ((t // 6) % 6), 104, 126, {})
end

function R.draw_text()
  panel(60, 12, 360, 136)
  text(lang.tr("res_title"), 240, 26, {font = "gba_title", align = "center", color = 0x8a3a08})
  text(lang.tr("res_coins", {n = R.shown}), 240, 78, {font = "gba_body", align = "center", color = 0x3a1c08})
  if R.record and R.t > 60 then text(lang.tr("res_record"), 240, 112, {font = "gba_small", align = "center", color = 0x207020}) end
  if R.t > 150 then text(lang.tr("res_press"), 240, 292, {font = "gba_small", align = "center", color = (R.t // 20) % 2 == 0 and 0xFFFFFF or 0xA0A0A0}) end
end

return R
