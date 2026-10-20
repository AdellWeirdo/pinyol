-- The episode's music and its clock. TEMPORARY AUDIO: a charanga made of the engine's own made sounds and two synth
-- voices (a trumpet and a tuba) on the studio's sequencer, written for the prototype, not the final soundtrack.
-- The clock is studio.pos(): the step the player hears now, the speaker's queue already taken off (docs/lua.md, "The
-- studio"), counted into bars here, so the chart never drifts from the music however slow a frame is.
local M = {}

M.BPM = 112
M.BARS = 28                 -- 28 bars of 4/4 at 112: one minute
M.SEC_PER_BEAT = 60 / M.BPM

local KEY = {C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11}
local function midi(name) -- "Bb4" -> 70
  local l, acc, oct = name:match("^(%a)([b#]?)(%-?%d)$")
  return 12 * (tonumber(oct) + 1) + KEY[l] + (acc == "b" and -1 or acc == "#" and 1 or 0)
end

-- Melodies, eight eighths a bar ("." holds silence); chords give the tuba its root.
local A = {"F4 A4 C5 . C5 D5 C5 A4", "Bb4 . G4 . Bb4 D5 C5 .", "A4 C5 F5 . E5 D5 C5 .", "D5 . Bb4 . G4 A4 Bb4 .",
           "C5 . A4 C5 F5 . E5 F5", "G5 . F5 E5 D5 . C5 .", "Bb4 D5 C5 A4 G4 . E4 .", "F4 . . . F5 . . ."}
local B = {"D5 . . . A4 . . .", "Bb4 . . . A4 . G4 .", "F4 . . . A4 . D5 .", "E5 . . . . . . .",
           "D5 . F5 . E5 . D5 .", "C5 . Bb4 . A4 . G4 .", "A4 . C5 . E5 . G5 .", "C5 C5 C5 C5 C5 . . ."}
local CHORDS_A = {"F2", "Bb1", "F2", "Bb1", "F2", "C2", "C2", "F2"}
local CHORDS_B = {"D2", "Bb1", "F2", "A1", "D2", "C2", "A1", "C2"}

-- The song bar by bar (1-based): what plays in each. Sections: intro 1-4, avance 5-12, duda 13-20, fanfarria 21-28.
local function bar_plan(b)
  if b <= 2 then return {drums = "pulse"} end
  if b <= 4 then return {drums = "march", bass = "F2"} end
  if b <= 12 then return {drums = "march", melody = A[b - 4], bass = CHORDS_A[b - 4]} end
  if b <= 20 then return {drums = "soft", melody = B[b - 12], bass = CHORDS_B[b - 12]} end
  if b <= 27 then return {drums = "roll", melody = A[b - 20], bass = CHORDS_A[b - 20], loud = true} end
  return {drums = "end", melody = "F5 . . . . . . .", bass = "F2"}
end

local DRUMS = { -- bombo, caja, plato: velocities on the 16 steps
  pulse = {{1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0}, {}, {}},
  march = {{1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0.5},
           {0, 0, 0.6, 0, 0, 0, 0.6, 0, 0, 0, 0.6, 0, 0, 0, 0.6, 0}},
  soft = {{0.7, 0, 0, 0, 0, 0, 0, 0, 0.7, 0, 0, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 0.4, 0, 0, 0, 0, 0, 0, 0, 0.4, 0, 0, 0}, {}},
  roll = {{1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0}, {0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0.5, 0.7, 0.9},
          {0.7, 0, 0.7, 0, 0.7, 0, 0.7, 0, 0.7, 0, 0.7, 0, 0.7, 0, 0.7, 0}},
  ["end"] = {{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, {1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
             {1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}},
}

local function melody_steps(line, loud)
  local out, i = {}, 0
  for tok in line:gmatch("%S+") do
    i = i + 1
    out[2 * i - 1] = tok ~= "." and {midi(tok), accent = loud} or 0
    out[2 * i] = 0
  end
  return out
end

local function bass_steps(root)
  local r = midi(root)
  return {r, 0, 0, 0, r + 7, 0, 0, 0, r, 0, 0, 0, r + 7, 0, 0, 0}
end

local function schedule(b, next_bar) -- bar b's patterns, now or from the next bar line
  local p = bar_plan(b)
  local d = DRUMS[p.drums]
  for t = 1, 3 do studio.steps(t, d[t], next_bar) end
  studio.notes(4, p.melody and melody_steps(p.melody, p.loud) or {}, next_bar)
  studio.notes(5, p.bass and bass_steps(p.bass) or {}, next_bar)
end

function M.init() -- the sounds, once
  sound("BOMBO", {wave = "sine", freq = 110, slide = -260, sustain = 0.03, decay = 0.25, punch = 0.4, volume = 0.9})
  sound("CAJA", {wave = "noise", freq = 900, sustain = 0.01, decay = 0.12, highpass = 0.15, volume = 0.5})
  sound("PLATO", {wave = "noise", freq = 2400, sustain = 0.01, decay = 0.3, highpass = 0.5, volume = 0.35})
  sound("GOLPE", {wave = "square", freq = 880, arp = 1.5, arp_time = 0.03, sustain = 0.02, decay = 0.1, volume = 0.45})
  sound("FALLO", {wave = "saw", freq = 180, slide = -200, sustain = 0.02, decay = 0.15, volume = 0.3})
  sound("DING", {wave = "sine", freq = 1320, sustain = 0.05, decay = 0.6, volume = 0.4})
end

function M.start()
  studio.stop()
  studio.tempo(M.BPM, 54)
  studio.length(16)
  studio.track(1, {sound = "BOMBO", gain = 0.9})
  studio.track(2, {sound = "CAJA", gain = 0.6, reverb = 0.15})
  studio.track(3, {sound = "PLATO", gain = 0.35})
  studio.synth(4, {wave = "saw", cutoff = 0.75, res = 0.25, env = 0.35, decay = 0.3, accent = 0.5, volume = 0.45,
                   reverb = 0.2, glide = 0.02})
  studio.synth(5, {wave = "square", cutoff = 0.28, res = 0.1, env = 0.2, decay = 0.15, volume = 0.55})
  studio.fx({reverb = "plate", size = 0.4, damp = 0.5})
  M.bar, M.last_step, M.done, M.energy = 0, nil, false, 0.5
  schedule(1, false)
  studio.play()
  schedule(2, true)
  sfx("DING", 0.6) -- the lift arrives
end

-- Once a tick: count the bars as the steps come round, and line up the next one.
function M.update()
  if M.done then return end
  local step = studio.pos()
  if not step then return end
  if M.last_step and step < M.last_step then
    M.bar = M.bar + 1
    if M.bar >= M.BARS then
      studio.stop()
      M.done = true
      return
    end
    if M.bar + 2 <= M.BARS then schedule(M.bar + 2, true) end
  end
  M.last_step = step
end

-- The beat the player hears now, from 0 at the song's start (quarter notes); nil before the song or after it.
function M.beat()
  if M.done then return nil end
  local step, frac = studio.pos()
  if not step then return nil end
  return (M.bar * 16 + step - 1 + frac) / 4
end

-- 0 to 1: how full the band sounds (the player's encouragement); the closing bars follow it.
function M.set_energy(e)
  M.energy = e
  studio.synth(4, {volume = 0.3 + 0.25 * e, cutoff = 0.6 + 0.3 * e})
  studio.track(3, {gain = 0.2 + 0.3 * e})
end

function M.stop() studio.stop(); M.done = true end

-- The bass drum on every beat, alone, for tapping along (the calibration); song.offset_now() reads it.
function M.metronome()
  studio.stop()
  studio.tempo(M.BPM, 50)
  studio.length(16)
  studio.track(1, {sound = "BOMBO", gain = 0.9})
  studio.steps(1, {1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0})
  for t = 2, 3 do studio.steps(t, {}) end
  for t = 4, 5 do studio.notes(t, {}) end
  M.done = false
  studio.play()
end

-- Seconds from the nearest beat the player hears now: positive is after it (a tap that comes late), nil when silent.
function M.offset_now()
  local step, frac = studio.pos()
  if not step then return nil end
  local beat = (step - 1 + frac) / 4
  return ((beat + 0.5) % 1 - 0.5) * M.SEC_PER_BEAT
end

-- From bar `bar` (0-based) on, as if the song had got there: for tests and, later, practising a section.
function M.jump(bar)
  studio.stop()
  M.bar, M.last_step, M.done = bar, nil, false
  schedule(bar + 1, false)
  studio.play()
  if bar + 2 <= M.BARS then schedule(bar + 2, true) end
end

return M
