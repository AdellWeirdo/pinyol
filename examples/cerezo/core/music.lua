-- music: which song plays where. The songs are modules (audio/*.mod made by gen/songs.py); this keeps the one playing,
-- changes it with a short fade, and drops it when the menu or a cutscene asks. A jingle plays over the silence of the song
-- (which waits) and the song comes back when the jingle ends.
local Mu = {}

Mu.now = nil
Mu.volume_on = true
Mu.back, Mu.jt = nil, nil -- the song that waits during a jingle, and the ticks the jingle has left

local FADE = 400

function Mu.play(name, fade)
  if Mu.jt then Mu.back = name return end -- a jingle is playing: the song starts when it ends
  if Mu.now == name then return end
  Mu.now = name
  if not name then music(nil, fade or FADE) return end
  music(name, fade or FADE)
end

function Mu.stop() Mu.back, Mu.jt = nil, nil Mu.now = nil music(nil, 300) end

-- plays a jingle of `secs` seconds, then the song that was playing
function Mu.jingle(name, secs)
  if not Mu.jt then Mu.back = Mu.now end
  Mu.jt = math.floor(secs * 60) + 12
  Mu.now = name
  music(name, 0)
end

function Mu.update()
  if not Mu.jt then return end
  Mu.jt = Mu.jt - 1
  if Mu.jt > 0 then return end
  local b = Mu.back
  Mu.jt, Mu.back, Mu.now = nil, nil, nil
  if b then Mu.play(b, 600) else music(nil, 200) end
end

-- the song of a place: the overworld has a song for each region, the caves one of their own
function Mu.for_screen(area, sx, sy)
  local n = area.notes
  if n.music == "overworld" then
    if sy == 2 then return "beach" end
    if sy == 1 then return "village" end
    if sx == 0 and sy == 0 then return "forest" end
  end
  return n.music
end

return Mu
