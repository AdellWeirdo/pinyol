-- play: one level being played. It sets the level up (the world, the things, the enemies, the hero coming out of the vortex), runs a tick of everything, and
-- draws the frame: sprites first-come-first-in-front (hud, effects, the hero, enemies, things) over the four layers the world scrolls.
local C = require("core.const")
local U = require("core.util")
local W = require("core.world")
local Hero = require("core.hero")
local Foes = require("core.foes")
local Things = require("core.things")
local Fx = require("core.fx")
local Hud = require("core.hud")
local S = require("core.spr")
local Run = require("core.run")
local Sound = require("core.sound")
local Music = require("core.music")
local Levels = require("data.levels")
local Play = {}

Play.hero = nil
Play.lv = nil
Play.max_coins = 1
Play.paused = false
Play.after_t = 0 -- ticks since the hero won or died

local COIN_VALUE = {[1] = 1, [2] = 5, [3] = 10}

function Play.enter(n)
  local lv = Levels[n]
  Run.reset(n)
  Fx.clear()
  Foes.clear()
  W.load(n)
  Things.load(lv)
  Play.lv = lv
  W.on_break = Things.on_break
  Foes.coin_drop = Things.coin_drop
  Foes.on_kill = function() Run.kills = Run.kills + 1 end
  Things.on_escape = Play.start_escape
  local max = 0
  for _, t in ipairs(lv.things) do
    if t.kind == "coin" then max = max + COIN_VALUE[t.s or 1]
    elseif t.kind == "gem" then max = max + (t.k == "b" and 50 or 20)
    elseif t.kind == "diamond" then max = max + 100
    elseif t.kind == "chest" then max = max + 100 + 10 * 2 end
    if t.kind == "enemy" then Foes.spawn(t) end
  end
  Play.max_coins = math.max(1, max)
  local v = Things.vortex
  Play.hero = Hero.new(v.cx, v.cy)
  Play.hero.state = "enter"
  Play.hero.enter_t = 0
  Play.after_t = 0
  W.follow(Hero.cx(Play.hero), Play.hero.y, 1, true)
  Music.play(lv.notes.music)
  Play.setup_light()
end

function Play.start_escape()
  Run.escape = true
  Run.escape_total = (Play.lv.notes.time or 45) * 60
  Run.escape_t = Run.escape_total
  Things.escape_started()
  W.haze_amp = 1
  W.shake(2, 40)
  Music.play("escape", 100)
  Sound.play("alarm")
end

function Play.crown()
  local r = U.clamp(Run.coins / Play.max_coins, 0, 1)
  return r >= 0.85 and 3 or r >= 0.6 and 2 or r >= 0.35 and 1 or 0
end

-- the cave's spotlight: two windows cut to circles a line at a time. Inside the small one everything shows as it is; in the ring round it everything shows
-- darkened (the fade works only where a window lets FX in); outside both only the far layer and the backdrop are left.
function Play.setup_light()
  Play.dark = Play.lv.notes.dark
  if Play.dark then
    window(0, 0, 0, C.W - 1, C.H - 1, ALL)
    window(1, 0, 0, C.W - 1, C.H - 1, ALL | FX)
    window_out(BG3 | BACK)
    fade("dark", ALL, 9)
  end
end

local function circle(k, cx, cy, r)
  for y = 0, C.H - 1 do
    local dy = y - cy
    if dy > -r and dy < r then
      local dx = math.floor(math.sqrt(r * r - dy * dy))
      line_window(k, y, cx - dx, cx + dx)
    else
      line_window(k, y, 1, 0)
    end
  end
end

local function light(h, t)
  if not Play.dark then return end
  local r = Play.dark + math.floor(math.sin(t / 20) * 2)
  local sx = math.floor(Hero.cx(h) - W.cam_x)
  local sy = math.floor(Hero.cy(h) - W.cam_y)
  circle(0, sx, sy, r)
  circle(1, sx, sy, r + 22)
end

-- one tick; returns "win", "dead" or nil
function Play.update(t)
  local h = Play.hero
  Run.t = Run.t + 1
  Hero.update(h, Foes)
  if h.state ~= "dead" and h.state ~= "win" and h.state ~= "enter" then
    Foes.touch_hero(h)
  end
  Foes.update(h)
  Things.update(h, Play)
  Fx.update()
  if Run.escape and h.state ~= "dead" and h.state ~= "win" then
    Run.escape_t = Run.escape_t - 1
    if Run.escape_t < 600 and Run.escape_t % 60 == 0 then Sound.play("alarm") end
    if Run.escape_t <= 0 then
      Run.fail = "time"
      h.hearts, h.state, h.st, h.vy, h.dead_t = 0, "dead", 0, -4, 0
      Sound.play("die")
    end
    if Things.at_vortex(h) then
      h.state, h.win_t, h.vx = "win", 0, 0
      Music.jingle("nivel_ok", 4, false)
      Run.escape = false
      W.haze_amp = 0
    end
  end
  if h.state == "dead" and Play.after_t == 0 then Music.jingle("muerte", 2, false) end
  if h.state == "dead" or h.state == "win" then Play.after_t = Play.after_t + 1 end
  if h.state ~= "dead" then W.follow(Hero.cx(h), h.y + h.h, h.face, false) end
  W.update(t)
  if h.state == "win" and Play.after_t > 110 then return "win" end
  if h.state == "dead" and Play.after_t > 100 then return "dead" end
  return nil
end

function Play.draw(t)
  local h = Play.hero
  local cx, cy = math.floor(W.cam_x) + W.shake_x, math.floor(W.cam_y) + W.shake_y
  S.begin()
  Hud.draw(h, t)
  Fx.draw(cx, cy)
  if not (h.state == "enter" and h.enter_t < 16) then Hero.draw(h, cx, cy) end
  Foes.draw(cx, cy)
  Things.draw(cx, cy)
  W.scroll(t)
  light(h, t)
end

return Play
