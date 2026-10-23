-- music: four voices, as PICO-8 has four channels. A tune of tunes.lua is four lists of notes, one entry every `step` ticks per voice:
-- a note name, 0 for a rest, "-" to hold the note.
local Tunes = require("tunes")
local Mu = {}

Mu.name, Mu.i, Mu.t, Mu.on = nil, 1, 0, false
Mu.active = {false, false, false, false} -- which voice sounds now (the explainer draws it)
Mu.level = {0, 0, 0, 0}                  -- a bar for each voice that falls off, drawn by the explainer

local function run_len(notes, k)
  local n = 1
  while notes[k + n] == "-" do n = n + 1 end
  return n
end

function Mu.play(name)
  if Mu.name == name and Mu.on then return end
  for v = 0, 3 do tone(v) end
  Mu.name, Mu.i, Mu.t, Mu.on = name, 1, 0, name ~= nil
end

function Mu.stop() for v = 0, 3 do tone(v) end Mu.on, Mu.name = false, nil end
function Mu.done() return not Mu.on end

function Mu.update()
  for v = 1, 4 do Mu.level[v] = math.max(0, Mu.level[v] - 0.08) end
  if not Mu.on then return end
  local tune = Tunes[Mu.name]
  if not tune then Mu.on = false return end
  if Mu.t % tune.step == 0 then
    local n_steps = #tune.voices[1].notes
    for vi, voice in ipairs(tune.voices) do
      local v = vi - 1
      local n = voice.notes[Mu.i]
      if n == 0 then
        tone(v)
      elseif n ~= "-" and n ~= nil then
        local len = (run_len(voice.notes, Mu.i) * tune.step - 0.5) / 60
        if voice.wave == "noise" then
          tone(v, n, {wave = "noise", vol = voice.vol, decay = n < 1000 and 0.08 or n < 4000 and 0.05 or 0.02, len = len, release = 0.01})
        else
          tone(v, n, {wave = voice.wave, duty = voice.duty or 0.5, vol = voice.vol, sustain = 1, release = 0.004, len = len})
        end
        Mu.level[vi] = 1
      end
    end
    Mu.i = Mu.i + 1
    if Mu.i > n_steps then
      if tune.loop then Mu.i = 1 else Mu.on = false end
    end
  end
  Mu.t = Mu.t + 1
end

return Mu
