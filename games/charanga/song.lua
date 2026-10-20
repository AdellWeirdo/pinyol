-- The episode's music and its clock: «Pasodoble del ascensor», an original arrangement for the studio's sequencer
-- (docs/lua.md, "The studio"): a bass drum, a snare, cymbals and the office's own sounds (the lift's ding, the clock's
-- tick, a knock) made with sound(); two trumpets, a trombone and a tuba on synth voices.
-- The clock is studio.pos(): the step the player hears now, the speaker's queue already taken off, counted into bars
-- here, so the chart never drifts from the music however slow a frame is.
local M = {}

M.BPM = 112
M.BARS = 28                 -- 28 bars of 4/4 at 112: one minute
M.SEC_PER_BEAT = 60 / M.BPM

-- Tracks
local KICK, SNARE, HAT, LEAD, TUBA, SECOND, BONE, CRASH, TICK, KNOCK, DING = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11

local NAMES = {C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11}
local function midi(name) -- "Bb4" -> 70
  local l, acc, oct = name:match("^(%a)([b#]?)(%-?%d)$")
  return 12 * (tonumber(oct) + 1) + NAMES[l] + (acc == "b" and -1 or acc == "#" and 1 or 0)
end

local MAJOR = {0, 2, 4, 5, 7, 9, 11}
local function third_below(n, key) -- the diatonic third under n in the major key whose tonic is pitch class `key`
  local pc = (n - key) % 12
  local deg = 1
  for i, s in ipairs(MAJOR) do if s <= pc then deg = i end end -- (a note out of the key: the degree under it)
  local j, oct = deg - 2, 0
  if j < 1 then j, oct = j + 7, -12 end
  return n - pc + MAJOR[j] + oct
end

-- Melodies: eight eighths a bar ("." is a rest, "-" makes the note before it slide into the next).
local CALL = "C5 . C5 . C5 C5 F5 ."                               -- the trumpets' call out of the lift
local A = {"F4 . A4 C5 F5 . E5 D5", "C5 . Bb4 . A4 G4 A4 .", "Bb4 . D5 . F5 . E5 D5", "C5 . . . A4 . C5 .",
           "F5 . E5 D5 C5 . A4 .", "G4 . Bb4 . D5 . C5 Bb4", "A4 . C5 . G4 . E4 .", "F4 . . . F5 . . ."}
local B = {"D5 . . . A4 . . .", "Bb4 . . . A4 . G4 .", "F4 . . . A4 . D5 .", "E5 . . . . . . .",
           "D5 . F5 . E5 . D5 .", "C5 . Bb4 . A4 . G4 .", "A4 . C5 . E5 . G5 .", "C5 C5 C5 C5 D5 . D5 ."}
local BONE_A = {"F3 . . . C3 . . .", "C3 . . . G3 . . .", "Bb2 . . . D3 . . .", "C3 . . . E3 - G3 .",
                "F3 . . . A3 . . .", "Bb2 . . . G3 . . .", "C3 . . . Bb2 - C3 .", "F3 . C3 . F3 . . ."}
local CHORDS_A = {"F2", "C2", "Bb1", "C2", "F2", "Bb1", "C2", "F2"}
local CHORDS_B = {"D2", "Bb1", "F2", "A1", "D2", "C2", "A1", "D2"}

-- What each bar plays (1-based). Sections: espera 1-4, avance 5-12, duda 13-20, fanfarria 21-28 (a tone higher).
local function bar_plan(b)
  if b == 1 then return {drums = "none", ding = true} end
  if b == 2 then return {drums = "pulse"} end
  if b == 3 then return {drums = "march", bass = "F2"} end
  if b == 4 then return {drums = "roll", bass = "C2", lead = CALL, second = true} end
  if b <= 12 then
    local i = b - 4
    return {drums = i == 8 and "roll" or "march", lead = A[i], second = true, bone = BONE_A[i], bass = CHORDS_A[i],
            crash = i == 1}
  end
  if b <= 20 then
    local i = b - 12
    return {drums = i >= 7 and "build" or "soft", lead = B[i], bass = CHORDS_B[i], tick = i <= 6, crash = i == 1,
            second = i >= 7}
  end
  if b <= 27 then
    local i = b - 20
    return {drums = "fanfare", lead = A[i], second = true, bone = BONE_A[i], bass = CHORDS_A[i], up = 2, loud = true,
            crash = i == 1 or i == 5}
  end
  return {drums = "end", lead = "G5 . . . . . . .", second = true, bone = "G3 . . . . . . .", bass = "G1", crash = true,
          knock = true}
end

local DRUMS = { -- bass drum, snare, hat: velocities on the 16 steps
  none = {{}, {}, {}},
  pulse = {{1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0}, {}, {}},
  march = {{1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0.4},
           {0, 0, 0.6, 0, 0, 0, 0.6, 0, 0, 0, 0.6, 0, 0, 0, 0.6, 0}},
  roll = {{1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0},
          {0, 0, 0, 0, 1, 0, 0, 0, 0.4, 0.45, 0.5, 0.55, 0.6, 0.7, 0.8, 0.95}, {0, 0, 0.6, 0, 0, 0, 0.6, 0}},
  soft = {{0.7, 0, 0, 0, 0, 0, 0, 0, 0.6, 0, 0, 0, 0, 0, 0, 0}, {}, {}},
  build = {{1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0},
           {0.3, 0, 0.35, 0, 0.4, 0, 0.45, 0, 0.5, 0.5, 0.6, 0.6, 0.7, 0.8, 0.9, 1}, {}},
  fanfare = {{1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0}, {0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0.6, 0.8},
             {0.7, 0, 0.7, 0, 0.7, 0, 0.7, 0, 0.7, 0, 0.7, 0, 0.7, 0, 0.7, 0}},
  ["end"] = {{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, {1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, {}},
}

-- Eighths to 16 steps, moved `up` semitones; harmony: each note a diatonic third under itself, in `key`
local function line_steps(line, up, accent, harmony, key)
  local out, i, prev = {}, 0, nil
  for tok in line:gmatch("%S+") do
    i = i + 1
    local s = 2 * i - 1
    if tok == "-" then
      if prev then out[prev].slide = true end
      out[s] = 0
    elseif tok == "." then
      out[s] = 0
    else
      local n = midi(tok) + (up or 0)
      if harmony then n = third_below(n, key) end
      out[s] = {n, accent = accent}
      prev = s
    end
    out[s + 1] = 0
  end
  return out
end

local function tuba_steps(root, up) -- oom-pah: the root, the fifth, the root, the fifth and a passing third
  local r = midi(root) + (up or 0)
  return {r, 0, 0, 0, r + 7, 0, 0, 0, r, 0, 0, 0, r + 7, 0, r + 4, 0}
end

local function one(at) local s = {} s[at] = 1 return s end -- a single hit on a step

local function schedule(b, next_bar) -- bar b's patterns, now or from the next bar line
  local p = bar_plan(b)
  local d = DRUMS[p.drums]
  studio.steps(KICK, d[1], next_bar)
  studio.steps(SNARE, d[2], next_bar)
  studio.steps(HAT, d[3], next_bar)
  local key = 5 + (p.up or 0) -- F major, or G for the fanfare
  studio.notes(LEAD, p.lead and line_steps(p.lead, p.up, p.loud) or {}, next_bar)
  studio.notes(SECOND, p.lead and p.second and line_steps(p.lead, p.up, false, true, key) or {}, next_bar)
  studio.notes(BONE, p.bone and line_steps(p.bone, p.up) or {}, next_bar)
  studio.notes(TUBA, p.bass and tuba_steps(p.bass, p.up) or {}, next_bar)
  studio.steps(CRASH, p.crash and one(1) or {}, next_bar)
  studio.steps(TICK, p.tick and {0.8, 0, 0, 0, 0.5, 0, 0, 0, 0.8, 0, 0, 0, 0.5, 0, 0, 0} or {}, next_bar)
  studio.steps(KNOCK, p.knock and {1, 0, 0, 0.8} or {}, next_bar)
  studio.steps(DING, p.ding and one(1) or {}, next_bar)
end

function M.init() -- the sounds, once
  sound("BOMBO", {wave = "sine", freq = 110, slide = -260, sustain = 0.03, decay = 0.25, punch = 0.4, volume = 0.9})
  sound("CAJA", {wave = "noise", freq = 900, sustain = 0.01, decay = 0.12, highpass = 0.15, volume = 0.5})
  sound("PLATO", {wave = "noise", freq = 2400, sustain = 0.01, decay = 0.3, highpass = 0.5, volume = 0.35})
  sound("CRASH", {wave = "noise", freq = 3000, sustain = 0.05, decay = 1.2, highpass = 0.35, volume = 0.4})
  sound("TIC", {wave = "square", freq = 2600, sustain = 0, decay = 0.02, highpass = 0.4, volume = 0.3})
  sound("TOC", {wave = "sine", freq = 380, slide = -300, sustain = 0.01, decay = 0.08, punch = 0.6, volume = 0.8})
  sound("GOLPE", {wave = "square", freq = 880, arp = 1.5, arp_time = 0.03, sustain = 0.02, decay = 0.1, volume = 0.45})
  sound("FALLO", {wave = "saw", freq = 180, slide = -200, sustain = 0.02, decay = 0.15, volume = 0.3})
  sound("DING", {wave = "sine", freq = 1320, sustain = 0.05, decay = 0.8, volume = 0.45})
end

local function band() -- the instruments, as a song starts
  studio.tempo(M.BPM, 54)
  studio.length(16)
  studio.track(KICK, {sound = "BOMBO", gain = 0.4})
  studio.track(SNARE, {sound = "CAJA", gain = 0.45, reverb = 0.15})
  studio.track(HAT, {sound = "PLATO", gain = 0.3})
  studio.track(CRASH, {sound = "CRASH", gain = 0.45, reverb = 0.3})
  studio.track(TICK, {sound = "TIC", gain = 0.5})
  studio.track(KNOCK, {sound = "TOC", gain = 0.9})
  studio.track(DING, {sound = "DING", gain = 0.6, reverb = 0.4})
  studio.synth(LEAD, {wave = "saw", cutoff = 0.75, res = 0.25, env = 0.35, decay = 0.3, accent = 0.5, volume = 0.9,
                      reverb = 0.2, glide = 0.02})
  studio.synth(SECOND, {wave = "saw", cutoff = 0.55, res = 0.2, env = 0.25, decay = 0.3, volume = 0.6, reverb = 0.2})
  studio.synth(BONE, {wave = "square", cutoff = 0.4, res = 0.15, env = 0.3, decay = 0.45, volume = 0.7, glide = 0.12,
                      reverb = 0.15})
  studio.synth(TUBA, {wave = "square", cutoff = 0.28, res = 0.1, env = 0.2, decay = 0.15, volume = 0.8})
  studio.fx({reverb = "plate", size = 0.45, damp = 0.5})
end

function M.start()
  studio.stop()
  band()
  M.bar, M.last_step, M.done, M.energy = 0, nil, false, 0.5
  schedule(1, false)
  studio.play()
  M.queued = false -- (bar 2 is asked for once bar 1 sounds: asked before, it would take bar 1's place)
end

-- Once a tick: count the bars as the steps come round, and line up the next one.
function M.update()
  if M.done then return end
  local step = studio.pos()
  if not step then return end
  if not M.queued and step >= 2 then
    M.queued = true
    if M.bar + 2 <= M.BARS then schedule(M.bar + 2, true) end
  end
  if M.last_step and step < M.last_step then
    M.bar = M.bar + 1
    if M.bar >= M.BARS then
      studio.stop()
      M.done = true
      return
    end
    M.queued = false -- the bar after this one, once this one sounds
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

-- 0 to 1: how full the band sounds (the player's encouragement): the lead brightens, the cymbals open up.
function M.set_energy(e)
  M.energy = e
  studio.synth(LEAD, {volume = 0.7 + 0.3 * e, cutoff = 0.6 + 0.3 * e})
  studio.synth(SECOND, {volume = 0.45 + 0.2 * e})
  studio.track(HAT, {gain = 0.18 + 0.25 * e})
end

function M.stop() studio.stop(); M.done = true end

-- The bass drum on every beat, alone, for tapping along (the calibration); song.offset_now() reads it.
function M.metronome()
  studio.stop()
  band()
  studio.steps(KICK, {1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0})
  for _, t in ipairs({SNARE, HAT, CRASH, TICK, KNOCK, DING}) do studio.steps(t, {}) end
  for _, t in ipairs({LEAD, SECOND, BONE, TUBA}) do studio.notes(t, {}) end
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

-- From bar `bar` (0-based) on, as if the song had got there: for tests and the pause.
function M.jump(bar)
  studio.stop()
  M.bar, M.last_step, M.done = bar, nil, false
  schedule(bar + 1, false)
  studio.play()
  M.queued = false
end

return M
