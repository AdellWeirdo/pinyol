-- map: the island's map. Four levels along a path and, when enough pieces of the jewel are kept, the Golem's door. The token walks between them.
local C = require("core.const")
local S = require("core.spr")
local Game = require("core.game")
local Sound = require("core.sound")
local Music = require("core.music")
local lang = require("lang")
local M = {}

M.sel = 1
M.t = 0
M.token = {x = 58, y = 96}
-- the centres of the places on the map picture (gen/art_items.py MAP_NODES): selva, cristal, galeón, fragua, the golem
local NODES = {{58, 96}, {106, 40}, {212, 100}, {146, 72}, {128, 128}}

function M.enter(at)
  M.t = 0
  M.sel = at or 1
  M.token.x, M.token.y = NODES[M.sel][1], NODES[M.sel][2]
  bg(3, {map = "MAPA_FONDO", prio = 3, wrap = true})
  bg(2) bg(1) bg(0)
  fx_off() line_off() window_off(0) mosaic(1, 1, 1, 1)
  Music.play("mapa", 300)
end

local function unlocked(i)
  if i == 5 then return Game.boss_open() end
  return Game.open(i)
end
M.unlocked = unlocked

-- returns the number of the level chosen (1..4, 5 = the boss), "title" or nil
function M.update()
  M.t = M.t + 1
  local tx, ty = NODES[M.sel][1], NODES[M.sel][2]
  M.token.x = M.token.x + (tx - M.token.x) * 0.2
  M.token.y = M.token.y + (ty - M.token.y) * 0.2
  if btnp("right") and M.sel < 5 then M.sel = M.sel + 1 Sound.play("select") end
  if btnp("left") and M.sel > 1 then M.sel = M.sel - 1 Sound.play("select") end
  if btnp("a") or btnp("start") then
    if unlocked(M.sel) then Sound.play("confirm") return M.sel end
    Sound.play("deny")
  end
  if btnp("b") then return "title" end
  return nil
end

function M.draw()
  S.begin()
  local t = M.t
  scroll(3, 0, 0)
  S.draw("MAPA16", "token_" .. ((t // 6) % 6), M.token.x - 8, M.token.y - 24 + math.floor(math.sin(t / 8) * 2), {prio = 0})
  for i, n in ipairs(NODES) do
    local f
    if i == 5 then f = unlocked(5) and ("node_boss_" .. ((t // 8) % 4)) or "node_locked"
    elseif not unlocked(i) then f = "node_locked"
    elseif Game.levels[i].done then f = "node_done_" .. ((t // 8 + i) % 4)
    else f = "node_idle_" .. ((t // 8 + i) % 4) end
    S.draw("MAPA16", f, n[1] - 8, n[2] - 8, {prio = 1})
    if i < 5 and Game.levels[i].done and Game.levels[i].crown > 0 then
      S.draw("UI16", ({"crown_bronze", "crown_silver", "crown_gold"})[Game.levels[i].crown], n[1] - 8, n[2] - 24, {prio = 0})
    end
  end
  -- arrows to the neighbours
  if M.sel > 1 then S.draw("UI16", "arrow_right_" .. ((t // 8) % 3), 6, 100, {flip = true, prio = 0}) end
  if M.sel < 5 then S.draw("UI16", "arrow_right_" .. ((t // 8) % 3), 218, 100, {prio = 0}) end
end

function M.draw_text()
  local i = M.sel
  panel(16, 262, 448, 52)
  local name = lang.tr(i == 5 and "boss_name" or ("level" .. i .. "_name"))
  text(name, 240, 268, {font = "gba_body", align = "center", color = 0x8a3a08})
  if not unlocked(i) then
    local msg = i == 5 and lang.tr("map_boss_locked", {n = Game.BOSS_NEEDS, have = Game.jewel_total()}) or lang.tr("map_locked")
    text(msg, 240, 290, {font = "gba_body", align = "center", color = 0x3a1c08})
  elseif i < 5 then
    local L = Game.levels[i]
    local have = 0
    for j = 1, 4 do if L.jewels[j] then have = have + 1 end end
    text(lang.tr("map_info", {jewels = have, coins = L.best}), 240, 290, {font = "gba_body", align = "center", color = 0x3a1c08})
  else
    text(lang.tr("map_boss_open"), 240, 290, {font = "gba_body", align = "center", color = 0x3a1c08})
  end
  text(lang.tr("map_total", {n = Game.jewel_total(), m = 16, coins = Game.coins_total}), 8, 6, {font = "gba_small", color = 0xFFFFFF, outline = 0x301808})
end

return M
