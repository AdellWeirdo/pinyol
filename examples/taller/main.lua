-- Taller de los Autómatas: a beat 'em up the way Capcom's CPS2 made them (docs/art.md, "CPS2"). Three clockmakers in clockwork exo-frames fight the rebel automatons through a clockmakers'
-- street, a roaring factory and the great clock tower, to the giant clock Péndulo; parts torn from the broken automatons change how each one fights. Every pixel at the screen's own
-- 480x320, characters of 15 colours with second colours borrowed from another palette, a floor in perspective where depth decides what is in front.
local lang = require("lang")
local juice = require("juice")
local Play = require("core.play")
local Sound = require("core.sound")
local Music = require("core.music")
local Run = require("core.run")
local Game = require("core.game")
local In = require("core.input")
local Bot = require("core.bot")
local Boss = require("core.boss")
local Foes = require("core.foes")
local Items = require("core.items")
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

local function to_play(hero)
  In.bot = nil
  G.state = "play"
  G.hero_id = hero
  Play.enter(hero)
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
  Play.enter(Scr.HEROES[math.random(#Scr.HEROES)])
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
      Play.enter(Scr.HEROES[Game.last])
      Explain.enter(Play)
      G.state, G.explain_from = "explain", "title"
    elseif pick == "demo" then demo() end
  elseif st == "select" then
    local pick = Scr.select.update()
    if pick == "back" then to_title() elseif pick then to_play(pick) end
  elseif st == "play" or st == "demo" then
    if st == "demo" then
      G.demo_t = G.demo_t + 1
      Bot.step(Play.hero)
      if btnp("a") or btnp("b") or btnp("start") or G.demo_t > 60 * 30 or Play.state == "over" then to_title() return end
    end
    if st == "play" and In.bot then Bot.step(Play.hero) end
    In.update()
    Play.update(G.t)
    if st == "play" then
      Ach.tick(Play)
      if Play.state == "over" then G.state = "continue" Scr.cont.enter() end
      if Play.state == "clear" and Play.clear_t > 220 then
        G.state = "results"
        Scr.results.enter()
        if Run.boss_dead then Game.finish(G.hero_id) Ach.finish(G.hero_id) end
      end
    end
  elseif st == "continue" then
    local pick = Scr.cont.update()
    if pick == "yes" then
      Run.continues = Run.continues + 1
      Run.score = 0 -- as in the arcade: a continue costs the score
      Play.continue()
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
      if Run.boss_dead then
        G.state = "ending"
        Scr.ending.enter()
      else
        Play.start_stage(Run.stage + 1)
        G.state = "play"
      end
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

-- for the test script: straight into a stage, to a place
function dbg_play(hero, stage, x)
  to_play(hero or "vera")
  if stage and stage > 1 then Play.start_stage(stage) end
  if x then dbg_go(x) end
  return true
end

function dbg_go(x)
  local h = Play.hero
  local L = require("core.level")
  h.x = x
  Play.cam = math.max(0, x - 200)
  local st = Play.stage()
  while st.events[Play.ev_i] and st.events[Play.ev_i].at < Play.cam - 4 do Play.ev_i = Play.ev_i + 1 end -- (what was passed is not put)
  Play.lock, Play.queue = nil, {}
  Foes.clear()
  return true
end

function dbg_boss()
  dbg_go(C.STAGE_W - 300)
  Run.stage = 3
  Play.cam = 2400
  Play.state = "boss"
  Boss.enter(2400)
  return true
end
function dbg_state()
  return {state = G.state, play = Play.state, lives = Play.hero and Play.hero.lives, hp = Play.hero and Play.hero.hp, score = Run.score, boss = Boss.hp, cam = Play.cam,
          hero = Play.hero and Play.hero.st, stage = Run.stage, foes = Foes.count(), lock = Play.lock}
end
function dbg_foe(kind, side, y) Foes.spawn_at(kind, side or "r", Play.cam, y) return true end
function dbg_part(kind) Play.hero:take_part(kind or "hammer") return true end
function dbg_meter() Play.hero.meter = 100 return true end
function dbg_die() local h = Play.hero h.inv = 0 h.god = false h:hurt(9999, 1, {down = true}) return h.lives end
function dbg_boss_kill() Boss.hp = 1 if Boss.ent then Boss.ent:hit(5, 1, {}, 9999) end return Boss.hp end
function dbg_clear() Foes.clear() Play.queue = {} return true end
function dbg_explain() Explain.enter(Play) G.state, G.explain_from = "explain", "play" return true end
function dbg_demo() demo() return true end
function dbg_god() Play.hero.god = true return true end
function dbg_bot() Bot.start() In.bot = true return true end
function dbg_items() return #Items.list end
