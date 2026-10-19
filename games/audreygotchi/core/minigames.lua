-- minigames: Jugar's games, their levels, stars and rewards (a port of audreygotchi/core/minigames.py).
--
-- The board of the game being played lives in `s._minigame_runtime` (a table, transient: never saved); its idle
-- deadline in `s._minigame_deadline_ms` (transient too). `game_view(s)` is the board the UI draws.
local util = require("core.util")
local game_boxes = require("core.game_boxes")
local game_brush = require("core.game_brush")
local game_feather = require("core.game_feather")
local game_knots = require("core.game_knots")
local game_laser = require("core.game_laser")
local game_simon = require("core.game_simon")
local M = {}

-- the games added 2026-10-05, turn by turn behind one interface: start(rt, level, now), left/right/press(rt, now)
-- -> result or nil, tick(rt, now), over(rt, now), won(rt), view(rt)
M.TURN_GAMES = {boxes = game_boxes, simon = game_simon, laser = game_laser, brush = game_brush}
M.TURN_ACTIONS = {["Juego:Cajas"] = "boxes", ["Juego:Simon"] = "simon", ["Juego:Laser"] = "laser",
                  ["Juego:Cepillar"] = "brush"}
-- what each result sounds like (the speaker has a pattern for each, or keeps silent)
M.TURN_SOUNDS = {found = "encontrada", empty = "aprieta", catch = "encontrada", miss = "aprieta",
                 bored = "aprieta", knot = "tira", swat = "enfado", won = "libre",
                 lost = "aprieta", round = "libre"}

M.BRUSH_CLEANS = 10.0      -- dirt a brushing takes off (the owner's yes, 2026-10-05)
M.GAME_IDLE_MS = 120000    -- a turn-based game left this long without a press ends (it is lost)
M.GAME_INTRO_MS = 2500     -- a game's intro, before what runs on time starts (a press ends it)
M.BOARD_KINDS = {"knots", "feather_path", "boxes", "simon", "laser", "brush"}

local GAMES = {   -- games with a level: their action, and what losing says
  feather = {"Juego:PalitoPlumas", "Las plumas ganan hoy"},
  knot = {"Juego:QuitaNudos", "El nudo ganó... grr"},
  boxes = {"Juego:Cajas", "¡Ni me viste!"},
  simon = {"Juego:Simon", "Uy, desafinamos"},
  laser = {"Juego:Laser", "Ese punto es muy listo"},
  brush = {"Juego:Cepillar", "¡Basta de cepillo!"},
}
M.LEVELS = 3   -- easy, medium, hard

M.GAME_NAMES = {["Juego:PalitoPlumas"] = "Palito con plumas", ["Juego:Cepillar"] = "Cepillarla",
                ["Juego:QuitaNudos"] = "Quita nudos", ["Juego:Laser"] = "Puntero láser",
                ["Juego:Cajas"] = "Trile de cajas", ["Juego:Simon"] = "Simón",
                ["Juego:SiguelaCasa"] = "Siguela por la casa"}

local function clear(t) for k in pairs(t) do t[k] = nil end end

local function truthy(v) -- Python truthiness of a number-or-None field
  return v ~= nil and v ~= false and v ~= 0
end

local function runtime(s)
  local rt = s._minigame_runtime
  if type(rt) ~= "table" then
    rt = {}
    s._minigame_runtime = rt   -- transient
  end
  return rt
end

local function deadline_ms(s, fallback)
  fallback = fallback or 0
  local v = util.get(s, "_minigame_deadline_ms", fallback)
  if type(v) ~= "number" then
    return util.int(fallback)
  end
  return util.int(v)
end

local function set_deadline_ms(s, ts_ms)
  s._minigame_deadline_ms = util.int(ts_ms)   -- transient
end

-- ported as is: nothing calls it (in the Python either)
function M._set_cursor_from_choice(s, candidate_idx, options)
  options = options or 3
  if options <= 1 then
    s.minigame_cursor = 0.0
    return
  end
  local cand = math.max(0, math.min(util.int(options - 1), util.int(candidate_idx)))
  s.minigame_cursor = (cand + 0.0) * (100.0 / (options - 1))
end

function M.minigame_profile(s, action)
  local base = {
    speed = 62.0,
    half = 12.0,
    target = 50.0,
  }
  if action == "Juego" then
    base.speed, base.half, base.target = 76.0, 10.0, 52.0
  end
  return base
end

local LABELS = {
  ["Juego:QuitaNudos"] = "Quita nudos",
  ["Juego:PalitoPlumas"] = "Palito con plumas",
  ["Juego:Cajas"] = "Trile de cajas",
  ["Juego:Simon"] = "Simón",
  ["Juego:Laser"] = "Puntero láser",
  ["Juego:Cepillar"] = "Cepillarla",
  ["Juego"] = "Juego",
}

function M.minigame_label(_s, action)
  local a = tostring(action or "")
  local label = LABELS[a]
  if label ~= nil then return label end
  if a ~= "" then return a end
  return "Acción"
end

-- forward declarations (the Python defines these further down)
local in_intro, end_intro, game_finish, turn_press, feather_turn

function M.enter_action_minigame(s, now_ms, action)
  local profile = s:_minigame_profile(action)
  local rt = runtime(s)
  clear(rt)
  s.mode = "action_minigame"
  s.minigame_action = tostring(action)
  s.minigame_speed = math.max(s.MINIGAME_SPEED_MIN, math.min(s.MINIGAME_SPEED_MAX, profile.speed + 0.0))
  s.minigame_target_half = math.max(7.0, math.min(18.0, profile.half + 0.0))
  s.minigame_dir = math.random() < 0.5 and 1 or -1
  s.minigame_cursor = util.uniform(8.0, 92.0)
  s.minigame_target_center = math.max(20.0, math.min(80.0, profile.target + util.uniform(-4.0, 4.0)))

  if action == "Juego:QuitaNudos" then
    -- the owner's knot game (game_knots): turn by turn, so no deadline
    if s.energy <= 10 then
      s:exit_action_minigame(now_ms, "Me quedé sin pilas")
      return
    end
    game_knots.start(rt, util.int(s.knot_level))
    rt.touched = true                     -- the idle deadline starts on the next frame
  elseif M.TURN_ACTIONS[action] ~= nil then
    if s.energy <= 10 then
      s:exit_action_minigame(now_ms, "Me quedé sin pilas")
      return
    end
    local kind = M.TURN_ACTIONS[action]
    M.TURN_GAMES[kind].start(rt, util.int(s[kind .. "_level"]), now_ms)
    rt.touched = true
  elseif action == "Juego:PalitoPlumas" then
    -- the owner's turn-based feather game (game_feather): no clock, so no deadline
    if s.energy <= 10 then
      s:exit_action_minigame(now_ms, "Me quedé sin pilas")
      return
    end
    game_feather.start(rt, util.int(s.feather_level))
    rt.touched = true                     -- the idle deadline starts on the next frame
  else
    rt.kind = "timing"
    set_deadline_ms(s, now_ms + 4200)
  end

  s._minigame_last_ms = now_ms
  if util.contains(M.BOARD_KINDS, rt.kind) then   -- its intro first (the owner, 2026-10-08)
    rt.intro_until = now_ms + M.GAME_INTRO_MS
  end
  s.overlay_text = nil
  s.overlay_until = 0
  s:_log_event("Minijuego: " .. tostring(action))
  s:mark_dirty()
end

function M.exit_action_minigame(s, now_ms, msg)
  s.mode = "main"
  s.minigame_action = nil
  local rt = runtime(s)
  clear(rt)
  set_deadline_ms(s, 0)
  if msg ~= nil and msg ~= "" then
    s.overlay_text = msg
    s.overlay_until = now_ms + 900
  else
    s.overlay_text = nil
    s.overlay_until = 0
  end
  s:mark_dirty()
end

local function action_or_game(s) -- str(state.minigame_action or "Juego")
  local a = s.minigame_action
  if a == nil or a == "" then return "Juego" end
  return tostring(a)
end

local function same_sung(sung, phase_at, step) -- rt["sung"] == (phase_at, step)
  return type(sung) == "table" and sung[1] == phase_at and sung[2] == step
end

function M.update_minigame(s, now_ms)
  if s.mode ~= "action_minigame" then
    return
  end
  if s._minigame_last_ms <= 0 then
    s._minigame_last_ms = now_ms
    return
  end

  local rt = runtime(s)
  local touched = rt.touched
  rt.touched = nil
  if touched then     -- a press in a turn-based game: the idle clock restarts
    set_deadline_ms(s, now_ms + M.GAME_IDLE_MS)
  end
  local deadline = deadline_ms(s, 0)
  -- far ahead of now: the frame tick wrapped, the time is up too
  if deadline > 0 and (now_ms >= deadline or deadline - now_ms > M.GAME_IDLE_MS) then
    s:_register_interaction(action_or_game(s), false)
    s:exit_action_minigame(now_ms, "¿Hola? Me aburrí")
    return
  end
  if in_intro(s, rt, now_ms) then
    return                           -- its intro on screen: what runs on time waits for it
  end

  local kind = tostring(util.get(rt, "kind", "timing"))
  if M.TURN_GAMES[kind] ~= nil then
    local game = M.TURN_GAMES[kind]
    game.tick(rt, now_ms)
    if kind == "simon" then                    -- a note for each colour she shows
      local lit, step = game.lit(rt, now_ms), (now_ms - rt.phase_at) // game.step_ms(rt)
      if lit ~= nil and not same_sung(rt.sung, rt.phase_at, step) then
        rt.sung = {rt.phase_at, step}
        s:_emit_sound(string.format("simon_%d", lit))
      end
    end
    if game.over(rt, now_ms) then
      game_finish(s, now_ms, game.won(rt), kind)
    end
    return
  end
  if kind == "knots" then
    if game_knots.over(rt, now_ms) then        -- the result has shown: the game ends
      game_finish(s, now_ms, rt.result == "free", "knot")
    end
    return
  end
  if kind == "feather_path" then   -- turn-based: nothing moves between presses
    if game_feather.over(rt, now_ms) then      -- her last jump has shown: the game ends
      game_finish(s, now_ms, game_feather.outcome(rt) == "win", "feather")
    end
    return
  end

  local dt_ms = math.max(0, now_ms - s._minigame_last_ms)
  s._minigame_last_ms = now_ms
  local step = (s.minigame_speed + 0.0) * (dt_ms / 1000.0)
  s.minigame_cursor = s.minigame_cursor + s.minigame_dir * step

  if s.minigame_cursor >= 100.0 then
    s.minigame_cursor = 100.0
    s.minigame_dir = -1
  elseif s.minigame_cursor <= 0.0 then
    s.minigame_cursor = 0.0
    s.minigame_dir = 1
  end
end

local PLAY_MESSAGES = {
  ["Juego:SiguelaCasa"] = "¡Aquí estoy!",   -- hide and seek, found
  ["Juego:QuitaNudos"] = "¡Adiós, nudos!",
  ["Juego:PalitoPlumas"] = "¡Soy una cazadora!",
  ["Juego:Cajas"] = "¡Me pillaste!",
  ["Juego:Simon"] = "¡Qué buen dúo!",
  ["Juego:Laser"] = "¡Punto rojo cazado!",
  ["Juego:Cepillar"] = "¡Mira qué melena!",
}

function M.minigame_apply(s, now_ms, action, score)
  local success = score > 0.0
  local quality = "floja"
  if score >= 0.75 then quality = "perfecta" elseif score >= 0.35 then quality = "buena" end

  if action:sub(1, 5) == "Juego" then
    if s.energy <= 10 then
      s:_register_interaction("Juego", false)
      s:exit_action_minigame(now_ms, "Me quedé sin pilas")
      return
    end

    if not success then
      s:_register_interaction("Juego", false)
      s:exit_action_minigame(now_ms, "Hoy no me apetece")
      return
    end

    -- v9 §7.2: the same for every game
    s.affection = math.min(100.0, s.affection + 18.0)
    local cost = s.GAME_ENERGY
    if s:_overweight() then cost = s.GAME_ENERGY_HEAVY end
    s.energy = math.max(0.0, s.energy - cost)
    s.stress = s:_clamp_stat(s.stress - 10.0)  -- D-12
    -- playing helps her weight
    s.weight_kg = math.max(1.8, s.weight_kg - 0.010)
    s._play_cd_until_ms = now_ms + util.int(s.PLAY_COOLDOWN_SEC * 1000)
    s:_register_interaction("Juego", success)
    if action == "Juego:Cepillar" then           -- brushing her out cleans her coat a little
      s.dirt = math.max(0.0, s.dirt - M.BRUSH_CLEANS)
    end
    local msg = util.get(PLAY_MESSAGES, action, "¡Qué bien jugamos!")
    s:_log_event("Play " .. quality)
    s:exit_action_minigame(now_ms, msg)
    return
  end

  -- defensive fallback
  s:_register_interaction(action, false)
  s:exit_action_minigame(now_ms, "Eso no sé hacerlo")
end

local KNOT_SOUNDS = {ok = "tira", free = "libre"}

function M.minigame_confirm(s, now_ms)
  local action = tostring(s.minigame_action or "")
  if action == "" then
    s:exit_action_minigame(now_ms, "Vale, otro rato")
    return
  end

  local rt = runtime(s)
  if truthy(rt.intro_until) then
    end_intro(rt, now_ms)                   -- a press ends its intro
  end
  local kind = tostring(util.get(rt, "kind", "timing"))
  local score = 0.0
  if M.TURN_GAMES[kind] ~= nil then
    turn_press(s, now_ms, M.TURN_GAMES[kind].press)
    return
  end
  if kind == "knots" then
    rt.touched = true
    local result = game_knots.pull(rt, now_ms)     -- B: she pulls the end picked
    if result ~= nil then
      s:_emit_sound(util.get(KNOT_SOUNDS, result, "aprieta"))
      s:mark_dirty()
    end
    return
  elseif kind == "feather_path" then
    feather_turn(s, now_ms, 0)          -- B: she stays
    return
  else
    score = s:_minigame_score()
  end
  s:_minigame_apply(now_ms, action, score)
end

-- A, B or C in one of the turn games: its result, heard
turn_press = function(s, now_ms, act)
  local rt = runtime(s)
  rt.touched = true
  local result = act(rt, now_ms)
  if result ~= nil then
    if rt.kind == "simon" and (result == "ok" or result == "round" or result == "won") then
      s:_emit_sound(string.format("simon_%d", rt.last))           -- the colour you played
    elseif M.TURN_SOUNDS[result] ~= nil then
      s:_emit_sound(M.TURN_SOUNDS[result])
    end
  end
  s:mark_dirty()
end

feather_turn = function(s, now_ms, move)
  local rt = runtime(s)
  rt.touched = true
  if rt.end_at ~= 0 then
    return                       -- her last jump is showing
  end
  local result = game_feather.turn(rt, move)
  if result ~= nil then
    s:_emit_sound(M.TURN_SOUNDS[result])          -- it was silent (the owner, 2026-10-08)
    s.overlay_text = result == "catch" and "¡Mía!" or "¡Se escapó!"
    s.overlay_until = now_ms + 900
    if game_feather.outcome(rt) ~= nil then
      local shows = game_feather.END_MS
      if result == "catch" then shows = game_feather.CATCH_END_MS end
      rt.end_at = now_ms + shows      -- the game ends once it has shown
    else
      rt.round = rt.round + 1
      game_feather.next_feather(rt)
    end
  end
  s:mark_dirty()
end

-- a game's stars (the owner, 2026-10-08, as Tamagotchi Paradise rates its games): won without a miss 3, with one
-- 2, else 1; lost 0
function M.stars_for(won, misses)
  if won then
    return math.max(1, 3 - util.int(misses))
  end
  return 0
end

-- a game's result, for the platform's card (game_result) and her best (memory stars)
function M.record_result(s, game, stars, won)
  s.game_result = {game = game, stars = util.int(stars), won = won and true or false}
  s.game_result_seq = util.int(s.game_result_seq) + 1
  local best = s.memory.stars
  best[game] = math.max(util.int(util.get(best, game, 0)), util.int(stars))
end

-- how many went wrong in a game just over: hearts, feathers or patience lost, rounds empty
local function misses_of(rt, game)
  if game == "feather" then
    return util.int(util.get(rt, "missed", 0))
  end
  if game == "boxes" then
    return util.int(util.get(rt, "round", 0)) - util.int(util.get(rt, "found", 0))
  end
  if game == "brush" then
    return 3 - util.int(util.get(rt, "patience", 3))
  end
  return 3 - util.int(util.get(rt, "hearts", 3))
end

-- the level follows the owner: up after three wins in a row, down after two losses
game_finish = function(s, now_ms, won, game)
  local misses = misses_of(runtime(s), game)
  local level, streak = util.int(s[game .. "_level"]), util.int(s[game .. "_streak"])
  if won then streak = math.max(1, streak + 1) else streak = math.min(-1, streak - 1) end
  if streak >= 3 and level < M.LEVELS - 1 then
    level, streak = level + 1, 0
  elseif streak <= -2 and level > 0 then
    level, streak = level - 1, 0
  end
  s[game .. "_level"] = level
  s[game .. "_streak"] = streak
  local action, lost = GAMES[game][1], GAMES[game][2]
  if won then
    s:_minigame_apply(now_ms, action, 1.0)
  else
    s:_register_interaction("Juego", false)
    s:exit_action_minigame(now_ms, lost)
  end
  M.record_result(s, M.GAME_NAMES[action], M.stars_for(won, misses), won)
  -- its end heard, and seen: she celebrates a win, sulks over a loss (the owner, 2026-10-08)
  s:_emit_sound(won and "gana" or "pierde")
end

-- a game opens to a short intro, how it is played shown without words (the owner, 2026-10-08): its first show (the
-- Trile's, Simón's) waits for it; a press ends it early. Ended, what runs on time starts from now.
in_intro = function(s, rt, now_ms)
  local until_ms = util.int(util.get(rt, "intro_until", 0))
  if until_ms == 0 then
    return false
  end
  if now_ms < until_ms and until_ms - now_ms <= M.GAME_INTRO_MS then   -- far ahead: the tick wrapped
    return true
  end
  end_intro(rt, now_ms)
  return false
end

end_intro = function(rt, now_ms)
  rt.intro_until = 0
  if rt.phase_at ~= nil then
    rt.phase_at = now_ms
  end
end

local function board_view(s)
  local rt = runtime(s)
  if s.mode == "action_minigame" and rt.kind == "feather_path" then
    return game_feather.view(rt)
  end
  if s.mode == "action_minigame" and rt.kind == "knots" then
    return game_knots.view(rt)
  end
  if s.mode == "action_minigame" and (rt.kind == "simon" or rt.kind == "laser") then
    return M.TURN_GAMES[rt.kind].view(rt, util.int(s._frame_ms))
  end
  if s.mode == "action_minigame" and rt.kind ~= nil and M.TURN_GAMES[rt.kind] ~= nil then
    return M.TURN_GAMES[rt.kind].view(rt)
  end
  return {}
end

-- the board of a game that has one, for the snapshot, with whether its intro shows; empty otherwise
function M.game_view(s)
  local view = board_view(s)
  if next(view) ~= nil then
    view.intro = truthy(runtime(s).intro_until)
    if view.intro and view.lit ~= nil then
      view.lit = nil                   -- Simón's run waits for it, the LED's too
    end
  end
  return view
end

function M.minigame_left(s, now_ms)
  if s.mode ~= "action_minigame" then
    return
  end
  local rt = runtime(s)
  if truthy(rt.intro_until) then
    end_intro(rt, now_ms)                   -- a press ends its intro
  end
  if rt.kind ~= nil and M.TURN_GAMES[rt.kind] ~= nil then
    turn_press(s, now_ms, M.TURN_GAMES[rt.kind].left)
  elseif rt.kind == "feather_path" then
    feather_turn(s, now_ms, -1)         -- A: a step left
  elseif rt.kind == "knots" then
    rt.touched = true
    game_knots.move(rt, -1)                  -- A: the end to the left
    s:mark_dirty()
  end
end

function M.minigame_right(s, now_ms)
  if s.mode ~= "action_minigame" then
    return
  end
  local rt = runtime(s)
  if truthy(rt.intro_until) then
    end_intro(rt, now_ms)                   -- a press ends its intro
  end
  if rt.kind ~= nil and M.TURN_GAMES[rt.kind] ~= nil then
    turn_press(s, now_ms, M.TURN_GAMES[rt.kind].right)
  elseif rt.kind == "feather_path" then
    feather_turn(s, now_ms, 1)          -- C: a step right
  elseif rt.kind == "knots" then
    rt.touched = true
    game_knots.move(rt, 1)                   -- C: the end to the right
    s:mark_dirty()
  end
end

return M
