-- tests of group D: the minigames' rules (core/minigames.lua and core/game_*.lua), ports of the asserts in
-- tests/test_rules_v11.py (PlayRewardTest, KnotGameTest, FeatherGameTest, TurnGamesTest, IntroTest, GameStarsTest)
-- plus each game played to a win and to a loss through the minigames API with seeded random.
local util = require("core.util")
local rules = require("core.rules")
local mg = require("core.minigames")
local feather = require("core.game_feather")
local knots = require("core.game_knots")
local boxes = require("core.game_boxes")
local simon = require("core.game_simon")
local laser = require("core.game_laser")
local brush = require("core.game_brush")

for _, m in ipairs({feather, knots, boxes, simon, laser, brush}) do assert(m.self_check()) end

-- a fake GameState: only the fields and methods minigames touches -----------------------------------------------
local methods = {}
local STATE_MT = {__index = setmetatable(methods, {__index = rules})}

function methods:_minigame_profile(action) return mg.minigame_profile(self, action) end
function methods:exit_action_minigame(now_ms, msg) mg.exit_action_minigame(self, now_ms, msg) end
function methods:_minigame_apply(now_ms, action, score) mg.minigame_apply(self, now_ms, action, score) end
function methods:_minigame_score() -- state_screens.py
  local dist = math.abs(self.minigame_cursor - self.minigame_target_center)
  if dist <= self.minigame_target_half then
    return math.max(0.0, 1.0 - (dist / math.max(0.01, self.minigame_target_half)))
  end
  return 0.0
end
function methods:_register_interaction(action, ok) self.interactions[#self.interactions + 1] = {action, ok} end
function methods:_emit_sound(name) self.sound = name; self.sound_seq = self.sound_seq + 1 end
function methods:_log_event(txt) self.last_events[#self.last_events + 1] = txt end
function methods:mark_dirty() self._dirty = true end
function methods:_overweight() return self.weight_kg > self.IDEAL_WEIGHT_RANGES[self.phase][2] end
function methods:_clamp_stat(v, lo, hi) return util.clamp(v, lo or 0.0, hi or 100.0) end

local function pet(over)
  local s = {
    mode = "main", phase = "Adulto", energy = 80.0, affection = 50.0, stress = 50.0, weight_kg = 5.0, dirt = 50.0,
    minigame_cursor = 0.0, minigame_dir = 1, minigame_speed = 60.0, minigame_target_center = 50.0,
    minigame_target_half = 12.0, _minigame_last_ms = 0, overlay_until = 0, _play_cd_until_ms = 0,
    game_result_seq = 0, memory = {stars = {}}, _frame_ms = 0, sound_seq = 0, last_events = {}, interactions = {},
    feather_level = 0, feather_streak = 0, knot_level = 0, knot_streak = 0,
  }
  for _, g in ipairs({"boxes", "simon", "laser", "brush"}) do s[g .. "_level"], s[g .. "_streak"] = 0, 0 end
  for k, v in pairs(over or {}) do s[k] = v end
  return setmetatable(s, STATE_MT)
end

-- GameState's entry points, as state.py / actions.py / navigation.py / simulation.py call them
local function open(s, action, now) mg.enter_action_minigame(s, now or 1000, action) end
local function B(s, now) mg.minigame_confirm(s, now) end
local function A(s) mg.minigame_left(s, s._frame_ms) end
local function C(s) mg.minigame_right(s, s._frame_ms) end
local function update(s, now)
  s._frame_ms = now
  if s.mode == "action_minigame" then mg.update_minigame(s, now) end
end
local function rt_of(s) return s._minigame_runtime end
local function view(s) return mg.game_view(s) end
-- TurnGamesTest._start: the game open, its intro skipped
local function start(s, action, now)
  now = now or 1000
  open(s, action, now)
  rt_of(s).intro_until = 0
  update(s, now)
  return view(s)
end

math.randomseed(1)

-- constants, labels, profile ----------------------------------------------------------------------------------
assert(mg.GAME_IDLE_MS == 120000 and mg.GAME_INTRO_MS == 2500 and mg.BRUSH_CLEANS == 10.0 and mg.LEVELS == 3)
assert(knots.END_MS == 1500 and feather.END_MS == 1500 and feather.CATCH_END_MS == 3300)
assert(feather.CATCH_END_MS > feather.END_MS)
assert(boxes.SHOW_MS == 1500 and boxes.RESULT_MS == 1600 and simon.RESULT_MS == 1300)
assert(laser.RESULT_MS == 1100 and brush.RESULT_MS == 1300)
assert(mg.minigame_label(nil, "Juego:Simon") == "Simón" and mg.minigame_label(nil, nil) == "Acción")
assert(mg.minigame_label(nil, "Juego:Otro") == "Juego:Otro" and mg.minigame_label(nil, "") == "Acción")
assert(mg.minigame_profile(nil, "Juego").speed == 76.0 and mg.minigame_profile(nil, "Juego:Cajas").speed == 62.0)
assert(mg.GAME_NAMES["Juego:QuitaNudos"] == "Quita nudos" and mg.GAME_NAMES["Juego:Laser"] == "Puntero láser")
assert(next(view(pet())) == nil)                                     -- no game: no board

-- the play reward (v9 §7.2), the same for every game ------------------------------------------------------------
for _, game in ipairs({"Juego:SiguelaCasa", "Juego:QuitaNudos", "Juego:PalitoPlumas"}) do
  local s = pet({mode = "action_minigame"})
  s:_minigame_apply(10000, game, 1.0)
  assert(s.affection == 68.0 and s.energy == 70.0 and s.stress == 40.0, game)
  assert(s.mode == "main" and s._play_cd_until_ms == 12500 and s.overlay_until == 10900)
  assert(s.weight_kg < 5.0 and s.weight_kg > 4.98)
  assert(s.last_events[#s.last_events] == "Play perfecta")
end
do
  local s = pet({mode = "action_minigame"})
  s:_minigame_apply(10000, "Juego:QuitaNudos", 1.0)
  assert(s.overlay_text == "¡Adiós, nudos!")
  s = pet({mode = "action_minigame", weight_kg = 9.5})                 -- overweight: E -15
  s:_minigame_apply(10000, "Juego:QuitaNudos", 1.0)
  assert(s.affection == 68.0 and s.energy == 65.0)
  s = pet({mode = "action_minigame", weight_kg = 1.8})                 -- underweight: as usual
  s:_minigame_apply(10000, "Juego:QuitaNudos", 1.0)
  assert(s.affection == 68.0 and s.energy == 70.0 and s.weight_kg == 1.8)
  s = pet({mode = "action_minigame"})                                  -- brushing takes dirt off
  s:_minigame_apply(10000, "Juego:Cepillar", 0.5)
  assert(s.dirt == 40.0 and s.overlay_text == "¡Mira qué melena!" and s.last_events[#s.last_events] == "Play buena")
  s = pet({mode = "action_minigame"})
  s:_minigame_apply(10000, "Juego:Nuevo", 0.1)
  assert(s.overlay_text == "¡Qué bien jugamos!" and s.last_events[#s.last_events] == "Play floja")
  s = pet({mode = "action_minigame", energy = 10.0})                   -- no energy left
  s:_minigame_apply(10000, "Juego:Cajas", 1.0)
  assert(s.mode == "main" and s.affection == 50.0 and s.overlay_text == "Me quedé sin pilas")
  assert(s.interactions[1][1] == "Juego" and s.interactions[1][2] == false)
  s = pet({mode = "action_minigame"})                                  -- a score of 0: she will not
  s:_minigame_apply(10000, "Juego:Cajas", 0.0)
  assert(s.overlay_text == "Hoy no me apetece" and s.affection == 50.0)
  s = pet({mode = "action_minigame"})
  s:_minigame_apply(10000, "Bailar", 1.0)
  assert(s.overlay_text == "Eso no sé hacerlo" and s.interactions[1][1] == "Bailar")
end

-- the timing game (no board): the cursor bounces, B scores it, the deadline ends it -----------------------------
do
  local s = pet()
  open(s, "Juego", 1000)
  assert(rt_of(s).kind == "timing" and s._minigame_deadline_ms == 5200 and rt_of(s).intro_until == nil)
  assert(s.minigame_speed == 76.0 and s.minigame_target_half == 10.0)
  assert(s.minigame_target_center >= 48.0 and s.minigame_target_center <= 56.0)
  s.minigame_cursor, s.minigame_dir = 50.0, 1
  update(s, 2000)                                    -- 76 a second: off the top, it turns
  assert(s.minigame_cursor == 100.0 and s.minigame_dir == -1)
  s.minigame_cursor = s.minigame_target_center
  B(s, 2100)
  assert(s.mode == "main" and s.affection == 68.0 and s.overlay_text == "¡Qué bien jugamos!")
  s = pet()
  open(s, "Juego", 1000)
  update(s, 5200)
  assert(s.mode == "main" and s.overlay_text == "¿Hola? Me aburrí" and s.interactions[1][1] == "Juego")
  s = pet()                                          -- B with no game: back home
  s.mode = "action_minigame"
  B(s, 1000)
  assert(s.mode == "main" and s.overlay_text == "Vale, otro rato")
end

-- Quita nudos (KnotGameTest) ------------------------------------------------------------------------------------
local function knot_game(level)
  local s = pet({knot_level = level or 0})
  open(s, "Juego:QuitaNudos", 1000)
  return s
end
local function pull(s, right, now)
  local rt = rt_of(s)
  local want = right and rt.good or (rt.good + 1) % 3
  while rt.sel ~= want do
    if want > rt.sel then C(s) else A(s) end
  end
  B(s, now or 2000)
end
local function knot_finish(s, right)
  for n = 0, 2 do pull(s, right, 2000 + n) end
  update(s, 2000 + 3 + knots.END_MS)
end
do
  local s = knot_game()
  local v = view(s)
  assert(s.mode == "action_minigame" and v.intro == true)
  assert(v.kind == "knots" and v.knot == 3 and v.sel == 1 and v.hearts == 3 and v.step == 0 and v.steps == 3)
  A(s); assert(view(s).sel == 0 and view(s).intro == false)       -- a press ends its intro
  A(s); assert(view(s).sel == 0)                                  -- no further than the left end
  C(s); C(s); C(s); assert(view(s).sel == 2)

  s = knot_game()
  pull(s, true)
  v = view(s)
  assert(v.step == 1 and v.knot == 2 and v.hearts == 3 and s.sound == "tira" and v.result == "ok" and v.pulled == v.sel)
  s = knot_game()
  pull(s, false)
  v = view(s)
  assert(v.step == 0 and v.knot == 3 and v.hearts == 2 and s.sound == "aprieta" and v.result == "miss")

  s = knot_game()                                                 -- three good pulls free it
  for n = 0, 2 do pull(s, true, 2000 + n) end
  v = view(s)
  assert(v.knot == 0 and v.result == "free" and s.mode == "action_minigame" and s.sound == "libre")
  A(s); B(s, 2100)                                                -- the result shows: no input
  assert(view(s).result == "free" and view(s).result_seq == 3)
  update(s, 2002 + knots.END_MS - 1)
  assert(s.mode == "action_minigame")
  update(s, 2002 + knots.END_MS)
  assert(s.mode == "main" and s.affection == 68.0 and s.energy == 70.0 and s.stress == 40.0)
  assert(s.overlay_text == "¡Adiós, nudos!" and s.sound == "gana" and s.knot_streak == 1)
  assert(rt_of(s).kind == nil and s._minigame_deadline_ms == 0)    -- the board is gone

  s = knot_game()                                                 -- three misses lose
  knot_finish(s, false)
  assert(s.mode == "main" and s.affection == 50.0 and s.overlay_text == "El nudo ganó... grr" and s.sound == "pierde")
  assert(s.knot_streak == -1)

  for _, case in ipairs({{0, {3, 2, 1}}, {1, {5, 4, 3}}, {2, {6, 4, 2}}}) do   -- the drawings by level
    s = knot_game(case[1])
    local seen = {view(s).knot}
    for n = 0, 1 do
      pull(s, true, 2000 + n)
      seen[#seen + 1] = view(s).knot
    end
    assert(seen[1] == case[2][1] and seen[2] == case[2][2] and seen[3] == case[2][3], case[1])
  end

  s = knot_game()                                                 -- the level follows the results
  for _ = 1, 3 do
    open(s, "Juego:QuitaNudos", 1000)
    knot_finish(s, true)
  end
  assert(s.knot_level == 1 and s.knot_streak == 0)
  for _ = 1, 2 do
    open(s, "Juego:QuitaNudos", 1000)
    knot_finish(s, false)
  end
  assert(s.knot_level == 0 and s.knot_streak == 0)

  s = knot_game()                                                 -- left alone mid-game, it ends
  update(s, 2000)
  C(s)                                                            -- a press keeps it going
  update(s, 2000 + mg.GAME_IDLE_MS - 1000)
  assert(s.mode == "action_minigame")
  update(s, 2000 + 2 * mg.GAME_IDLE_MS)
  assert(s.mode == "main" and s.overlay_text == "¿Hola? Me aburrí")
  assert(s.interactions[1][1] == "Juego:QuitaNudos" and s.interactions[1][2] == false)

  s = pet({energy = 5.0})                                         -- too tired to play
  open(s, "Juego:QuitaNudos", 1000)
  assert(s.mode == "main" and s.overlay_text == "Me quedé sin pilas" and s.overlay_until == 1900)
end

-- Palito con plumas (FeatherGameTest) ---------------------------------------------------------------------------
local function feather_game(level)
  local s = pet({feather_level = level or 0})
  open(s, "Juego:PalitoPlumas", 1000)
  return s
end
local function land_under(s, catch)              -- steer her to where it lands, or to the column next to it
  local rt = rt_of(s)
  for _ = 1, 4 do
    local land = rt.path[#rt.path]
    local want = catch and land or (land + 1) % rt.cols
    if want > rt.cat then C(s) elseif want < rt.cat then A(s) else B(s, 2000) end
  end
end
local function feather_finish(s) update(s, rt_of(s).end_at) end
do
  local s = feather_game()
  local v = view(s)
  assert(s.mode == "action_minigame" and v.kind == "feather" and v.cols == 3 and v.row == 5 and v.hearts == 3)
  assert(v.cat == 1 and v.intro == true and v.goal == 2 and v.round == 1)    -- she starts in the middle

  s = feather_game(1)                                            -- each press is a turn
  local rt = rt_of(s)
  rt.path, rt.cat = {2, 2, 2, 2, 2}, 2
  A(s); assert(rt.cat == 1 and view(s).row == 4)
  B(s, 2000); assert(rt.cat == 1 and view(s).row == 3)
  C(s); assert(rt.cat == 2 and view(s).row == 2)

  s = feather_game(); land_under(s, true)
  v = view(s)
  assert(v.caught == 1 and v.hearts == 3 and v.round == 2 and s.sound == "encontrada" and s.overlay_text == "¡Mía!")
  s = feather_game(); land_under(s, false)
  v = view(s)
  assert(v.caught == 0 and v.hearts == 2 and v.round == 2 and s.sound == "aprieta" and s.overlay_text == "¡Se escapó!")

  s = feather_game()                                             -- two catches win
  land_under(s, true); land_under(s, true)
  v = view(s)
  assert(s.mode == "action_minigame" and v.result == "catch" and v.row == 1)   -- her last jump shows
  local end_at = rt_of(s).end_at
  update(s, end_at - 1)
  assert(s.mode == "action_minigame")
  update(s, end_at)
  assert(s.mode == "main" and s.affection == 68.0 and s.energy == 70.0 and s.stress == 40.0)
  assert(s.game_result.game == "Palito con plumas" and s.game_result.stars == 3 and s.game_result.won == true)

  s = feather_game()                                             -- two misses lose
  land_under(s, false); land_under(s, false)
  rt = rt_of(s)
  local cat, step = rt.cat, rt.step
  A(s); B(s, 2000)                                               -- presses wait while her last jump shows
  assert(rt.cat == cat and rt.step == step and rt.missed == 2)
  feather_finish(s)
  assert(s.mode == "main" and s.affection == 50.0 and s.overlay_text == "Las plumas ganan hoy")
  assert(s.game_result.stars == 0 and s.game_result.won == false)

  for _, case in ipairs({{true, feather.CATCH_END_MS}, {false, feather.END_MS}}) do   -- how long the end shows
    s = feather_game()
    for _ = 1, 2 do
      rt = rt_of(s)
      rt.path, rt.cat = {1, 1, 1, 1, 1}, case[1] and 1 or 0
      for _ = 1, 4 do B(s, 2000) end
    end
    assert(rt_of(s).end_at - 2000 == case[2])
  end

  s = feather_game(1)                                            -- the view says where she landed
  rt = rt_of(s)
  rt.path, rt.cat = {4, 4, 4, 4, 4}, 2
  for _ = 1, 4 do C(s) end
  v = view(s)
  assert(v.result == "catch" and v.landed == 4 and v.cat == 2)   -- next: the middle

  s = feather_game()                                             -- A and C keep to the frame clock
  update(s, 1000)
  for _ = 1, 2 do
    rt = rt_of(s)
    rt.path, rt.cat = {0, 0, 0, 0, 0}, 2
    for _ = 1, 4 do A(s) end
  end
  feather_finish(s)
  assert(s.mode == "main" and s._play_cd_until_ms < 1000 + 2000 + 31000 and s.overlay_until < 1000 + 2000 + 5000)

  local hints = {}                                               -- hints shrink with the level
  for level = 0, 2 do
    s = feather_game(level)
    rt_of(s).path = {0, 1, 2, 1, 0}
    hints[level] = view(s)
  end
  assert(#hints[0].hint == 1 and hints[0].hint[1] == 1 and #hints[1].hint == 1 and hints[1].hint[1] == 1)
  assert(#hints[2].hint == 0 and hints[2].sway == 1 and hints[0].sway == nil)

  for level = 0, 2 do assert(view(feather_game(level)).cols == ({3, 5, 6})[level + 1]) end

  s = feather_game()                                             -- the level follows the results
  for _ = 1, 3 do
    open(s, "Juego:PalitoPlumas", 1000)
    land_under(s, true); land_under(s, true)
    feather_finish(s)
  end
  assert(s.feather_level == 1)
  for _ = 1, 2 do
    open(s, "Juego:PalitoPlumas", 1000)
    land_under(s, false); land_under(s, false)
    feather_finish(s)
  end
  assert(s.feather_level == 0)

  for level = 0, 2 do                                            -- paths stay on the board
    for _ = 1, 200 do
      local path = feather.new_path(level)
      assert(#path == feather.ROWS)
      for _, c in ipairs(path) do assert(c >= 0 and c < feather.COLS[level + 1]) end
    end
  end

  s = pet({energy = 5.0}); open(s, "Juego:PalitoPlumas", 1000)  -- too tired
  assert(s.mode == "main")

  s = feather_game()                                             -- left alone mid-game, it ends
  update(s, 2000)
  update(s, 2000 + 2 * mg.GAME_IDLE_MS)
  assert(s.mode == "main")
end

-- the turn games: Trile, Simón, Láser, Cepillar (TurnGamesTest) ------------------------------------------------
do
  for _, case in ipairs({{"Juego:Cajas", "boxes"}, {"Juego:Simon", "simon"}, {"Juego:Laser", "laser"},
                         {"Juego:Cepillar", "brush"}}) do
    assert(start(pet(), case[1]).kind == case[2], case[2])
  end

  local s = pet()                                                -- boxes: watch the shuffle, then pick
  local g = start(s, "Juego:Cajas")
  assert(g.phase == "show" and g.cat == rt_of(s).cat and g.where == boxes._where(rt_of(s)) and #g.swaps == 3)
  assert(g.swap_ms == 700 and g.rounds == 3 and g.round == 0)
  B(s, 1100)                                                     -- nothing to pick yet
  assert(view(s).phase == "show")
  local t = 1000 + boxes.SHOW_MS + 10
  update(s, t)
  assert(view(s).phase == "shuffle" and view(s).cat == nil and view(s).where == nil)
  t = t + #g.swaps * g.swap_ms + 10
  update(s, t)
  assert(view(s).phase == "pick")
  local rt = rt_of(s)
  rt.sel = boxes._where(rt)
  B(s, t)
  assert(view(s).result == "found" and s.sound == "encontrada" and view(s).where == rt.sel)

  local function turn_pet() return pet({affection = 40.0, energy = 70.0}) end   -- TurnGamesTest._pet
  s = turn_pet()                                                 -- winning boxes is the play reward
  start(s, "Juego:Cajas")
  rt, t = rt_of(s), 1000
  for _ = 1, 2 do
    rt.phase = "pick"
    rt.sel = boxes._where(rt)
    B(s, t)
    t = t + boxes.RESULT_MS + 10
    update(s, t)
    t = t + 10
  end
  assert(s.mode == "main" and s.affection == 58.0 and s.boxes_streak == 1 and s.overlay_text == "¡Me pillaste!")

  for _, case in ipairs({{true, "gana"}, {false, "pierde"}}) do  -- a game ends with a fanfare or a sad fall
    s = pet()
    start(s, "Juego:QuitaNudos")
    rt = rt_of(s)
    for _ = 1, 3 do
      rt.sel = case[1] and rt.good or (rt.good + 1) % 3
      B(s, 2000)
    end
    update(s, 2000 + knots.END_MS + 10)
    assert(s.mode == "main" and s.sound == case[2])
  end

  s = pet()                                                      -- palito: a catch and a miss are heard
  start(s, "Juego:PalitoPlumas")
  rt = rt_of(s)
  rt.path, rt.cat = {1, 1, 1, 1, 1}, 1
  for _ = 1, 4 do B(s, 2000) end
  assert(s.sound == "encontrada")
  rt.path, rt.cat = {0, 0, 0, 0, 0}, 2
  for _ = 1, 4 do B(s, 3000) end
  assert(s.sound == "aprieta")

  rt = {}                                                        -- a new Trile round: in the box she was found in
  boxes.start(rt, 0, 0)
  rt.swaps, rt.cat, rt.phase, rt.sel = {{0, 2}}, 0, "pick", 2
  assert(boxes.press(rt, 5000) == "found")                       -- in box 2 once shuffled
  boxes.tick(rt, 5000 + boxes.RESULT_MS)
  assert(rt.phase == "show" and rt.cat == 2 and #rt.swaps == 3)

  s = pet()                                                      -- Simón shows the run with notes, then listens
  start(s, "Juego:Simon")
  rt = rt_of(s)
  rt.run = {0, 2, 1}
  rt.sung = nil
  local notes = {}
  for ms = 1000, 1000 + 3 * simon.STEP_MS[1] + 50 - 1, 50 do
    local seq = s.sound_seq
    update(s, ms)
    if s.sound_seq ~= seq then notes[#notes + 1] = s.sound end
  end
  assert(#notes == 3 and notes[1] == "simon_0" and notes[2] == "simon_2" and notes[3] == "simon_1")
  assert(view(s).phase == "input" and #view(s).run == 0 and view(s).lit == nil)
  A(s); assert(s.sound == "simon_0")
  C(s); assert(s.sound == "simon_2")
  B(s, 5000)
  assert(view(s).result == "round" and s.sound == "simon_1" and view(s).round == 1)

  s = pet()                                                      -- Simón: a wrong colour costs a heart
  start(s, "Juego:Simon")
  rt = rt_of(s)
  rt.run, rt.phase = {0, 0, 0}, "input"
  B(s, 2000)                                                     -- B is green
  assert(view(s).hearts == 2 and view(s).result == "miss" and s.sound == "aprieta")

  s = turn_pet()                                                 -- láser: a pounce on the dot is a catch
  start(s, "Juego:Laser")
  rt = rt_of(s)
  for _ = 1, 3 do
    rt.aim = rt.dot
    B(s, 2000)
  end
  update(s, 2000 + 2000)
  assert(s.mode == "main" and s.affection == 58.0 and s.overlay_text == "¡Punto rojo cazado!")

  local wrap = 1 << 30                                           -- a game still ends when the frame tick wraps
  rt = {}
  brush.start(rt, 0, wrap - 500)
  rt.knots, rt.sel = {0, 1, 0, 0, 0}, 1
  brush.press(rt, wrap - 500)                                    -- won: ends RESULT_MS later
  assert(not brush.over(rt, wrap - 400))
  assert(brush.over(rt, 2000))                                   -- past the wrap
  rt = {}
  boxes.start(rt, 0, wrap - 500)
  boxes.tick(rt, 100)                                            -- wrapped mid-show: starts over
  assert(rt.phase == "show" and rt.phase_at == 100)
  boxes.tick(rt, 100 + boxes.SHOW_MS)
  assert(rt.phase == "shuffle")

  for seed = 0, 39 do                                            -- the dot never darts under her
    math.randomseed(seed)
    rt = {}
    laser.start(rt, 0, 0)
    rt.aim = (rt.dot + 1) % laser.SPOTS
    assert(laser.press(rt, 0) == "miss")                         -- a miss: the dot moves on
    assert(rt.dot ~= rt.aim and rt.hearts == 2)
  end
  math.randomseed(1)

  rt = {}                                                        -- Simón: the run grows when the next one starts
  simon.start(rt, 0, 0)
  rt.run, rt.phase = {0, 1, 2}, "input"
  for _, colour in ipairs({simon.left, simon.press, simon.right}) do colour(rt, 0) end
  assert(rt.result == "round" and #rt.run == 3)                  -- the result shows the run played
  simon.tick(rt, simon.RESULT_MS)
  assert(rt.phase == "show" and #rt.run == 4)

  s = pet()                                                      -- brushing her out takes dirt off too
  start(s, "Juego:Cepillar")
  rt = rt_of(s)
  rt.knots, rt.sel = {0, 2, 0, 0, 0}, 1
  B(s, 2000)
  assert(s.sound == "tira" and view(s).result == "knot")
  B(s, 2100)
  update(s, 2100 + 2000)
  assert(s.mode == "main" and s.dirt == 40.0)

  s = pet()                                                      -- her belly she keeps to herself
  start(s, "Juego:Cepillar")
  rt = rt_of(s)
  rt.sel = 4                                                     -- barriga
  local real_random = math.random
  math.random = function(a, b) if a == nil then return 0.0 end return real_random(a, b) end
  B(s, 2000)
  math.random = real_random
  assert(view(s).patience == 2 and view(s).result == "swat" and s.sound == "enfado")
  rt.sel, rt.knots = 0, {0, 1, 0, 0, 0}                          -- no knot there: smooth, and silent
  local seq = s.sound_seq
  B(s, 2100)
  assert(view(s).result == "smooth" and s.sound_seq == seq)
  assert(view(s).zones[5] == "barriga" and view(s).knots[2] == 1)
end

-- the intro (IntroTest) -----------------------------------------------------------------------------------------
do
  local s = pet({stress = 0.0, energy = 90.0})
  open(s, "Juego:Cajas", 1000)
  assert(view(s).intro == true)
  update(s, 1000 + mg.GAME_INTRO_MS - 10)
  assert(view(s).phase == "show" and rt_of(s).phase_at == 1000)
  update(s, 1000 + mg.GAME_INTRO_MS + 10)                        -- over: the show starts now
  assert(view(s).intro == false and rt_of(s).phase_at == 1000 + mg.GAME_INTRO_MS + 10)

  s = pet()
  open(s, "Juego:QuitaNudos", 1000)
  update(s, 1100)
  C(s)                                                           -- a press ends it
  assert(view(s).intro == false)

  s = pet()                                                      -- Simón's run waits for it, the LED's too
  open(s, "Juego:Simon", 1000)
  s._frame_ms = 1000
  assert(simon.lit(rt_of(s), 1000) ~= nil and view(s).intro == true and view(s).lit == nil)

  local rt = {}                                                  -- Simón sings quicker round by round
  simon.start(rt, 0, 0)
  local times = {}
  for rnd = 0, 3 do
    rt.round = rnd
    times[#times + 1] = simon.step_ms(rt)
  end
  for i = 2, #times do assert(times[i] <= times[i - 1]) end
  assert(times[#times] < times[1])
  rt.round = 99
  assert(simon.step_ms(rt) == simon.FASTEST_MS)
end

-- stars (GameStarsTest) -----------------------------------------------------------------------------------------
do
  assert(mg.stars_for(true, 0) == 3 and mg.stars_for(true, 1) == 2 and mg.stars_for(true, 2) == 1)
  assert(mg.stars_for(true, 5) == 1 and mg.stars_for(false, 0) == 0)

  local function knots_played(misses, won)
    local s = pet({stress = 0.0, energy = 90.0})
    open(s, "Juego:QuitaNudos", 1000)
    local rt = rt_of(s)
    for _ = 1, misses do
      rt.sel = (rt.good + 1) % 3
      B(s, 2000)
    end
    for _ = 1, (won and 3 or 0) do
      rt.sel = rt.good
      B(s, 2000)
    end
    update(s, 2000 + knots.END_MS + 10)
    return s
  end
  local s = knots_played(0, true)
  assert(s.game_result.game == "Quita nudos" and s.game_result.stars == 3 and s.game_result.won == true)
  assert(s.game_result_seq == 1)
  s = knots_played(3, false)
  assert(s.game_result.stars == 0 and s.game_result.won == false)
  s = knots_played(1, true)
  assert(s.memory.stars["Quita nudos"] == 2)
  mg.record_result(s, "Quita nudos", 1, true)                    -- her best is kept
  assert(s.memory.stars["Quita nudos"] == 2 and s.game_result.stars == 1 and s.game_result_seq == 2)
end

-- the level: up after three wins in a row, down after two losses, kept at the ends ----------------------------
do
  local s = pet({boxes_level = 2, boxes_streak = 2})
  start(s, "Juego:Cajas")
  local rt = rt_of(s)
  rt.found, rt.round, rt.end_at = 2, 2, 5000
  update(s, 5000)
  assert(s.mode == "main" and s.boxes_level == 2 and s.boxes_streak == 3)   -- hard already: the streak goes on
  s = pet({brush_level = 0, brush_streak = 1})
  start(s, "Juego:Cepillar")
  rt = rt_of(s)
  rt.patience, rt.end_at = 0, 5000
  update(s, 5000)
  assert(s.brush_level == 0 and s.brush_streak == -1 and s.overlay_text == "¡Basta de cepillo!")
  assert(s.game_result.game == "Cepillarla" and s.game_result.stars == 0)
end

-- each game played to a win and to a loss through A, B, C and the frame tick (seeded) ---------------------------
local BOTS = {}
function BOTS.knots(s, rt, t, win)
  local want = win and rt.good or (rt.good + 1) % 3
  if rt.sel < want then C(s) elseif rt.sel > want then A(s) else B(s, t) end
end
function BOTS.feather_path(s, rt, t, win)
  if rt.end_at ~= 0 then return end
  local land = rt.path[#rt.path]
  local want = win and land or (land + 1) % rt.cols
  if rt.cat < want then C(s) elseif rt.cat > want then A(s) else B(s, t) end
end
function BOTS.boxes(s, rt, t, win)
  if rt.phase ~= "pick" then return end
  local where = boxes._where(rt)
  local want = win and where or (where + 1) % 3
  if rt.sel < want then C(s) elseif rt.sel > want then A(s) else B(s, t) end
end
function BOTS.simon(s, rt, t, win)
  if rt.phase ~= "input" then return end
  local colour = rt.run[rt.got + 1]
  if not win then colour = (colour + 1) % 3 end
  ({[0] = A, [1] = function(st) B(st, t) end, [2] = C})[colour](s)
end
function BOTS.laser(s, rt, t, win)
  if rt.end_at ~= 0 then return end
  if (rt.aim == rt.dot) == win then B(s, t)                       -- win: pounce on it; lose: pounce off it
  elseif rt.dot < rt.aim then C(s) else A(s) end
end
function BOTS.brush(s, rt, t, win)
  if rt.end_at ~= 0 then return end
  local want = 4                                                  -- lose: her belly till she walks off
  if win then
    for z = 0, 3 do if rt.knots[z + 1] > 0 then want = z break end end
  end
  if rt.sel < want then C(s) elseif rt.sel > want then A(s) else B(s, t) end
end

local PLAYS = {
  {"Juego:QuitaNudos", "knot", "¡Adiós, nudos!"}, {"Juego:PalitoPlumas", "feather", "¡Soy una cazadora!"},
  {"Juego:Cajas", "boxes", "¡Me pillaste!"}, {"Juego:Simon", "simon", "¡Qué buen dúo!"},
  {"Juego:Laser", "laser", "¡Punto rojo cazado!"}, {"Juego:Cepillar", "brush", "¡Mira qué melena!"},
}
local LOST = {knot = "El nudo ganó... grr", feather = "Las plumas ganan hoy", boxes = "¡Ni me viste!",
              simon = "Uy, desafinamos", laser = "Ese punto es muy listo", brush = "¡Basta de cepillo!"}
for _, play in ipairs(PLAYS) do
  local action, game, won_msg = play[1], play[2], play[3]
  for _, win in ipairs({true, false}) do
    math.randomseed(7)
    local s = pet({energy = 90.0})
    open(s, action, 1000)
    local kind, t = rt_of(s).kind, 1000
    while s.mode == "action_minigame" and t < 200000 do
      t = t + 50
      update(s, t)
      if s.mode ~= "action_minigame" then break end
      if not (rt_of(s).intro_until ~= nil and rt_of(s).intro_until ~= 0) then BOTS[kind](s, rt_of(s), t, win) end
    end
    assert(s.mode == "main", action)
    assert(s.game_result.won == win and s.game_result.game == mg.GAME_NAMES[action], action)
    assert(s.sound == (win and "gana" or "pierde"), action)
    assert(s[game .. "_streak"] == (win and 1 or -1), action)
    if win then
      assert(s.affection == 68.0 and s.overlay_text == won_msg and s.game_result.stars >= 1, action)
    else
      assert(s.affection == 50.0 and s.overlay_text == LOST[game] and s.game_result.stars == 0, action)
    end
    assert(t < 60000, action)                                     -- it ended by play, not by the idle clock
  end
end

print("ok d")
