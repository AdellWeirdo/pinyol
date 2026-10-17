-- events: her initiative, the event director (a port of audreygotchi/core/events.py; Character Bible §11-§15,
-- §46-§47).
--
-- Once an awake minute on the main screen the director looks at her and picks what she does on her own, or nothing,
-- the most frequent outcome (the owner's yes, 2026-10-05): something small about half the minutes, something
-- uncommon about every 45-60 awake minutes, rare about once a day, very rare at most once a life. Never the same
-- twice running, the distinctive ones among the last RING of them weigh little, and two of those stay GAP_MIN
-- apart (v11: 20 minutes).
--
-- Small events change nothing but what she looks at. Hours come from the simulated second, so a catch-up keeps the
-- clock's hours. No text narrates what she does (Bible); core names each event as a sound, which the renderer
-- shows and the speaker leaves silent unless it is a call.
local util = require("core.util")
local bird = require("core.bird")
local hearing = require("core.hearing")
local lifecycle = require("core.lifecycle")
local memory = require("core.memory")
local weather = require("core.weather")
local M = {}

-- per awake minute; an uncommon one after the 20-minute gap comes ~32 min later on average, ~52 min apart in all.
-- Rare and very rare are set for the 4-7 h a day she is awake and free (tools/sim_life.py): rare about once a
-- day, very rare once or twice a life. ponytail: feel numbers, tested in EventDirectorTest; tune on the board
M.TIERS = {{"common", 0.47}, {"uncommon", 1 / 32}, {"rare", 1 / 240}, {"very_rare", 1 / 3000}}
M.RING = 8                -- recent_event_history (Bible §15): the last distinctive events
M.RING_WEIGHT = 0.15      -- each time an event is among them, its weight times this
M.GAP_MIN = 20            -- v11: at least 20 minutes between two events that change something
M.LOOK_MS = 6000          -- she looks at something this long: a press then, and she looks at you

M.DAY = {{8, 22}}
-- id: {tier, cooldown in awake minutes, hours it may happen in or nil for any}
M.EVENTS = {
  mira = {"common", 0, nil},                    -- follows something off screen
  escucha = {"common", 0, nil},                 -- hears a sound
  cola = {"common", 0, nil},                    -- her tail at something
  bosteza = {"common", 0, {{7, 11}, {20, 24}}}, -- mornings and evenings
  pasea = {"common", 30, M.DAY},                -- walks to another room
  espera = {"common", 0, nil},                  -- your usual hour: she waits for you (§9.2)
  mira_lluvia = {"common", 0, nil},             -- rain or snow outside: she watches it (§42)
  pide_jugar = {"uncommon", 0, {{9, 21}}},
  capricho = {"uncommon", 0, {{9, 21}}},        -- a whim: she asks for you, needing nothing
  se_esconde = {"uncommon", 0, nil},
  encuentra_objeto = {"uncommon", 0, nil},
  ensucia_habitacion = {"uncommon", 0, {{9, 21}}},
  se_duerme_sola = {"uncommon", 0, {{13, 18}}}, -- tired, a siesta on her own
  acompana = {"uncommon", 0, nil},              -- stays by you, asking for nothing
  juega_juguete = {"uncommon", 0, nil},         -- she plays with her toy (§24)
  pajaro = {"uncommon", 120, {{8, 20}}},        -- a sparrow at the window: she hates birds (core/bird.lua)
  se_revuelca = {"rare", 0, {{10, 18}}},        -- rolls on her back in the sun
  recuerdo = {"rare", 0, nil},                  -- an old memory comes back (§10)
  mira_legado = {"rare", 0, nil},               -- she looks at what earlier lives left (§37)
  mira_estrella = {"rare", 0, {{19, 23}}},      -- an evening with her stars (§27, §29, §53)
  baila = {"very_rare", 0, {{10, 20}}},         -- a little dance, never seen before
  -- secrets (Bible §54), never mentioned anywhere: once a life each
  ritual = {"very_rare", 0, nil},               -- a special answer to your routine
  luna = {"very_rare", 0, {{20, 22}}},          -- a night owl gazing at the moon
  herencia = {"very_rare", 0, nil},             -- a tiny gesture of the last Audrey (§37)
}
-- EVENTS' ids in the Python dict's order: pick() walks them in it (a Lua table has no order)
M.EVENT_IDS = {"mira", "escucha", "cola", "bosteza", "pasea", "espera", "mira_lluvia", "pide_jugar", "capricho",
               "se_esconde", "encuentra_objeto", "ensucia_habitacion", "se_duerme_sola", "acompana",
               "juega_juguete", "pajaro", "se_revuelca", "recuerdo", "mira_legado", "mira_estrella", "baila",
               "ritual", "luna", "herencia"}
M.LOW = {"grumpy", "sad", "sleepy", "nervous", "lonely"}
-- Bible §20-§26, the owner's yes: the stages differ by pace and behaviour, not new art yet.
-- stage: {animation pace, the small events' share, leanings by event}. ponytail: feel numbers
M.STAGES = {
  -- a puppy (the owner, 2026-10-06): fewer small events, more naps, no hiding on her own and no past to recall yet
  Cachorro = {1.0, 0.6, {mira = 1.5, escucha = 1.5, se_duerme_sola = 3.0, acompana = 1.5,
                         se_esconde = 0.0, recuerdo = 0.0, mira_legado = 0.0, mira_estrella = 0.0,
                         ritual = 0.0, herencia = 0.0, baila = 0.0}},
  Juvenil = {1.05, 1.0, {se_esconde = 1.5, ensucia_habitacion = 1.5, pide_jugar = 1.5, pasea = 1.3}},
  Adulto = {1.0, 1.0, {}},
  Senior = {0.85, 0.85, {recuerdo = 2.0, acompana = 1.5, se_duerme_sola = 1.3, mira = 0.8,
                         ensucia_habitacion = 0.5, pide_jugar = 0.7, pasea = 0.7}},
  Extra = {0.8, 0.7, {recuerdo = 3.0, acompana = 2.0, ensucia_habitacion = 0.2, pide_jugar = 0.5,
                      se_esconde = 0.5, pasea = 0.5}},
}

local WET = {"rain", "snow", "storm"}
local MERRY = {"happy", "excited", "playful"}
local STORM = {se_esconde = 2.0, pasea = 0.6}

function M.stage(s)
  return util.get(M.STAGES, tostring(s.phase), M.STAGES.Adulto)
end

M.LATER_MAX = 4           -- things she will do a moment later, at most this many waiting

-- She does `sound` at frame tick `at_ms` (a comeback, an answer, a hello); update() plays what is due, one a
-- frame, if she is there to be seen.
function M.later(s, at_ms, sound)
  if #s._later < M.LATER_MAX then
    local l = util.copy(s._later)
    l[#l + 1] = {util.int(at_ms), sound}
    s._later = l
  end
end

function M.hour(s)
  local ts = util.get(s, "_sim_ts", 0)
  local localtime = s.clock.localtime
  if ts ~= 0 and localtime ~= nil then
    return util.int(s.clock:localtime(ts).tm_hour)
  end
  return util.int(s.clock:local_hour())
end

local function _in_hours(windows, h)
  if windows == nil then return true end
  for _, w in ipairs(windows) do
    if w[1] <= h and h < w[2] then return true end
  end
  return false
end

-- The weather leans her too (Bible §42): a storm sends her into hiding and keeps her in, warm sun she lies in,
-- cold and heat make her nap.
local function _outside(s, ev)
  local w = weather.kind(s)
  if w == "storm" then
    return util.get(STORM, ev, 1.0)
  end
  if ev == "se_revuelca" and weather.sunny(s) then
    return 3.0
  end
  if ev == "se_duerme_sola" and (weather.cold(s) or weather.hot(s)) then
    return 1.5
  end
  return 1.0
end

-- How much she leans to `ev` now; 0 when it cannot happen. The hour leans, never rules (Bible §42): curious
-- mornings, play and walks in the afternoon, quiet evenings.
function M._lean(s, ev, h)
  local mood, e = s.mood, s.energy
  local morning, afternoon, evening = 7 <= h and h < 12, 15 <= h and h < 20, h >= 20 or h < 7
  local low = util.contains(M.LOW, mood)
  if ev == "mira" then
    return (0.5 + s:_pf("curiosity")) * (morning and 1.5 or (evening and 0.7 or 1.0))
  end
  if ev == "escucha" then
    return 0.7 * (evening and 1.5 or 1.0)
  end
  if ev == "cola" then
    return 0.7
  end
  if ev == "pajaro" then  -- by day, dry, at a window of the room she is in
    if weather.dark(s) or util.contains(WET, weather.kind(s)) or not bird.window_here(s) then
      return 0.0
    end
    return morning and 1.5 or 1.0
  end
  if ev == "bosteza" then
    return 1.0 + (e < 40 and 1.0 or 0.0)
  end
  if ev == "pasea" then
    if e < 30 or #s.scenarios <= 1 then
      return 0.0
    end
    local walk = 0.5 + s:_pf("curiosity") + 0.5 * (1.0 - s:_pf("sociability")) + (s.stress > 70 and 0.5 or 0.0)
    return walk * (afternoon and 1.5 or 1.0)
  end
  if ev == "pide_jugar" then
    if e < 40 or s.wants_play or low then
      return 0.0
    end
    return (0.5 + s:_pf("activity")) * (afternoon and 1.5 or 1.0)
  end
  if ev == "capricho" then     -- owner, 2026-10-06: only when she needs nothing, two a day
    local day = s.memory.day
    if (math.min(s.hunger, s.affection, e) < 60 or s.health < 80 or s.dirt > 40
        or low or day.whim_yes + day.whim_no >= 2) then
      return 0.0
    end
    return 0.5 + s:_pf("pampered")         -- a spoilt cat asks more
  end
  if ev == "se_esconde" then
    if not s:_may_hide(s._frame_ms) then
      return 0.0               -- just out of hiding
    end
    return 1.0 + (util.contains(s.quirks, "Huidiza") and 2.0 or 0.0) + (mood == "nervous" and 1.5 or 0.0)
  end
  if ev == "encuentra_objeto" then
    return 0.5 + s:_pf("curiosity")
  end
  if ev == "ensucia_habitacion" then
    if s.dirt > 80 then return 0.0 end
    return 0.5 + 0.5 * (1.0 - s:_pf("sociability"))
  end
  if ev == "se_duerme_sola" then
    return e < 30 and 2.0 or 0.0
  end
  if ev == "acompana" then
    if low or s.affection < 70 then return 0.0 end
    return 0.5 + s:_pf("affection")
  end
  if ev == "juega_juguete" then
    local toy = s.memory.toy
    if toy == nil or toy == "" or e < 30 then return 0.0 end
    return 0.5 + 0.5 * s:_pf("activity")
  end
  if ev == "mira_lluvia" then  -- she watches outside: rain or snow, or the sun going down
    return (util.contains(WET, weather.kind(s)) or weather.dusk(s)) and 2.0 or 0.0
  end
  if ev == "espera" then
    local usual = memory.habit_hour(s)
    return (usual ~= nil and (h == usual or h == (usual - 1) % 24)) and 1.0 or 0.0
  end
  if ev == "recuerdo" then
    if #memory.old_memories(s) == 0 then
      return 0.0
    end
    return util.int(s.farewell_scheduled_day) > 0 and 3.0 or 1.0   -- more near the end (§29)
  end
  if ev == "se_revuelca" then
    return (low or s.affection < 50) and 0.0 or 1.0
  end
  if ev == "mira_legado" then  -- in the living room, where their objects stand; a star draws her
    local earlier = {}
    for _, x in ipairs(s.legacy) do
      if util.int(util.get(x, "cycle", 0)) < util.int(s.cycle) then earlier[#earlier + 1] = x end
    end
    local files = s.BG_FILES
    local file = tostring(files[util.int(s.current_scene) % #files + 1])
    local here = file:sub(1, #"bg_living") == "bg_living"
    if not (#earlier > 0 and here) then
      return 0.0
    end
    for _, x in ipairs(earlier) do
      if x.item == "estrella" then return 2.0 end
    end
    return 1.0
  end
  if ev == "mira_estrella" then  -- once there is a star; she looks at the sky more near the end
    if util.int(s.stars) == 0 then
      return 0.0
    end
    return util.int(s.farewell_scheduled_day) > 0 and 3.0 or 1.0
  end
  if ev == "herencia" then
    local gesture = lifecycle.heirloom(s)
    return (gesture ~= nil and gesture ~= "") and 1.0 or 0.0
  end
  if ev == "ritual" then         -- your usual hour, and you were just with her
    local recent = s.clock:now() - s.last_input_ts < 600   -- (Python's float(): kept integer, 32-bit floats)
    return (recent and memory.habit_hour(s) == h) and 1.0 or 0.0
  end
  if ev == "luna" then
    return (s:_pf("rhythm") >= 0.65 and 20 <= h and h < 22) and 1.0 or 0.0
  end
  if ev == "baila" then
    return (util.contains(MERRY, mood) and e >= 60) and 1.0 or 0.0
  end
  return 0.0
end

function M._weight(s, ev, h)
  h = h or 12
  return M._lean(s, ev, h) * util.get(M.stage(s)[3], ev, 1.0) * _outside(s, ev)
end

M.HOLIDAY_F = 10.0

-- A holiday's moment, once a life (owner, 2026-10-06), when you give her its food or rose (2026-10-07): F +10,
-- kept as a first she dreams of, and may recall.
function M.celebrate(s, day, now_ms)
  if day == nil or day == "" or s.memory.first[day] ~= nil then
    return
  end
  memory.first(s, day)
  s.affection = math.min(100.0, s.affection + M.HOLIDAY_F)
  s:_emit_sound("fiesta")
  s:_log_event("Fiesta: " .. day)
  s:mark_dirty()
end

M.PETARD_P = 1 / 30        -- a petard an awake minute: about six on the night. ponytail: feel number

-- Awake on the main screen, well, home (not with Sancho) and not waiting on her cushion for someone to play
-- with her.
function M.able(s)
  return s.mode == "main" and not (s.sleeping or s.deep_sleep or s.powered_off
          or s.hidden or s.sick or s.in_critical or util.int(s.sitter_until) ~= 0
          or s.wants_play or s._away)
end

-- Sant Joan's eve (owner, 2026-10-07): from 21:00 to midnight on 23 June, now and then a petard frightens her as
-- a loud noise does (core/hearing.lua).
function M.revetlla(s, now_ms)
  if not M.able(s) then                -- first: cheap, and false all through a catch-up away
    return
  end
  local ts = util.get(s, "_sim_ts", 0)
  if ts == 0 then ts = nil end
  local d = weather._date(s, ts)
  if d == nil or d[2] ~= 6 or d[3] ~= 23 or M.hour(s) < 21 then
    return
  end
  if math.random() < M.PETARD_P then
    hearing.fright(s, now_ms)
    s:_log_event("Un petardo")
  end
end

local function count(list, v)
  local n = 0
  for _, x in ipairs(list) do if x == v then n = n + 1 end end
  return n
end

-- The event for this minute, or nil; changes nothing.
function M.pick(s)
  local r, tier, quiet = math.random(), nil, M.stage(s)[2]
  for _, t in ipairs(M.TIERS) do
    local name, p = t[1], t[2]
    if name == "common" then p = p * quiet end
    if r < p then
      tier = name
      break
    end
    r = r - p
  end
  if tier == nil then
    return nil
  end
  local minute, h = s._ev_min, M.hour(s)
  if tier ~= "common" and minute - s._ev_last_big < M.GAP_MIN then
    return nil
  end
  local ring = s._ev_ring
  local options = {}
  for _, ev in ipairs(M.EVENT_IDS) do
    local spec = M.EVENTS[ev]
    local t, windows = spec[1], spec[3]
    local skip = t ~= tier or ev == s._ev_prev or (#ring > 0 and ring[#ring] == ev) or not _in_hours(windows, h)
    if not skip then
      skip = minute < util.get(s._ev_ready, ev, 0) or (t == "very_rare" and util.contains(s.events_once, ev))
    end
    if not skip then
      local w = M._weight(s, ev, h) * M.RING_WEIGHT ^ count(ring, ev)
      if w > 0 then
        options[#options + 1] = {ev, w}
      end
    end
  end
  if #options == 0 then
    return nil
  end
  local total = 0
  for _, o in ipairs(options) do total = total + o[2] end
  r = math.random() * total
  for _, o in ipairs(options) do
    r = r - o[2]
    if r < 0 then
      return o[1]
    end
  end
  return options[#options][1]
end

-- Once an awake minute: what she does on her own, if anything.
function M.direct(s, now_ms)
  if not M.able(s) then
    return nil
  end
  s._ev_min = s._ev_min + 1
  local ev = M.pick(s)
  if ev ~= nil then
    M.happen(s, ev, now_ms)
  end
  return ev
end

function M.happen(s, ev, now_ms)
  local spec = M.EVENTS[ev]
  local tier, cooldown = spec[1], spec[2]
  s._ev_prev = ev
  if cooldown ~= 0 then
    s._ev_ready[ev] = s._ev_min + cooldown
  end
  if tier ~= "common" then
    local ring = util.copy(s._ev_ring)
    ring[#ring + 1] = ev
    s._ev_ring = util.slice(ring, -M.RING)
    s._ev_last_big = s._ev_min
  end
  if tier == "very_rare" then
    local once = util.copy(s.events_once)
    once[#once + 1] = ev
    s.events_once = once
    s:mark_dirty()
  end
  if ev == "mira" then
    s._looking_until = util.int(now_ms) + M.LOOK_MS
  end
  if ev == "mira_estrella" then
    memory.first(s, "stars")      -- her first evening with the stars (§53)
  end
  if ev == "pasea" then
    local fav = memory.fav_room(s)
    if fav ~= nil and fav ~= util.int(s.current_scene) and math.random() < 0.5 then
      s.current_scene = fav                    -- her room (Bible §7)
    else
      local direction = math.random() < 0.62 and 1 or -1
      s.current_scene = (util.int(s.current_scene) + direction) % #s.scenarios
    end
    s:mark_dirty()
  elseif ev == "pide_jugar" then
    s.wants_play = true      -- she waits for it, until any button attends to her
    local fav = memory.fav_game(s)
    if fav ~= nil and util.contains(s.PLAY_OPTIONS, fav) then
      s.play_choice = util.index(s.PLAY_OPTIONS, fav)   -- she asks for her favourite (0-based)
    end
    s.excitement = s:_clamp_stat(s.excitement + 3.0)
    s:mark_dirty()
  elseif ev == "capricho" then
    local asks = require("core.asks")      -- here: asks reads the director's hour
    asks.start(s, "whim", asks.WHIM_WAIT_SEC)
  elseif ev == "se_esconde" then
    s:_hide(now_ms)          -- emits its own sound
    s:_log_event("Se esconde")
    return
  elseif ev == "se_duerme_sola" then
    s:enter_sleep(now_ms, "siesta", false)
    s.light_on = true        -- a nap where she is: nobody turned the light off
  elseif ev == "encuentra_objeto" then
    s.memory.day.found = s.memory.day.found + 1    -- what she finds makes her curious (Bible §5.1)
    memory.first(s, "object")
    local toy = s.memory.toy
    if toy == nil or toy == "" then      -- the first find is her toy
      memory.keep_toy(s, util.choice(memory.TOYS))
    end
  elseif ev == "ensucia_habitacion" then
    s.dirt = math.min(100.0, s.dirt + 7.0)
    s:mark_dirty()
  elseif ev == "pajaro" then
    bird.land(s, now_ms)
  end
  s:_emit_sound(ev)
end

return M
