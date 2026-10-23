-- Cajas: a one-on-one fight of boxy fighters, the way the first fighting games of the 32-bit consoles drew them. Each fighter is eleven pieces moved with a little
-- kinematics in Lua and drawn with mesh() (the limbs one flat face each); the arena is the PPU's background layer; the CPU fights back. The console's menu has
-- "Cómo funciona", which switches each trick off.
--   left, right: walk (back blocks)   up: jump   down: crouch   A: punch   B: kick   down and B: sweep
local Tex, Cam, F = require("textures"), require("cam"), require("fighter")
local View, W, Snd, Music, E = require("view"), require("world"), require("sound"), require("music"), require("explain")
local lang, hud, juice, particles = require("lang"), require("hud"), require("juice"), require("particles")

state = "title" -- title | play | over | explain (global: tests/cajas.script)
diff = 2        -- 1 easy, 2 normal, 3 hard
local back_to, faces_drawn, over_t = "title", 0, 0
local fx, banner = nil, nil
local SPARK = {0xFFFFFF, 0xFFE060, 0xFF8030}

local function menu()
  menuitem()
  menuitem(lang.tr("how"), function()
    if state ~= "explain" then back_to, state = state == "over" and "title" or state, "explain" E.enter() achieve("curioso") end
  end)
end

local function toast(s) hud.toast(s, 170) sfx("SFX_TOAST", 0.8) end
local function earn(id) if achieve(id) then toast(lang.tr("ach_" .. id)) end end
local function say(key, vars, col, t) banner = {text = lang.tr(key, vars), t = t or 60, col = col or 0xFFFFFF} end

local function spark(f, o, n, colours)
  local sx, sy = Cam.project(o.x - f.face * 1.5, o.y + 11, 0)
  if sx then fx:burst(sx, sy, n, {speed = 3.2, angle = -90, spread = 360, gravity = 0.1, life = 14, size = 2.5, colours = colours or SPARK, shape = "square"}) end
end

local function on_event(ev, a, b, c)
  if state == "title" or state == "explain" then
    if ev == "hit" or ev == "blocked" then spark(a, b, 5) end
    return
  end
  if ev == "whoosh" then Snd.play("SFX_WHOOSH")
  elseif ev == "hit" then
    local f, o, m = a, b, c
    Snd.play(m.dmg >= 8 and "SFX_HIT_BIG" or "SFX_HIT")
    spark(f, o, m.dmg >= 8 and 10 or 6)
    juice.shake(m.dmg >= 8 and 3.5 or 2) juice.freeze(m.dmg >= 8 and 4 or 3)
    if f == W.p then earn("golpe") if W.combo_p >= 3 and W.p.hits_taken == 0 then earn("combo") end end
  elseif ev == "blocked" then Snd.play("SFX_BLOCK") spark(a, b, 4, {0xFFFFFF, 0x80C0FF}) juice.shake(1)
  elseif ev == "jump" then Snd.play("SFX_JUMP", 0.7)
  elseif ev == "land" then Snd.play("SFX_LAND", 0.8)
  elseif ev == "round" then say("round", {n = a}, 0xFFE060, 50) Snd.play("SFX_BELL")
  elseif ev == "fight" then say("fight", nil, 0xFF6040, 45) Snd.play("SFX_FIGHT") Music.set("fight", math.min(3, W.round))
  elseif ev == "round_over" then
    local winner, timeout = a, b
    say(timeout and "time" or "ko", nil, 0xFF4040, 130) Snd.play("SFX_KO") Music.set(nil) juice.shake(5)
    if winner == W.p then
      earn("asalto")
      if W.p.hits_taken == 0 then earn("perfecto") banner.sub = lang.tr("perfect") end
    end
  elseif ev == "match_over" then
    state, over_t = "over", 0
    Snd.play(a == "p" and "SFX_WIN" or "SFX_KO")
  end
end

local function start_match()
  W.hook = on_event
  W.new(diff)
  fx = particles.new()
  banner = nil
end

function _init()
  show(BG3)
  lang.load()
  Tex.init(); F.init(); Snd.init()
  Cam.define({{pos = {0, 12, -34}, target = {0, 8.5, 0}, zone = {-99, 99, -99, 99}}})
  Cam.use(1)
  View.sky()
  Music.on = stored("music", true)
  start_match()
  Music.set("title")
  menu()
end

function _resume() lang.load() menu() end

local function player_input()
  return {left = btn("left"), right = btn("right"), up = btn("up"), down = btn("down"), a = btn("a"), b = btn("b"), a_p = btnp("a"), b_p = btnp("b")}
end

function _update()
  hud.update()
  fx:update()
  Music.update()
  if banner then banner.t = banner.t - 1 if banner.t <= 0 then banner = nil end end
  if juice.update() then return end
  if state == "title" or state == "explain" then
    if W.phase == "match_over" or W.round > 3 then start_match() end
    W.update(W.ai_input_p()) -- (the machines fight each other behind the title)
    if state == "title" then
      if btnp("left") then diff = (diff - 2) % 3 + 1 sfx("SFX_BLIP", 0.8) end
      if btnp("right") then diff = diff % 3 + 1 sfx("SFX_BLIP", 0.8) end
      if btnp("a") then state = "play" start_match() sfx("SFX_START", 0.9) Music.set(nil) end
    elseif E.update() then state = back_to
    end
  elseif state == "play" then
    W.update(player_input())
  elseif state == "over" then
    over_t = over_t + 1
    W.update({})
    if over_t > 60 and btnp("a") then state = "title" start_match() Music.set("title") end
  end
end

local function bar(x, w, hp, flip, col)
  rect(x - 2, 10, w + 4, 18, 0xFFFFFF) rect(x, 12, w, 14, 0x2A2030)
  local fw = math.floor(w * hp / 100)
  local c = hp > 50 and 0x58C858 or hp > 25 and 0xF0C040 or 0xE04838
  if flip then rect(x + w - fw, 12, fw, 14, c) else rect(x, 12, fw, 14, c) end
end

local function hud_draw()
  local p, c = W.p, W.c
  bar(24, 188, p.hp, false) bar(268, 188, c.hp, true)
  text(lang.tr("p1"), 26, 31, {font = "silk", color = 0xFFD8D0, outline = 0x201018})
  text(lang.tr("p2"), 454, 31, {font = "silk", align = "right", color = 0xD0E0FF, outline = 0x201018})
  for i = 1, 2 do -- rounds won
    circ(34 + (i - 1) * 14, 52, 5, i <= p.wins and 0xF0C040 or 0x40384C, true)
    circ(446 - (i - 1) * 14, 52, 5, i <= c.wins and 0xF0C040 or 0x40384C, true)
  end
  text(string.format("%02d", math.ceil(W.timer / 60)), 240, 10, {font = "arcade", align = "center", color = 0xFFFFFF, outline = 0x201018})
  if W.combo_p >= 2 then text(lang.tr("hits", {n = W.combo_p}), 24, 64, {font = "arcade", color = 0xFFE060, outline = 0x201018}) end
  if banner then
    text(banner.text, 240, 120, {font = "gothic", align = "center", color = banner.col, outline = 0x201018})
    if banner.sub then text(banner.sub, 240, 160, {font = "arcade", align = "center", color = 0xFFE060, outline = 0x201018}) end
  end
  hud.draw_toasts(110, 80, {font = "silk", w = 260})
end

function _draw()
  camera(juice.offset())
  faces_drawn = View.fighters(W, ticks())
  fx:draw()
  camera()
  if state == "play" or state == "over" then
    hud_draw()
    if state == "over" then
      shade(70, 90, 340, 110)
      local won = W.winner == "p"
      text(lang.tr(won and "you_win" or "you_lose"), 240, 110, {font = "gothic", align = "center", color = won and 0xFFE060 or 0xE05848, outline = 0x201018})
      if over_t > 60 then text(lang.tr("again"), 240, 168, {font = "arcade", align = "center", color = 0xFFFFFF}) end
    end
  elseif state == "title" then
    shade(0, 24, 480, 130)
    text(lang.tr("title"), 242, 38, {font = "gothic", align = "center", color = 0x201018})
    text(lang.tr("title"), 240, 36, {font = "gothic", align = "center", color = 0xF0C860, outline = 0x201018})
    text("< " .. lang.tr("diff" .. diff) .. " >", 240, 96, {font = "arcade", align = "center", color = 0xFFFFFF, outline = 0x201018})
    text(lang.tr("press"), 240, 124, {font = "arcade", align = "center", color = (ticks() // 30) % 2 == 0 and 0xFFFFFF or 0x9A88B8})
    shade(0, 236, 480, 84)
    for i, k in ipairs({"controls", "controls2", "controls3", "controls4"}) do
      text(lang.tr(k), 240, 240 + (i - 1) * 14, {font = "silk", align = "center", color = 0xE8DCC0})
    end
    text(lang.tr("hint"), 240, 300, {font = "silk", align = "center", color = 0xB8A888})
  elseif state == "explain" then E.panel(faces_drawn)
  end
end
