-- music: which song plays. The songs are MIDI files played by a bank of samples (audio/*.mid + audio/BANK.bank, made by gen/songs.py), the way the GBA's
-- sound driver played its songs. This keeps the one playing, changes it with a short fade and plays a jingle over the silence of the song, which comes
-- back when the jingle ends.
local Mu = {}

Mu.now = nil
Mu.back, Mu.jt = nil, nil -- the song that waits during a jingle, and the ticks the jingle has left
local FADE = 400

local function start(name, fade, loop)
  music(name, fade, {bank = "BANK", loop = loop})
end

function Mu.play(name, fade)
  if Mu.jt then Mu.back = name return end
  if Mu.now == name then return end
  Mu.now = name
  if not name then music(nil, fade or FADE) return end
  start(name, fade or FADE, true)
end

function Mu.stop(fade) Mu.back, Mu.jt, Mu.now = nil, nil, nil music(nil, fade or 300) end

-- a jingle of `secs` seconds; the song comes back after it (or nothing, if `keep` is false)
function Mu.jingle(name, secs, keep)
  if not Mu.jt then Mu.back = keep ~= false and Mu.now or nil end
  Mu.jt = math.floor(secs * 60) + 12
  Mu.now = name
  start(name, 0, false)
end

function Mu.update()
  if not Mu.jt then return end
  Mu.jt = Mu.jt - 1
  if Mu.jt > 0 then return end
  local b = Mu.back
  Mu.jt, Mu.back, Mu.now = nil, nil, nil
  if b then Mu.play(b, 600) else music(nil, 200) end
end

return Mu
