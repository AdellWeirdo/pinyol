-- Botín: a treasure-hunting platformer the way the Game Boy Advance made them (docs/art.md, "Game Boy Advance"). Four background layers, sixteen-colour palettes,
-- sprites that turn, and the effects of a line at a time. Four worlds, four pieces of a jewel in each, a frog that starts the escape, and a Golem.
local lang = require("lang")
local Play = require("core.play")
local Sound = require("core.sound")
local Trans = require("core.trans")
local Music = require("core.music")
local Title = require("core.title")
local Map = require("core.map")
local Results = require("core.results")
local Game = require("core.game")
local Run = require("core.run")
local In = require("core.input")
local Bot = require("core.bot")
local Hero = require("core.hero")
local Boss = require("core.boss")
local Explain = require("core.explain")
local Ach = require("core.ach")

G = {t = 0, state = "title", level = 1}

local DEMO_TICKS = 60 * 22

local function set_menu()
  menuitem()
  menuitem(lang.tr("how_item"), function()
    if G.state == "play" and not Trans.active() then Explain.enter(Play) G.state = "explain" end
  end)
end

local function to_title()
  menuitem()
  Boss.reset()
  In.bot = nil
  G.state = "title"
  Title.enter()
end

local function go(fn)
  Trans.out(function() fn() Trans.into() end)
end

local function to_map(at)
  menuitem()
  In.bot = nil
  G.state = "map"
  Map.enter(at)
end

local function to_level(n)
  G.level = n
  In.bot = nil
  Boss.reset()
  G.state = "play"
  Play.enter(n)
  if n == 5 then Boss.enter(Play) end
  set_menu()
end

function _init()
  lang.load()
  Sound.init()
  palette("OBJ", true)
  Game.load()
  Ach.init()
  to_title()
end

function _resume()
  lang.load()
  if G.state == "play" then set_menu() end
end

local function after_level(outcome)
  if outcome == "win" then
    local crown = G.level < 5 and Play.crown() or 0
    if G.level < 5 then
      Game.finish_level(G.level, Run, crown)
      Game.stats.broken = Game.stats.broken + Run.broken
      Game.stats.kills = Game.stats.kills + Run.kills
      Game.save()
      Ach.level_done(G.level, Run, crown, Play.hero)
      go(function() G.state = "results" Results.enter(G.level, crown) end)
    else
      Game.boss_done = true
      Game.save()
      Ach.boss()
      go(function() G.state = "ending" G.ending_t = 0 Results.enter(4, 0) Music.play("final", 200) end)
    end
  else
    Game.stats.deaths = Game.stats.deaths + 1
    go(function() G.state = "over" G.over_sel = 1 Music.jingle("game_over", 4, false) end)
  end
end

function _update()
  G.t = G.t + 1
  Music.update()
  if Trans.active() then Trans.update() return end
  local st = G.state
  if st == "title" then
    local pick = Title.update()
    if pick == "new" then go(function() Game.reset() Game.save() to_map(1) end)
    elseif pick == "continue" then go(function() Game.load() to_map(1) end)
    elseif pick == "how" then go(function() G.state = "play" Play.enter(1) Explain.enter(Play) G.state = "explain" end)
    elseif pick == "demo" then
      go(function() G.state = "demo" G.demo_t = 0 Play.enter(1) Bot.start() In.bot = true end)
    end
  elseif st == "demo" then
    G.demo_t = G.demo_t + 1
    Bot.step(Play.hero)
    In.update()
    local out = Play.update(G.t)
    local real = btnp("a") or btnp("b") or btnp("start")
    if real or out or G.demo_t > DEMO_TICKS then go(function() to_title() end) end
  elseif st == "map" then
    local pick = Map.update()
    if pick == "title" then go(to_title)
    elseif pick then go(function() to_level(pick) end) end
  elseif st == "play" then
    if In.bot then Bot.step(Play.hero) end
    In.update()
    if Boss.active then Boss.update(Play) end
    local out = Play.update(G.t)
    if Boss.active and Boss.done_t and Boss.done_t > 120 and Play.hero.state ~= "win" then
      Play.hero.state, Play.hero.win_t = "win", 0
      Music.jingle("nivel_ok", 4, false)
      Play.after_t = 0
    end
    Ach.tick(Run, Play.hero)
    if out then after_level(out) end
  elseif st == "results" then
    if Results.update() then go(function() to_map(math.min(G.level + 1, 4)) end) end
  elseif st == "over" then
    if btnp("a") or btnp("start") then go(function() to_level(G.level) end)
    elseif btnp("b") then go(function() to_map(math.min(G.level, 4)) end) end
  elseif st == "ending" then
    G.ending_t = G.ending_t + 1
    Results.t = Results.t + 1
    if G.ending_t > 240 and (btnp("a") or btnp("start")) then go(function() to_map(1) end) end
  elseif st == "explain" then
    if Explain.update() then G.state = "play" end
  end
end

function _draw()
  local st = G.state
  if st == "title" then Title.draw() Title.draw_text()
  elseif st == "map" then Map.draw() Map.draw_text()
  elseif st == "play" or st == "demo" then
    Play.draw(G.t)
    if Boss.active then Boss.draw(Play) end
    if st == "demo" then text(lang.tr("demo"), 240, 300, {font = "gba_small", align = "center", color = (G.t // 30) % 2 == 0 and 0xFFFFFF or 0xFFD040, outline = 0x301808}) end
  elseif st == "results" then Results.draw() Results.draw_text()
  elseif st == "over" then
    Play.draw(G.t)
    shade(0, 0, 480, 320)
    text(lang.tr("over_title"), 240, 110, {font = "gba_title", align = "center", color = 0xFF6050, outline = 0x301808})
    text(lang.tr(Run.fail == "time" and "over_time" or "over_dead"), 240, 150, {font = "gba_small", align = "center", color = 0xFFFFFF})
    text(lang.tr("over_retry"), 240, 200, {font = "gba_body", align = "center", color = 0xFFFFFF, outline = 0x301808})
    text(lang.tr("over_map"), 240, 230, {font = "gba_small", align = "center", color = 0xE0E0E0})
  elseif st == "ending" then Results.draw() Ach.ending_text(G.ending_t)
  elseif st == "explain" then Explain.draw()
  end
end

-- for the test script: straight into a level, without the title and the map
function dbg_level(n)
  Trans.mode = nil
  to_level(n)
  return true
end

function dbg_bot()
  Bot.start()
  In.bot = true
  return true
end

function dbg_hero() local h = Play.hero return {x = h.x, y = h.y, hearts = h.hearts, state = h.state} end

-- put the hero standing at a cell (test script)
function dbg_tp(cx, cy)
  local h = Play.hero
  h.x, h.y, h.vx, h.vy, h.state = cx * 16 + 2, (cy + 1) * 16 - h.h, 0, 0, "move"
  Play.hero.enter_t = 99
  require("core.world").follow(h.x, h.y, 1, true)
  return true
end

function dbg_run() return {coins = Run.coins, jewels = Run.jewel_count(), escape = Run.escape, key = Run.key, broken = Run.broken} end

function dbg_boss_hit(n) for _ = 1, n do Boss.head_open = true Boss.hurt_t = 0 Boss.damage(1) end return Boss.hp end
function dbg_boss() return {hp = Boss.hp, state = Boss.state, active = Boss.active} end
function dbg_hurt(n) local h = Play.hero h.inv = 0 Hero.hurt(h, h.x + 40, n or 1) return h.hearts end
function dbg_time_out() Run.escape_t = 2 return true end

function dbg_cell(cx, cy) return require("core.world").cell(cx, cy) end

function dbg_print() local h = Play.hero print(string.format("hero x=%.1f y=%.1f vy=%.2f vx=%.2f st=%s ground=%s", h.x, h.y, h.vy, h.vx, h.state, tostring(h.ground))) return true end

function dbg_explain() Explain.enter(Play) G.state = "explain" return true end
