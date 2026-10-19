-- Audreygotchi for Game Boy: the board game's whole core (core/, a port of audreygotchi/core) under a front end in
-- the Game Boy's four tones. The core decides everything; this file runs its clock, hands it the buttons, plays the
-- sounds it names, saves when it says, and draws its snapshot (s:ui()) the way the board's renderer did.
--
-- Buttons: the board had three (A left, B ok, C right); here the cross moves (left/right, and up/down in lists),
-- A is the board's B (ok), B is the board's long B (back), START is the board's A+C (call her, "Buscar").
-- Time: pinyol keeps no clock while the console is off, so the game asks the date and the hour once and its clock
-- runs while it plays, TIME_SCALE times faster than real time (faster still when she sleeps through the night).
local ui = require("ui")
local hud = require("hud")
local room = require("room")
local actor = require("actor")
local screens = require("screens")
local games = require("games")
local cinema = require("cinema")
local world = require("world")
local title = require("title")
local sfx = require("sfx")
local strings = require("strings")
local Clock = require("core.clock")
local State = require("core.state")
local save = require("core.save")
local lifecycle = require("core.lifecycle")
local T = ui.T

TIME_SCALE = 60       -- game seconds a real second: a game day in 24 minutes (global: tests change it)
NIGHT_SCALE = 4       -- asleep in the dark at night, the night goes by this much faster again
local LABEL_TICKS, BOOST_TICKS, RESULT_TICKS, STICKER_TICKS = 90, 90, 192, 168
local SYSTEM_HOLD, CONFIRM_HOLD = 180, 120 -- START held 3 s: Modo Sistema; A held 2 s confirms there

S = nil               -- the game (global: tests read it)
scene = "title"       -- title, setup, game
local t, now_ms, frac = 0, 0, 0
local snap = {}
local last_sel, label_until = -1, 0
local seen_seq, last_press = nil, -1000
local boost, boost_until = nil, 0
local result, result_until, result_seq = nil, 0, nil
local sticker, sticker_until, sticker_seq = nil, 0, nil
local held_used = false
local game_kind, game_phase = nil, nil

local function start_game(s)
  S = s
  scene = "game"
  seen_seq = s.sound_seq
  snap = s:ui()
end

local function new_game(v) -- v = {year, month, day, hour, minute}
  math.randomseed(ticks() * 7919 + v[3] * 373 + v[4] * 31 + v[5])
  local clock = Clock.start({v[1], v[2], v[3]}, v[4] * 3600 + v[5] * 60)
  local s = State.new(clock)
  lifecycle.start_birth(s, now_ms)
  start_game(s)
  store("save", save.dump(s))
end

local function continue_game()
  local s = save.load(stored("save"), now_ms)
  if not s then scene = "title" title.title.enter({has_save = false}) return end
  math.randomseed(ticks() * 7919 + s.clock:now() % 100000)
  start_game(s)
end

function _init()
  local has = stored("save") ~= nil
  title.title.enter({has_save = has})
end

-- ------------------------------------------------------------------ the buttons, to the core

local LIST_MODES = {action_feed = true, action_play = true, action_heal = true, action_bath = true, settings = true,
                    system = true, status = false}

local function press(fn, ...) last_press = t fn(S, ...) end

local function input()
  local m = S.mode
  if btnt("start") == SYSTEM_HOLD and m ~= "system" and m ~= "birth" and m ~= "farewell" then
    press(S.enter_system_mode, now_ms)
    held_used = true
    return
  end
  if btnr("start") then
    if held_used then held_used = false
    elseif m == "main" then press(S.search, now_ms) end
  end
  if m == "system" then
    if btnt("a") == CONFIRM_HOLD then press(S.system_choose, now_ms, true) held_used = true return end
    if btnr("a") then
      if held_used then held_used = false else press(S.system_choose, now_ms, false) end
      return
    end
  elseif btnp("a") then
    press(S.press_ok, now_ms)
  end
  if btnp("b") then press(S.cancel_action, now_ms) end
  local vertical = LIST_MODES[m]
  if btnp("left", 18, 6) or (vertical and btnp("up", 18, 6)) then press(S.move_left) ui.blip() end
  if btnp("right", 18, 6) or (vertical and btnp("down", 18, 6)) then press(S.move_right) ui.blip() end
end

-- ------------------------------------------------------------------ what the core says

local function heard()
  local seq = snap.sound_seq or 0
  if seq == seen_seq then return end
  seen_seq = seq
  local name = snap.sound
  if not name then return end
  local answering = t - last_press < 60
  sfx.play(name, sfx.volume_for(name, S.sound_mode, snap.night, answering, S.volume))
  if hud.BOOSTS[name] then boost, boost_until = hud.BOOSTS[name], t + BOOST_TICKS end
  if name == "sancho" or name == "vuelve" then cinema.start_cut(name, actor.tick()) end
  if S.minigame_action then actor.note_game(S.minigame_action) end
end

local function cards()
  local r = snap.game_result
  if r and r.seq ~= result_seq then
    if result_seq ~= nil then result, result_until = r, t + RESULT_TICKS end
    result_seq = r.seq
  end
  local st = snap.new_sticker
  if st and st.seq ~= sticker_seq then
    if sticker_seq ~= nil then sticker, sticker_until = st.id, t + STICKER_TICKS end
    sticker_seq = st.seq
  end
end

local function game_tunes() -- each game's own tune as it opens; the Trile's while its boxes shuffle
  local g = snap.game or {}
  local vol = sfx.volume_for("gana", S.sound_mode, snap.night, true, S.volume)
  if g.kind ~= game_kind then
    game_kind = g.kind
    if g.kind then sfx.play("tema_" .. g.kind, vol) end
  end
  if g.phase ~= game_phase then
    game_phase = g.phase
    if g.kind == "boxes" and g.phase == "shuffle" then sfx.play("mezcla", vol) end
  end
end

local function advance_clock()
  local scale = TIME_SCALE
  if (S.sleeping or S.deep_sleep) and not S.light_on and S:is_night() then scale = scale * NIGHT_SCALE end
  frac = frac + scale / 60
  local whole = math.floor(frac)
  frac = frac - whole
  if whole > 0 then S.clock:advance(whole) end
  S.clock.ms = now_ms
end

local function update_game()
  advance_clock()
  input()
  world.weather(S)
  S:update(now_ms)
  world.friends(S, now_ms, t)
  world.ears(S, now_ms, sfx.busy())
  snap = S:ui()
  heard()
  game_tunes()
  cards()
  games.update()
  actor.update(snap)
  room.update()
  if snap.selected_index ~= last_sel then
    if last_sel >= 0 then label_until = t + LABEL_TICKS end
    last_sel = snap.selected_index
  end
  if S:save_due(now_ms) then
    store("save", save.dump(S))
    S:saved(now_ms)
  end
end

function _update()
  t = t + 1
  now_ms = t * 1000 // 60
  sfx.update()
  if scene == "title" then
    local r = title.title.update()
    if r == "continue" then continue_game()
    elseif r == "new" then scene = "setup" title.setup.enter() end
  elseif scene == "setup" then
    local r = title.setup.update()
    if r == "back" then scene = "title" title.title.enter({has_save = stored("save") ~= nil})
    elseif type(r) == "table" then new_game(r) end
  else
    update_game()
  end
end

-- ------------------------------------------------------------------ drawing

local function draw_result()
  if t >= result_until or not result then return end
  local x, y, w, h = 140, 96, 200, 96
  ui.box(x, y, w, h)
  local stars = result.stars or 0
  for i = 0, 2 do
    local cx = x + 52 + i * 48
    local on = i < stars and (t - (result_until - RESULT_TICKS)) > i * 20
    local id = on and "IC_ST_STAR" or nil
    if id then actor.icon(id, cx, y + 40) else circ(cx, y + 40, 10, T[2]) end
  end
  if result.won then actor.icon("IC_FX_HEART", x + w // 2, y + 76) end
end

local function draw_sticker()
  if t >= sticker_until or not sticker then return end
  local rise = (t - (sticker_until - STICKER_TICKS)) // 2
  local cx, cy = 360, 200 - math.min(rise, 60)
  circ(cx, cy, 30, T[4]) circ(cx, cy, 28, T[1])
  local icons = {comida = "IC_OPT_MEAL", mimos = "IC_FX_HEART", bano = "IC_MENU_BATH"}
  actor.icon(icons[sticker] or "IC_ST_STAR", cx, cy)
end

local function cut(mid, floor) return cinema.draw_cut(snap, actor.tick(), mid, floor) end

local function draw_main(menu)
  room.draw(snap, cut)
  hud.topbar(snap, t, t < boost_until and boost or nil)
  local edge = hud.badge(snap, S.clock)
  hud.popup(snap, edge)
  draw_result()
  draw_sticker()
  if snap.away then screens.away(snap)
  elseif snap.hidden then screens.seek(snap, t)
  elseif menu ~= false then hud.menu(snap, t, label_until) end
  if snap.grow_due and S.mode == "main" and (t // 30) % 2 == 0 then
    ui.box(100, 120, 280, 40)
    ui.text(strings.T.grow_call, 240, 132, T[4], "center")
  end
end

local function draw_placeholder(what) -- a scene the Game Boy front end does not draw yet: the room and a note
  room.draw(snap)
  hud.topbar(snap, t)
  ui.box(40, 100, 400, 80)
  ui.text(what, 240, 120, T[4], "center")
  ui.text("A / B", 240, 146, T[3], "center")
end

local DRAW = {
  main = draw_main,
  action_feed = function() draw_main(false) if not screens.feed(snap, t) then hud.menu(snap, t, 0) end end,
  action_play = function() draw_main(false) if not screens.play(snap, t) then hud.menu(snap, t, 0) end end,
  action_heal = function() draw_main(false) hud.menu(snap, t, 0) screens.heal(snap, t) end,
  action_bath = function() draw_main(false) hud.menu(snap, t, 0) screens.bath(snap, t) end,
  settings = function() draw_main(false) hud.menu(snap, t, 0) screens.settings(snap, t) end,
  system = function() draw_main(false) screens.system(snap, t) end,
  status = function() screens.status(snap) end,
  ask = function() draw_main(false) screens.question(snap, snap.ask or "bed", snap.ask_yes) end,
  sitter_confirm = function() draw_main(false) screens.question(snap, "sitter", snap.sitter_yes) end,
  guide = function() screens.guide() end,
  action_minigame = function() games.draw(snap, now_ms) end,
  birth = function() cinema.birth(snap, now_ms) end,
  farewell = function() cinema.farewell(snap, now_ms) end,
  grow = function()
    cinema.grow(snap, now_ms, room)
    hud.topbar(snap, t)
    hud.menu(snap, t, 0, true)
  end,
  sancho_intro = function()
    cinema.sancho_intro(snap, actor.tick(), room, function(step)
      local labels = snap.menu_labels
      if step ~= "menu" then -- his button is not there yet
        local without = {}
        for _, l in ipairs(labels) do if l ~= "Sitter" then without[#without + 1] = l end end
        snap.menu_labels = without
      end
      hud.menu(snap, t, 0, step ~= "menu")
      snap.menu_labels = labels
    end)
    hud.topbar(snap, t)
  end,
}

function _draw()
  if scene == "title" then title.title.draw() return end
  if scene == "setup" then title.setup.draw() return end
  if snap.powered_off then screens.off() return end
  local draw = DRAW[S.mode]
  if draw then draw() else draw_placeholder(tostring(S.mode)) end
end
