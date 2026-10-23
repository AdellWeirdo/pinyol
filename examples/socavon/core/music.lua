-- music: the beeper. One voice (a square wave) plays a tune of tunes.lua, one entry every `step` ticks: a note name, 0 for a rest,
-- "-" to hold the note. And the sounds of the game, which share the same single channel the way the beeper did.
local Tunes = require("tunes")
local Mu = {}

local CH_MUSIC, CH_SFX, CH_NOISE = 2, 0, 3
Mu.name, Mu.i, Mu.t, Mu.on, Mu.muted = nil, 1, 0, false, false

function Mu.play(name)
  if Mu.name == name and Mu.on then return end
  tone(CH_MUSIC)
  Mu.name, Mu.i, Mu.t, Mu.on = name, 1, 0, name ~= nil
end

function Mu.stop() tone(CH_MUSIC) Mu.on = false Mu.name = nil end

-- how many steps a note lasts: itself and the "-" that hold it
local function run_len(notes, k)
  local n = 1
  while notes[k + n] == "-" do n = n + 1 end
  return n
end

function Mu.update()
  if not Mu.on then return end
  local tune = Tunes[Mu.name]
  if not tune then Mu.on = false return end
  if Mu.t % tune.step == 0 then
    local n = tune.notes[Mu.i]
    if n == 0 then
      tone(CH_MUSIC)
    elseif type(n) == "string" and n ~= "-" then
      -- a flat square, as the beeper's: no fade (sustain), the whole run of the note
      tone(CH_MUSIC, n, {wave = "square", duty = 0.5, vol = 0.1, sustain = 1, release = 0.004,
                         len = (run_len(tune.notes, Mu.i) * tune.step - 0.5) / 60})
    end
    Mu.i = Mu.i + 1
    if Mu.i > #tune.notes then
      if tune.loop then Mu.i = 1 else Mu.on = false end
    end
  end
  Mu.t = Mu.t + 1
end

function Mu.done() return not Mu.on end

-- the effects
function Mu.sfx(name)
  if name == "jump" then tone(CH_SFX, 400, {wave = "square", slide = 900, len = 0.25, vol = 0.12})
  elseif name == "key" then tone(CH_SFX, 1200, {wave = "square", len = 0.08, vol = 0.14}) tone(1, 1800, {wave = "square", len = 0.08, vol = 0.1})
  elseif name == "tally" then tone(CH_SFX, 2000, {wave = "square", len = 0.02, vol = 0.1})
  elseif name == "hit" then tone(CH_SFX, 220, {wave = "square", slide = -300, len = 0.5, vol = 0.18})
  elseif name == "crumble" then tone(CH_NOISE, 900, {wave = "noise", len = 0.08, vol = 0.05})
  elseif name == "start" then tone(CH_SFX, 600, {wave = "square", slide = 600, len = 0.2, vol = 0.12}) end
end

return Mu
