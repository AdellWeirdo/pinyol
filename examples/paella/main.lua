-- Paella de combate: a run-and-gun the way the Neo Geo made them (docs/art.md, "Neo Geo"). Six cooks, each its own weapon, against the Gaviotas Mecánicas along a harbour, a main
-- street (with a tractor) and a beach, to a giant seagull. Every pixel at the screen's native 480x320 from packed pictures; a chef is two sprites (legs and torso) pinned at the hips.
local lang = require("lang")
local juice = require("juice")
local Play = require("core.play")
local Sound = require("core.sound")
local Music = require("core.music")
local Run = require("core.run")
local Game = require("core.game")
local In = require("core.input")
local Bot = require("core.bot")
local Chef = require("core.chef")
local Boss = require("core.boss")
local Hud = require("core.hud")
local Scr = require("core.screens")
local Explain = require("core.explain")
local Ach = require("core.ach")
local C = require("core.const")

G = {t = 0, state = "title"}

local function set_menu()
  menuitem()
  menuitem(lang.tr("how_item"), function()
    if G.state == "play" then Explain.enter(Play) G.state, G.explain_from = "explain", "play" end
  end)
end

local function to_title()
  menuitem()
  In.bot = nil
  G.state = "title"
  Scr.title.enter()
end

local function to_select()
  G.state = "select"
  Scr.select.enter()
end

local function to_play(chef)
  In.bot = nil
  G.state = "play"
  G.chef_id = chef
  Play.enter(chef)
  set_menu()
end

function _init()
  show(0) -- no 240x160 world: every pixel at the screen's own resolution
  lang.load()
  Sound.init()
  Game.load()
  to_title()
end

function _resume()
  lang.load()
  if G.state == "play" then set_menu() end
end

local function demo()
  G.state = "demo"
  G.demo_t = 0
  Play.enter(Scr.CHEFS[math.random(#Scr.CHEFS)])
  Bot.start()
  In.bot = true
end

function _update()
  G.t = G.t + 1
  if juice.update() then return end
  Music.update()
  local st = G.state
  if st == "title" then
    local pick = Scr.title.update()
    if pick == "start" then to_select()
    elseif pick == "how" then
      Play.enter(Scr.CHEFS[Game.last])
      Explain.enter(Play)
      G.state, G.explain_from = "explain", "title"
    elseif pick == "demo" then demo() end
  elseif st == "select" then
    local pick = Scr.select.update()
    if pick == "back" then to_title() elseif pick then to_play(pick) end
  elseif st == "play" or st == "demo" then
    if st == "demo" then
      G.demo_t = G.demo_t + 1
      Bot.step(Play.chef)
      if btnp("a") or btnp("b") or btnp("start") or G.demo_t > 60 * 24 or Play.state == "over" then to_title() return end
    end
    if st == "play" and In.bot then Bot.step(Play.chef) end
    In.update()
    Play.update(G.t)
    if st == "play" then
      Ach.tick(Play)
      if Play.state == "over" then G.state = "continue" Scr.cont.enter() end
      if Play.state == "clear" and Play.clear_t > 240 then
        G.state = "results"
        Scr.results.enter()
        Game.finish(G.chef_id)
        Ach.mission(G.chef_id)
      end
    end
  elseif st == "continue" then
    local pick = Scr.cont.update()
    if pick == "yes" then
      Run.continues = Run.continues + 1
      Run.score = 0 -- as in the arcade: a continue costs the score
      local c = Play.chef
      c.lives, c.state, c.dead_t = C.LIVES, "play", 0
      c.x, c.y, c.vx, c.vy, c.ground, c.inv = Play.cam + 120, C.FLOOR, 0, 0, true, C.INVULN
      c.weapon, c.up_shots = c.base, 0
      c.grenades = 8
      Play.state = Boss.active and "boss" or "play"
      Music.play(Boss.active and "jefe" or require("core.level").ZONES[Play.zone].music, 200)
      G.state = "play"
    elseif pick == "no" then
      Game.save_best(Run.score)
      Music.jingle("game_over", 4, false)
      G.state, G.over_t = "over", 0
    end
  elseif st == "over" then
    G.over_t = G.over_t + 1
    if G.over_t > 200 and (btnp("a") or btnp("start")) then to_title() end
  elseif st == "results" then
    if Scr.results.update() then
      G.state = "ending"
      Scr.ending.enter()
    end
  elseif st == "ending" then
    if Scr.ending.update() then to_title() end
  elseif st == "explain" then
    if Explain.update() then
      if G.explain_from == "title" then to_title() else G.state = "play" end
    end
  end
end

function _draw()
  local st = G.state
  if st == "title" then Scr.title.draw()
  elseif st == "select" then Scr.select.draw()
  elseif st == "play" or st == "demo" or st == "continue" or st == "over" then
    Play.draw_world()
    if st == "over" then
      rect(0, 0, 480, 320, 0x000000)
      Hud.label(lang.tr("over_title"), 240, 130, {align = "center", scale = 2, fit = 440, gradient = 0xFF4040})
    else
      Hud.draw(Play, G.t)
      if st == "demo" then Hud.label(lang.tr("demo"), 240, 296, {align = "center", color = (G.t // 30) % 2 == 0 and 0xFFFFFF or 0xFFD040}) end
      if st == "continue" then Scr.cont.draw() end
    end
  elseif st == "results" then Scr.results.draw()
  elseif st == "ending" then Scr.ending.draw()
  elseif st == "explain" then Explain.draw()
  end
  juice.draw()
end

-- for the test script: straight into a mission, to a place
function dbg_play(chef, x)
  to_play(chef or "estrella")
  if x then dbg_go(x) end
  return true
end

function dbg_go(x)
  local c = Play.chef
  local L = require("core.level")
  c.x = x
  Play.cam = math.max(0, x - 200)
  while L.EVENTS[Play.ev_i] and L.EVENTS[Play.ev_i].at < Play.cam + C.W - 20 do Play.ev_i = Play.ev_i + 1 end -- (what was passed is not put)
  require("core.foes").clear()
  return true
end

function dbg_boss()
  dbg_go(C.LEVEL_W + 100)
  Play.cam = C.LEVEL_W
  Play.state = "boss"
  Boss.enter(C.LEVEL_W)
  return true
end
function dbg_state() return {state = G.state, play = Play.state, lives = Play.chef and Play.chef.lives, score = Run.score, hp = Boss.hp, cam = Play.cam, chef_state = Play.chef and Play.chef.state} end
function dbg_boss_kill() Boss.hp = 1 Boss.pot_open = true Boss.damage(5) return Boss.hp end
function dbg_die() local c = Play.chef c.inv = 0 Chef.hurt() return c.lives end
function dbg_explain() Explain.enter(Play) G.state, G.explain_from = "explain", "play" return true end

function dbg_tractor()
  local T = require("core.tractor")
  T.park(Play.cam + 300)
  local c = Play.chef
  c.x, c.y, c.vy, c.ground = Play.cam + 300, C.FLOOR - 140, 2, false
  return true
end
function dbg_vehicle() return Play.chef.vehicle ~= nil end
function dbg_pow()
  local P = require("core.pows")
  P.add("grandma", Play.cam + 300, "a")
  return true
end
function dbg_pows() return Run.pows end
function dbg_demo() demo() return true end
function dbg_foe(kind, off)
  local F = require("core.foes")
  F.spawn_at(kind, "r", off or 0, Play.cam)
  return true
end
function dbg_boss_open() Boss.pot_open = true Boss.state = "pot" Boss.st = 100 return true end
function dbg_eject() local T = require("core.tractor") if T.active then T.eject(T.active) end return true end
function dbg_print() local c = Play.chef print(string.format("state=%s play=%s lives=%d chef=%s inv=%d dead_t=%d veh=%s", G.state, Play.state, c.lives, c.state, c.inv, c.dead_t, tostring(c.vehicle and c.vehicle.state))) return true end
function dbg_god() Play.chef.god = true return true end
function dbg_bot() Bot.start() In.bot = true return true end
