-- Niebla: a street at night, a torch, and something that follows. The way a fixed-camera horror game of the 32-bit consoles worked: the camera does
-- not turn, it cuts when the player crosses into another stretch; controls are those of a tank; the dark and the fog hide what is far (and so
-- what the machine could not draw). Everything is a mesh(). The console's menu has "Cómo funciona", which switches each trick off.
--   left and right: turn   up and down: walk and back away   B: run   A: act (take, open)   START: begin
local Tex, View, Cam, Level = require("textures"), require("view"), require("cam"), require("level")
local People, W, Snd, E, Music = require("people"), require("world"), require("sound"), require("explain"), require("music")
local lang, hud = require("lang"), require("hud")

state = "title" -- title | play | won | explain (global: tests/niebla.script)
local back_to, faces_drawn = "title", 0
local over_t, wind, static_h, beat_t = 0, nil, nil, 0
local said = {}

local function menu() -- the game's own item in the console's menu, in the language of the settings
  menuitem()
  menuitem(lang.tr("how"), function()
    if state ~= "explain" then back_to, state = state, "explain" E.enter() achieve("curioso") end
  end)
end

local function toast(s) hud.toast(s, 170) sfx("SFX_TOAST", 0.8) end
local function earn(id) if achieve(id) then toast(lang.tr("ach_" .. id)) end end
local function say_once(key) if not said[key] then said[key] = true W.say(key) end end

local function on_event(ev)
  if state ~= "play" then return end
  if ev == "figure" then Snd.play("SFX_FIGURE", 0.8) say_once("figure")
  elseif ev == "lit" then Snd.play("SFX_LIT", 0.9) say_once("light")
  elseif ev == "repelled" then earn("luz") Snd.play("SFX_FIGURE", 0.5, {pitch = 0.6})
  elseif ev == "caught" then Snd.play("SFX_CAUGHT") over_t = 0
  elseif ev == "key" then Snd.play("SFX_KEY") earn("llave")
  elseif ev == "locked" then Snd.play("SFX_LOCKED")
  elseif ev == "door" then Snd.play("SFX_DOOR") earn("faro") state, over_t = "won", 0
  elseif ev == "ran" then earn("correr")
  elseif ev == "winded" then say_once("breath")
  end
end

local function new_game()
  W.hook = on_event
  W.new(ticks() + 1)
  said = {}
  Cam.use(Cam.pick(W.p.x, W.p.z))
end

function _init()
  show(0)
  lang.load()
  Tex.init(); View.init(); People.init(); Snd.init()
  Cam.define(Level.cameras)
  Music.on = stored("sound", true)
  W.new(1)
  Cam.use(1)
  Music.set("title")
  menu()
end

function _resume() lang.load() menu() end

local function sound_bed(on)
  if on and not wind then wind = sfx("SFX_WIND", 0.22, {loop = true}) static_h = sfx("SFX_STATIC", 0, {loop = true}) end
  if not on then
    if wind then sfx_stop(wind) wind = nil end
    if static_h then sfx_stop(static_h) static_h = nil end
  end
end

function _update()
  hud.update()
  Music.update()
  if state == "title" or state == "explain" then
    W.idle()
    if state == "title" and btnp("a") then
      state = "play"
      sfx("SFX_START", 0.9)
      new_game()
      W.say("start")
      Music.set("play")
      sound_bed(Music.on)
    elseif state == "explain" and E.update() then state = back_to
    end
  elseif state == "play" then
    local p = W.p
    local turn = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
    local walk = (btn("up") and 1 or 0) - (btn("down") and 1 or 0)
    W.update({turn = turn, walk = walk, run = btn("b"), act = btnp("a")})
    local c = Cam.pick(p.x, p.z) -- the cut: another stretch, another camera, and a place to come back to
    if c ~= Cam.current() then Cam.use(c) if W.caught_t == 0 then W.check = {x = p.x, z = p.z, h = p.h} end end
    -- steps on the beat of the stride
    local n = math.floor(p.phase / math.pi)
    if n ~= p.steps and p.moving then p.steps = n Snd.play("SFX_STEP", p.running and 0.9 or 0.45) end
    -- the radio and the heart
    Music.danger = W.danger
    if static_h then -- the radio crackles louder as it nears, and from the side of the picture it comes from (behind the camera: the middle)
      local sx = W.f.state ~= "away" and Cam.project(W.f.x, 10, W.f.z)
      sfx_set(static_h, {gain = Music.on and W.danger * 0.7 or 0, pan = sx and math.max(-1, math.min(1, (sx - 240) / 240)) or 0})
    end
    beat_t = beat_t - 1
    if W.danger > 0.3 and beat_t <= 0 and Music.on then
      Snd.play("SFX_HEART", 0.5 + W.danger * 0.5)
      beat_t = math.floor(64 - 38 * W.danger)
    end
    if W.caught_t > 0 then over_t = over_t + 1 end
  elseif state == "won" then
    over_t = over_t + 1
    if over_t > 240 and btnp("a") then state = "title" W.new(1) Cam.use(1) said = {} sound_bed(false) Music.set("title") end
  end
end

local function people(kind)
  local p, f = W.p, W.f
  if kind == "player" then
    return People.draw_player(p.x, p.z, p.h, p.moving and p.phase or nil, View.ambient(W, p.x, p.z) + 0.2)
  end
  return People.draw_figure(f.x, f.z, f.h, f.phase, math.max(0.26, View.ambient(W, f.x, f.z)))
end

local function grain(level) -- the picture breaks up as the Figure comes close
  if level < 0.2 then return end
  for _ = 1, math.floor(level * 70) do
    local g = 90 + (ticks() * 31 + _ * 17) % 140
    rect((ticks() * 37 + _ * 53) % 480, (ticks() * 19 + _ * 91) % 320, 2 + _ % 3, 1, g << 16 | g << 8 | g)
  end
end

local function hud_draw()
  local p = W.p
  -- the radio: three bars that light as it comes closer
  for i = 1, 3 do
    local lit = W.danger * 3.2 >= i - 0.4
    rect(14 + (i - 1) * 7, 28 - i * 5, 5, i * 5, lit and (i == 3 and 0xE05040 or 0xE0B040) or 0x20282E)
  end
  if p.key then rect(14, 40, 9, 5, 0xE6BE46) rect(23, 41, 6, 3, 0xE6BE46) end
  if p.breath < 1 then
    rect(14, 304, 90, 5, 0x1A2024)
    rect(14, 304, math.floor(90 * p.breath), 5, p.tired and 0xC04838 or 0x7AB0C8)
  end
  if W.prompt then text(lang.tr(W.prompt == "locked" and "try_door" or W.prompt), 240, 232, {font = "silk", align = "center", color = 0xFFFFFF, outline = 0x000000}) end
  if W.msg then
    shade(40, 252, 400, 46)
    local m = lang.tr("msg_" .. W.msg.key)
    text(m, 52, 260, 0xDDE6F0, "silk", "left", 376, math.floor((260 - W.msg.t) * 0.9))
  end
  hud.draw_toasts(110, 8, {font = "silk", w = 260})
end

function _draw()
  rect(0, 0, 480, 320, 0x040608)
  local n = View.scene(W, people)
  View.glows(W)
  faces_drawn = n
  if state == "play" then
    grain(W.danger)
    hud_draw()
    if W.caught_t > 0 then -- the screen closes from above and below, then says it
      local k = math.min(1, over_t / 40)
      rect(0, 0, 480, math.floor(160 * k), 0x000000)
      rect(0, 320 - math.floor(160 * k), 480, math.floor(160 * k), 0x000000)
      if over_t > 40 then text(lang.tr("caught"), 240, 148, {font = "arcade", align = "center", color = 0xC04838}) end
    end
  elseif state == "won" then
    local k = math.min(1, over_t / 120)
    rect(0, 0, 480, math.floor(320 * k), k >= 1 and 0xE8ECF4 or 0xB8C4D8)
    if over_t > 120 then
      text(lang.tr("won_title"), 240, 110, {font = "gothic", align = "center", color = 0x202838})
      text(lang.tr("won_text"), 240, 160, {font = "main", align = "center", color = 0x303848})
      text(lang.tr("won_deaths", {n = W.deaths}), 240, 190, {font = "silk", align = "center", color = 0x485068})
      if over_t > 240 then text(lang.tr("press"), 240, 230, {font = "silk", align = "center", color = 0x485068}) end
    end
  elseif state == "title" then
    shade(0, 40, 480, 100)
    text(lang.tr("title"), 240, 50, {font = "gothic", align = "center", color = 0xC8D8F0, outline = 0x060A10})
    text(lang.tr("press"), 240, 108, {font = "arcade", align = "center", color = (ticks() // 30) % 2 == 0 and 0xFFFFFF or 0x708098})
    shade(0, 254, 480, 66)
    local a, b, c, d = lang.tr("controls"):match("^(.-) · (.-) · (.-) · (.*)$")
    text(a, 240, 258, {font = "silk", align = "center", color = 0xC8D8F0})
    text(b, 240, 273, {font = "silk", align = "center", color = 0xC8D8F0})
    text(c .. "  ·  " .. d, 240, 288, {font = "silk", align = "center", color = 0xC8D8F0})
    text(lang.tr("hint"), 240, 303, {font = "silk", align = "center", color = 0x8898B0})
  elseif state == "explain" then E.panel(faces_drawn)
  end
end
