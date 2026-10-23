-- screens: everything that is not the mission: the title (and its attract mode), the choice of chef, the tally after the mission, the ending, and the continue countdown.
local C = require("core.const")
local S = require("core.spr")
local Run = require("core.run")
local Game = require("core.game")
local Sound = require("core.sound")
local Music = require("core.music")
local W = require("core.weapons")
local Hud = require("core.hud")
local lang = require("lang")
local X = {}

local label = Hud.label
X.CHEFS = {"estrella", "espuma", "pinche", "arrocero", "brioche", "crianza"}

-- ------------------------------------------------------------------ title

X.title = {t = 0, sel = 1, idle = 0}
local T = X.title
T.items = {"start", "how"}
local ATTRACT = 60 * 14

function T.enter()
  T.t, T.idle, T.sel = 0, 0, 1
  Music.play("titulo", 200)
end

-- returns "start", "how" or "demo"
function T.update()
  T.t, T.idle = T.t + 1, T.idle + 1
  if btnp("up") or btnp("down") then T.sel = 3 - T.sel T.idle = 0 Sound.play("select") end
  if btnp("a") or btnp("start") then Sound.play("confirm") return T.items[T.sel] end
  if btnp("b") or btnp("left") or btnp("right") then T.idle = 0 end
  if T.idle > ATTRACT then return "demo" end
  return nil
end

function T.draw()
  S.count = 0
  S.back("title", 0, 0)
  local y = 22 + math.floor(math.sin(T.t / 25) * 3)
  label("PAELLA", 240, y, {align = "center", scale = 4, gradient = 0xFF5020, color = 0xFFF0A0})
  label(lang.tr("title_de"), 240, y + 66, {align = "center", scale = 2, fit = 440, gradient = 0xFFB020, color = 0xFFFFFF})
  for i, it in ipairs(T.items) do
    local on = i == T.sel
    label((on and "> " or "  ") .. lang.tr("title_" .. it), 240, 214 + (i - 1) * 28, {align = "center", scale = 1, color = on and 0xFFFFFF or 0xA09070})
  end
  label(lang.tr("title_best") .. " " .. string.format("%07d", Game.best), 240, 292, {align = "center", color = 0xFFE070})
end

-- ------------------------------------------------------------------ choosing a chef

X.select = {sel = 1, t = 0}
local SEL = X.select

function SEL.enter()
  SEL.sel, SEL.t = Game.last, 0
  Music.play("seleccion", 200)
end

-- returns the chef's id when chosen, "back" on B
function SEL.update()
  SEL.t = SEL.t + 1
  if btnp("left") then SEL.sel = (SEL.sel - 2) % 6 + 1 Sound.play("select") elseif btnp("right") then SEL.sel = SEL.sel % 6 + 1 Sound.play("select") end
  if btnp("a") or btnp("start") then Game.choose(SEL.sel) Sound.play("confirm") return X.CHEFS[SEL.sel] end
  if btnp("b") then return "back" end
  return nil
end

function SEL.draw()
  S.count = 0
  S.back("select", 0, 0)
  local al = S.backs.select.alcoves or {}
  local feet = S.backs.select.counter_y or 216
  for i, id in ipairs(X.CHEFS) do
    local a = al[i] or {40 + (i - 1) * 70, 134, 50, 82}
    local on = i == SEL.sel
    S.draw("chef_" .. id .. "_full", "select_" .. ((SEL.t // 8 + i) % 4), a[1] + a[3] // 2, feet + 2 - (on and math.floor(math.abs(math.sin(SEL.t / 8)) * 5) or 0), {dim = on and nil or 0.5})
  end
  label(lang.tr("select_title"), 240, 22, {align = "center", scale = 2, fit = 300, gradient = 0xFF8020})
  local id = X.CHEFS[SEL.sel]
  panel(60, 238, 360, 70)
  text(lang.tr("chef_" .. id .. "_name"), 240, 246, {font = "bold", align = "center", color = 0x402010})
  text(W.NAMES[id][lang.code] or W.NAMES[id].es, 240, 268, {font = "main", align = "center", color = 0x402010})
  text(lang.tr("chef_" .. id .. "_trait"), 240, 286, {font = "main", align = "center", color = 0x8a3a08})
end

-- ------------------------------------------------------------------ the tally

X.results = {t = 0}
local R = X.results

function R.enter()
  R.t = 0
  local bonus = Run.pows * 5000
  R.bonus = bonus
  Run.add(bonus)
  Game.save_best(Run.score)
end

function R.update()
  R.t = R.t + 1
  return R.t > 180 and (btnp("a") or btnp("start"))
end

function R.draw(chef)
  S.count = 0
  S.back("title", 0, 0)
  S.draw("chef_" .. Run.chef .. "_full", "win_" .. (R.t // 6) % 6, 110, 300, {})
  panel(190, 40, 270, 210)
  text(lang.tr("res_title"), 325, 52, {font = "bold", align = "center", color = 0x8a3a08})
  local y = 92
  local function row(k, v) text(lang.tr(k), 206, y, {font = "main", color = 0x402010}) text(v, 446, y, {font = "main", align = "right", color = 0x402010}) y = y + 26 end
  row("res_pows", Run.pows .. " / " .. Run.pows_total)
  row("res_bonus", "+" .. R.bonus)
  row("res_foods", Run.food_n .. " / 12")
  row("res_kills", tostring(Run.kills))
  text(lang.tr("res_score") .. " " .. string.format("%07d", Run.score), 325, y + 10, {font = "bold", align = "center", color = 0x8a3a08})
  if R.t > 180 then text(lang.tr("res_press"), 325, 224, {font = "main", align = "center", color = (R.t // 20) % 2 == 0 and 0x402010 or 0x907050}) end
end

-- ------------------------------------------------------------------ the ending

X.ending = {t = 0}
local E = X.ending

function E.enter() E.t = 0 Music.play("fin", 300) end

function E.update()
  E.t = E.t + 1
  return E.t > 600 and (btnp("a") or btnp("start"))
end

function E.draw()
  S.count = 0
  S.back("title", 0, 0)
  S.draw("chef_" .. Run.chef .. "_full", "win_" .. (E.t // 6) % 6, 240, 300, {})
  shade(0, 0, 480, 150)
  label(lang.tr("end_title"), 240, 24, {align = "center", scale = 2, fit = 460, gradient = 0xFF8020})
  text(lang.tr("end_text"), 240, 90, {font = "main", align = "center", width = 420, color = 0xFFFFFF, outline = 0x200010})
  label(string.format("%07d", Run.score), 240, 140, {align = "center", scale = 2})
  if E.t > 600 then label(lang.tr("res_press"), 240, 200, {align = "center", color = (E.t // 20) % 2 == 0 and 0xFFFFFF or 0x908070}) end
end

-- ------------------------------------------------------------------ continue?

X.cont = {t = 0, left = C.CONTINUE_SECS}
local K = X.cont

function K.enter() K.t, K.left = 0, C.CONTINUE_SECS Music.play("continue", 100) end

-- "yes", "no" or nil
function K.update()
  K.t = K.t + 1
  K.left = C.CONTINUE_SECS - K.t // 60
  if btnp("a") or btnp("start") then Sound.play("confirm") return "yes" end
  if K.left < 0 then return "no" end
  return nil
end

function K.draw()
  shade(0, 0, 480, 320)
  label(lang.tr("cont_title"), 240, 80, {align = "center", scale = 2, fit = 440, gradient = 0xFF5020})
  label(tostring(math.max(0, K.left)), 240, 130, {align = "center", scale = 6, gradient = 0xFFB020, color = 0xFFFFFF})
  label(lang.tr("cont_press"), 240, 250, {align = "center", color = (K.t // 20) % 2 == 0 and 0xFFFFFF or 0x908070})
end

return X
