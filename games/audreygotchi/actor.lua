-- actor: Audrey on the screen, as the board's renderer drew her (platforms/esp32s3/renderer.py _draw_audrey and
-- _oneshot_for): her resting set from the snapshot (anim.sprite_set); a one-off over it when the core names a sound
-- (anim.reaction_set), or now and then a gesture; frames held by anim.HOLD, poses kept by anim.LINGER. Time runs in
-- animation ticks (~270 ms at rest, slower asleep).
local anim = require("anim")
local M = {}

local A = {tick = 0, ms = 0, oneshot = nil, oneshot_at = 0, oneshot_end = 0, reacting = false, queue = {},
           gesture_next = 0, was_wanted = nil, was_hiding = false, seen_seq = nil, shown = "idle", frame = 0,
           sparkles_until = 0, toy_until = 0, moon_until = 0, hearts_from = nil, dance = nil, last_game = nil}
M.state = A

local CUDDLED = {mimos = true, enamorada = true, rueda = true, derretida = true, cachorro_mimos = true,
                 cachorro_enamorada = true, cachorro_acompana = true}
local DANCES = {baila = {0, 1, 2, 1, 2, 3, 0, 4, 5, 6, 7, 8, 7, 8, 3, 9}, cachorro_baila = {0, 1, 2, 1, 2, 3, 0, 4}}
local DANCE_STEP_TICKS = 2 -- ~450 ms a step: her own tempo (the board followed the microphone's beat)

local function frames_of(set) local _, _, n = imgsize("A_" .. set:upper()) return n or 1 end
local function has(set) return anim.has(set) end

local function start_oneshot(name, reacting)
  A.oneshot, A.oneshot_at, A.reacting = name, A.tick, reacting
  A.oneshot_end = A.tick + frames_of(name) * (anim.REPEAT[name] or 1) * (anim.HOLD[name] or 1) + (anim.LINGER[name] or 0)
end

local function anim_ms(ui)
  local state = "idle"
  if ui.sleeping or ui.deep_sleep then state = "dormir"
  elseif ui.sick or ui.in_critical then state = "enferma" end
  local pace = tonumber(ui.anim_pace) or 1.0
  return math.floor(anim.ANIM_MS[state] / math.max(0.5, pace))
end

local function on_sound(ui, wanted)
  local sound = ui.sound
  local reaction = anim.reaction_set(sound, ui)
  A.queue = {}
  if sound == "gana" and A.last_game == "Simón" and type(reaction) == "string" and reaction:sub(1, 8) ~= "disfraz_"
      and has("baila") then
    reaction = "baila" -- Audrey dice won: she dances (the owner, 2026-10-08)
  end
  if sound == "crece" or sound == "gana" then A.sparkles_until = A.tick + 30 end
  if sound == "luna" then A.moon_until = A.tick + 30 end
  if sound == "juega_juguete" then A.toy_until = A.tick + 25 end
  if anim.TURNS[wanted] and sound ~= "musica" and type(reaction) ~= "nil" and anim.EVENT_SET_NAMES[sound] then
    reaction = nil -- curled up or on her cushion: no small event gets her up; music does
  end
  if type(reaction) == "table" then
    local rest = {}
    for i = 2, #reaction do rest[#rest + 1] = reaction[i] end
    reaction, A.queue = reaction[1], rest
  end
  if reaction and not has(reaction) then
    if sound == "mimos" and has("mimos") then reaction = "mimos"
    elseif reaction:sub(1, 5) == "come_" and has("come") then reaction = "come"
    else reaction = nil end
    A.queue = {}
  end
  if reaction and DANCES[reaction] then
    if not (A.dance and A.dance.name == reaction) then
      start_oneshot(reaction, true)
      A.oneshot_end = A.tick + #DANCES[reaction] * DANCE_STEP_TICKS * 2
      A.dance = {name = reaction, at = A.tick}
    end
  elseif reaction then
    if reaction == A.oneshot and A.reacting then
      A.oneshot_end = math.max(A.oneshot_end, A.tick + (anim.LINGER[reaction] or 0))
    else
      start_oneshot(reaction, true)
    end
  end
end

local function oneshot_for(ui, wanted)
  local rule = anim.gestures(wanted)
  local hidden = wanted == "hidden"
  if hidden ~= A.was_hiding then -- into or out of hiding: what was playing stops
    A.was_hiding, A.was_wanted = hidden, wanted
    A.oneshot, A.reacting, A.queue = nil, false, {}
    if rule then A.gesture_next = A.tick + math.random(rule[2], rule[3]) end
  end
  local seq = ui.sound_seq or 0
  if A.seen_seq == nil then A.seen_seq = seq end -- nothing that happened before the first frame
  if seq ~= A.seen_seq then
    A.seen_seq = seq
    on_sound(ui, wanted)
  end
  if A.was_wanted == nil then A.was_wanted = wanted end
  if wanted ~= A.was_wanted then
    local into, out = anim.TURNS[wanted], anim.TURNS[A.was_wanted]
    local turn = (into and into[1]) or (out and out[2])
    A.was_wanted = wanted
    if turn and has(turn) then start_oneshot(turn, true) end
  end
  if hidden and A.reacting then A.oneshot, A.reacting, A.queue = nil, false, {} end
  if A.oneshot then
    if A.tick < A.oneshot_end and (A.reacting or rule) then return A.oneshot end
    A.oneshot, A.reacting, A.dance = nil, false, nil
    if #A.queue > 0 then
      start_oneshot(table.remove(A.queue, 1), true)
      return A.oneshot
    end
    if rule then A.gesture_next = A.tick + math.random(rule[2], rule[3]) end
  end
  if rule and A.tick >= A.gesture_next then
    local names = {}
    for _, nm in ipairs(rule[1]) do if has(nm) and anim.gesture_ok(nm, ui) then names[#names + 1] = nm end end
    if #names > 0 then start_oneshot(names[math.random(#names)], false) end
    A.gesture_next = A.tick + math.random(rule[2], rule[3])
  end
  return A.oneshot
end

function M.note_game(label) A.last_game = label end

function M.update(ui) -- 60 times a second, with the snapshot
  A.ms = A.ms + 1000 / 60
  local per = anim_ms(ui)
  local wanted = anim.sprite_set(ui)
  local stepped = false
  while A.ms >= per do
    A.ms = A.ms - per
    A.tick = A.tick + 1
    stepped = true
  end
  if not stepped and A.seen_seq == (ui.sound_seq or 0) then return end
  local oneshot = oneshot_for(ui, wanted)
  local name = anim.pick(oneshot or wanted)
  local n = frames_of(name)
  if A.dance and oneshot == A.dance.name then
    local steps = DANCES[oneshot]
    A.frame = steps[((A.tick - A.dance.at) // DANCE_STEP_TICKS) % #steps + 1] % n
  elseif oneshot then
    local step = (A.tick - A.oneshot_at) // (anim.HOLD[oneshot] or 1)
    A.frame = math.min(n * (anim.REPEAT[oneshot] or 1) - 1, step) % n
  else
    local hold = anim.HOLD[name]
    A.frame = (hold and A.tick // hold or A.tick) % n
  end
  A.shown, A.cuddled = name, oneshot ~= nil and CUDDLED[oneshot] and A.reacting
end

local K = 0.728 * 2 -- the board's screen pixels to this screen's (art.py's S / the board's 0.5, then 2x)
M.K = K

function M.icon(id, cx, cy) -- an icon centred on (cx, cy), at the world's scale
  local w, h = imgsize(id)
  if w then img(id, math.floor(cx - w), math.floor(cy - h), {scale = 2}) end
end

-- her canvas's bottom centre at (cx, floor), screen pixels; returns the drawing's x, y, w, h (screen)
function M.draw(cx, floor)
  local id = "A_" .. A.shown:upper()
  local w, h = imgsize(id)
  if not w then return cx, floor, 0, 0 end
  local x, y = cx - w, floor - h * 2
  img(id, x, y, {frame = A.frame, scale = 2})
  if A.cuddled then -- loved: hearts by her head, one by one (the board's offsets, scaled to this screen)
    local t = A.tick - A.oneshot_at
    for i, d in ipairs({{-42, 46}, {44, 38}, {6, 26}}) do
      if t >= 2 * (i - 1) then M.icon("IC_FX_HEART", cx + d[1] * K, y + d[2] * K) end
    end
  end
  if A.tick < A.sparkles_until then -- a new stage, a game won: sparkles twinkle round her
    for i, d in ipairs({{-58, 30}, {56, 22}, {-36, 2}, {44, 70}, {-62, 80}}) do
      if (A.tick + i) % 3 ~= 0 then M.icon("IC_FX_SPARKLE", cx + d[1] * K, y + d[2] * K) end
    end
  end
  return x, y, w * 2, h * 2
end

function M.toy_playing() return A.tick < A.toy_until end
function M.moon_showing() return A.tick < A.moon_until end
function M.tick() return A.tick end

return M
