-- Cerezo: a top-down adventure the way the last Game Boy games were made (docs/art.md, "Game Boy"). Four tones, 8x8
-- tiles in two layers, 16x16 sprites, a status bar that is a layer of tiles, screens that slide, a pala and a lantern.
local lang = require("lang")
local Pal = require("core.pal")
local Play = require("core.play")
local UI = require("core.ui")
local Hud = require("core.hud")
local Game = require("core.game")
local Sound = require("core.sound")
local Dialog = require("core.dialog")
local Quest = require("core.quest")
local W = require("core.world")
local Menu = require("core.menu")
local E = require("core.ents")
local Save = require("core.save")
local Title = require("core.title")
local Cine = require("core.cine")
local GameOver = require("core.gameover")
local Music = require("core.music")
local FX = require("core.fx")
local S = require("core.spr")
local Explain = require("core.explain")
local Ev = require("core.events")

G = {t = 0, state = "title"} -- the game's state, global for the test script

local function show_hud()
  Hud.init()
end

local function hide_hud()
  UI.clear(0, 0, 30, 20)
  Hud.reset()
end

-- a new game: from the bed
local function set_menu_item()
  menuitem()
  menuitem(lang.tr("how_item"), function()
    if G.state == "play" and not Menu.open_ then Explain.enter() G.state = "explain" end
  end)
end

local function new_game()
  Game.reset()
  set_menu_item()
  G.state = "play"
  hide_hud()
  spr_clear()
  -- the opening: some words, then the bed (events.lua)
  Ev.intro(function()
    Pal.fade("dark", 3)
    show_hud()
    Play.enter("casa_yaya", 1, 1, "down")
  end)
end

local function continue_game()
  set_menu_item()
  Save.read()
  Pal.fade("dark", 0)
  G.state = "play"
  show_hud()
  Play.enter(Game.area, Game.cx, Game.cy, Game.face)
  Music.play(W.area.notes and W.area.notes.music)
end

local function to_title()
  G.state = "title"
  menuitem()
  hide_hud()
  Pal.fade("dark", 0)
  spr_clear()
  bg(1) bg(2)
  Title.enter()
end

function _init()
  lang.load()
  Pal.init(stored("palette", 1))
  Sound.init()
  Quest.install()
  Game.reset()
  Dialog.init(lang.code)
  UI.init()
  to_title()
end

function _resume()
  lang.load()
  Dialog.init(lang.code)
  if G.state == "play" then set_menu_item() end
end

local function can_pause()
  local h = E.hero
  return h and h.state == "walk" and not Play.slide and not Play.fading and not Dialog.active
end

function _update()
  G.t = G.t + 1
  Music.update()
  local st = G.state
  if st == "title" then
    local pick = Title.update()
    if pick then Title.leave() end
    if pick == "new" then new_game() elseif pick == "continue" then continue_game() end
    store("palette", Pal.mode)
  elseif st == "play" then
    Game.time = Game.time + 1
    if Menu.open_ then
      Menu.update()
      store("palette", Pal.mode)
    elseif Cine.running() then
      if Dialog.active then Dialog.update() end -- a scene's talk is typed and turned by the same window
      Cine.update()
      if Ev.credits_t then G.state = "credits" Cine.draw_fn = nil hide_hud() end
    elseif Dialog.active then
      Dialog.update()
      W.update(G.t)
    else
      if btnp("start") and can_pause() then Menu.open() else Play.update() end
    end
    local h = E.hero
    if h and h.state == "dead" and h.st > 70 then
      G.state = "gameover"
      hide_hud()
      GameOver.enter()
    end
    Hud.update()
  elseif st == "credits" then
    if Ev.update_credits() then
      Save.write()
      to_title()
    end
  elseif st == "explain" then
    if Explain.update() then G.state = "play" end
  elseif st == "gameover" then
    local pick = GameOver.update()
    if pick == "continue" then
      if Save.exists() then continue_game() else new_game() end
    elseif pick == "title" then to_title() end
  end
end

function _draw()
  local st = G.state
  if st == "title" then
    Title.draw()
  elseif st == "play" then
    Play.draw()
    if Cine.draw_fn then Cine.draw_fn() end
    Dialog.draw()
    Menu.draw()
  elseif st == "credits" then
    Ev.draw_credits()
  elseif st == "explain" then
    Explain.draw()
  elseif st == "gameover" then
    GameOver.draw()
  end
end
