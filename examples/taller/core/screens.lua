-- screens: everything that is not the stage: the title (and its attract mode), the choice of hero, the tally after each stage, the ending, and the continue countdown.
local C = require("core.const")
local S = require("core.spr")
local Run = require("core.run")
local Game = require("core.game")
local Sound = require("core.sound")
local Music = require("core.music")
local Hud = require("core.hud")
local lang = require("lang")
local X = {}

local label = Hud.label
X.HEROES = {"vera", "tomas", "mina"}

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
  local y = 14 + math.floor(math.sin(T.t / 25) * 3)
  S.draw("logo", "logo", 240, y - 6, {})
  for i, it in ipairs(T.items) do
    local on = i == T.sel
    label((on and "> " or "  ") .. lang.tr("title_" .. it), 240, 224 + (i - 1) * 28, {align = "center", scale = 1, color = on and 0xFFFFFF or 0xA09070})
  end
  label(lang.tr("title_best") .. " " .. string.format("%07d", Game.best), 240, 296, {align = "center", color = 0xFFE070})
end

-- ------------------------------------------------------------------ choosing a hero

X.select = {sel = 1, t = 0}
local SEL = X.select
local XS = {90, 240, 390}

function SEL.enter()
  SEL.sel, SEL.t = Game.last, 0
  Music.play("seleccion", 200)
end

-- returns the hero's id when chosen, "back" on B-hold (select B toggles the second colours)
function SEL.update()
  SEL.t = SEL.t + 1
  if btnp("left") then SEL.sel = (SEL.sel - 2) % 3 + 1 Sound.play("select") elseif btnp("right") then SEL.sel = SEL.sel % 3 + 1 Sound.play("select") end
  if btnp("b") then Run.alt = not Run.alt Sound.play("select") end
  if btnp("a") or btnp("start") then Game.choose(SEL.sel) Sound.play("confirm") return X.HEROES[SEL.sel] end
  if btnp("c") then return "back" end
  return nil
end

function SEL.draw()
  S.count = 0
  S.back("select", 0, 0)
  for i, id in ipairs(X.HEROES) do
    local on = i == SEL.sel
    S.draw(id, "select_0", XS[i], 196 - (on and math.floor(math.abs(math.sin(SEL.t / 8)) * 5) or 0), {dim = on and nil or 0.45, alt = Run.alt})
  end
  label(lang.tr("select_title"), 240, 12, {align = "center", scale = 2, fit = 400, gradient = 0xFF8020})
  local id = X.HEROES[SEL.sel]
  Hud.panel(20, 206, 440, 112)
  text(lang.tr("hero_" .. id .. "_name"), 240, 214, {font = "bold", align = "center", color = 0x402010})
  text(lang.tr("hero_" .. id .. "_trait"), 240, 238, {font = "main", align = "center", width = 410, color = 0x8a3a08})
  text(lang.tr("select_help"), 240, 288, {font = "main", align = "center", color = 0x402010})
end

-- ------------------------------------------------------------------ the tally

X.results = {t = 0}
local R = X.results

function R.enter()
  R.t = 0
  R.bonus = Run.parts * 500 + Run.props * 100
  Run.add(R.bonus)
  Game.save_best(Run.score)
end

function R.update()
  R.t = R.t + 1
  return R.t > 150 and (btnp("a") or btnp("start"))
end

function R.draw(hero)
  S.count = 0
  S.back("select", 0, 0)
  S.draw(Run.hero, "win_" .. (R.t // 10) % 3, 110, 262, {alt = Run.alt})
  Hud.panel(196, 24, 270, 240)
  text(lang.tr("res_title", {n = Run.stage}), 330, 42, {font = "bold", align = "center", color = 0x8a3a08})
  local y = 84
  local function row(k, v) text(lang.tr(k), 214, y, {font = "main", color = 0x402010}) text(v, 446, y, {font = "main", align = "right", color = 0x402010}) y = y + 26 end
  row("res_kills", tostring(Run.kills))
  row("res_parts", tostring(Run.parts))
  row("res_props", tostring(Run.props))
  row("res_bonus", "+" .. R.bonus)
  text(lang.tr("res_score") .. " " .. string.format("%07d", Run.score), 330, y + 12, {font = "bold", align = "center", color = 0x8a3a08})
  if R.t > 150 then text(lang.tr("res_press"), 330, 232, {font = "main", align = "center", color = (R.t // 20) % 2 == 0 and 0x402010 or 0x907050}) end
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
  S.draw(Run.hero, "win_" .. (E.t // 10) % 3, 240, 310, {alt = Run.alt})
  shade(0, 0, 480, 200)
  label(lang.tr("end_title"), 240, 18, {align = "center", scale = 2, fit = 460, gradient = 0xFF8020})
  text(lang.tr("end_text"), 240, 62, {font = "main", align = "center", width = 420, color = 0xFFFFFF, outline = 0x200010})
  label(string.format("%07d", Run.score), 240, 150, {align = "center", scale = 2})
  if E.t > 600 then label(lang.tr("res_press"), 240, 210, {align = "center", color = (E.t // 20) % 2 == 0 and 0xFFFFFF or 0x908070}) end
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
