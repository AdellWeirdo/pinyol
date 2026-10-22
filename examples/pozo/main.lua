-- Pozo: a game the way the vector arcade machines drew it. Nothing is a picture, nothing is filled: every frame the
-- game hands the monitor a list of lines, and vec.lua draws them with their glow. The console's menu has "Cómo
-- funciona", which replays the frame on the screen line by line, as the beam drew it (explain.lua).
--   left and right: move the claw round the rim   A: fire   B: the zapper   START: begin
local V, W = require("vec"), require("well")
local P, E, Snd = require("play"), require("explain"), require("sound")
local lang = require("lang")

state = "title" -- title | play | over | explain (global: tests/pozo.script)
G = P           -- the game's own state, for the test script
P.vec = V

local T, high, new_record = 0, 0, false
local toast_text, toast_t = nil, 0
local BODY = {font = "hud", color = 0xFFE040}
local SMALL = {font = "hud_s", color = 0x7088C0}
local YELLOW = 0xFFE040

local function toast(s) toast_text, toast_t = s, 170 end

local function hook(id) -- an achievement earned, or an extra life
  if state == "demo" then return end
  if id == "extra" then
    toast(lang.tr("extra"))
    Snd.play("SFX_TOAST")
    return
  end
  if achieve(id) then
    toast(lang.tr("ach_" .. id))
    Snd.play("SFX_TOAST")
  end
end

local function menu() -- the game's own item in the console's menu, in the language of the settings
  menuitem()
  menuitem(lang.tr("how"), function()
    if state ~= "explain" and state ~= "demo" then E.enter(state) state = "explain" end
  end)
end

function _init()
  show(0) -- no world of tiles and sprites: only lines, at the screen's resolution
  lang.load()
  Snd.init()
  high = stored("high", 0)
  V.flicker = not settings().reduce_flashing
  P.hook, E.hook = hook, hook
  W.set(1)
  menu()
end

function _resume() -- the menu closed: Ajustes may have changed the language or the flashing
  V.flicker = not settings().reduce_flashing
  lang.load()
  menu()
end

local function start()
  P.ai = false
  P.new_game()
  state, new_record = "play", false
  Snd.play("SFX_START")
end

local DEMO_AFTER, DEMO_LENGTH = 420, 2400 -- ticks of title before the machine plays itself, and for how long
local demos = 0

local function any_button()
  for _, b in ipairs({"a", "b", "c", "start", "left", "right", "up", "down"}) do if btnp(b) then return true end end
  return false
end

local function start_demo()
  demos = demos + 1
  P.new_game()
  P.ai = true
  P.begin_level(1 + (demos * 2) % 8)
  state, T = "demo", 0
end

function _update()
  T = T + 1
  if toast_t > 0 then toast_t = toast_t - 1 end
  if state == "title" then
    if btnp("a") or btnp("start") then start() elseif T > DEMO_AFTER then start_demo() end
  elseif state == "demo" then
    P.update()
    if any_button() or T > DEMO_LENGTH or P.mode == "over" then P.ai, state, T = false, "title", 0 end
  elseif state == "play" then
    P.update()
    if P.mode == "over" then
      state, T = "over", 0
      if P.score > high then high, new_record = P.score, true store("high", high) end
    end
  elseif state == "over" then
    P.update()
    if T > 70 and (btnp("a") or btnp("start")) then state, T = "title", 0 end
  elseif state == "explain" then
    if E.update() then state = E.back end
  end
end

-- ------------------------------------------------------------------ drawing

local function lives_icons()
  for i = 1, math.max(0, P.lives) do
    local x = 456 - (i - 1) * 20
    V.open({x - 7, 12, x - 3, 24, x + 3, 24, x + 7, 12}, YELLOW, 2)
  end
end

local function zap_lamps()
  for i = 1, 2 - P.zaps do
    local x = 446 + (i - 1) * 16
    V.open({x, 296, x + 6, 296, x + 3, 306, x + 9, 306}, 0x80D0FF, 2)
  end
end

local function hud_strokes() -- the lives and the zapper's lamps are lines too: before vec.flush
  lives_icons()
  zap_lamps()
end

local function hud() -- the score, the level and the toast are letters
  text(string.format("%06d", P.score), 14, 8, BODY)
  text(lang.tr("high") .. " " .. string.format("%06d", high), 240, 8, {font = "hud_s", color = 0x7088C0, align = "center"})
  text(lang.tr("level", {n = P.level}), 14, 298, SMALL)
  if toast_t > 0 and toast_text then
    local w = textw(toast_text, "hud") + 24
    rect(240 - w // 2, 26, w, 20, 0x0A0A18)
    box(240 - w // 2, 26, w, 20, 0xFFE040)
    text(toast_text, 240, 29, {font = "hud", color = 0xFFFFFF, align = "center"})
  end
end

local function draw_title()
  local k = (T // 420) % 8 + 1
  if W.level_shown ~= k then W.set(k) W.level_shown = k end
  W.zoom = 0.62
  if W.closed then W.turn(T * 0.006) else W.turn(0) end
  W.draw(nil, 0.9)
  P.claw(1 + (T * 0.045) % W.n, 0, 0.7, W.pal[3])
  W.zoom = 1
  V.text(lang.tr("title"), 240, 18, 8, YELLOW)
end

function _draw()
  cls(0x000000)
  if state == "explain" then
    E.draw()
    return
  end
  V.begin()
  if state == "title" then
    draw_title()
    V.flush()
    text(lang.tr("high") .. " " .. string.format("%06d", high), 240, 252, {font = "hud", color = 0x7088C0, align = "center"})
    if (T // 30) % 2 == 0 then text(lang.tr("press"), 240, 270, {font = "vector_arcade_title", color = 0xFFFFFF, align = "center"}) end
    text(lang.tr("controls"), 240, 291, {font = "hud_s", color = 0x6078B0, align = "center"})
    text(lang.tr("hint"), 240, 303, {font = "hud_s", color = 0x7088C0, align = "center"})
    return
  end
  P.draw()
  hud_strokes()
  -- a flash is one short burst of white, never a strobe (a flash 3 times a second is the most a player can be given)
  if P.flash >= 10 and V.flicker then V.wash = 0xFFFFFF else V.wash = nil end
  if state == "over" then
    V.text(lang.tr("game_over"), 240, 120, 4, 0xFF4060)
  end
  V.flush()
  V.wash = nil
  hud()
  if state == "demo" and (T // 30) % 2 == 0 then text(lang.tr("demo") .. " · " .. lang.tr("press"), 240, 30, {font = "hud", color = 0xFFFFFF, align = "center"}) end
  if state == "over" then
    text(string.format("%06d", P.score), 240, 168, {font = "vector_arcade_title", color = 0xFFFFFF, align = "center"})
    if new_record then text(lang.tr("new_record"), 240, 200, {font = "hud", color = 0xFFE040, align = "center"}) end
  end
end
