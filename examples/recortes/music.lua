-- music: played live on the synth's voices (tone) from the game's own clock, so it is in time with the rhythm by construction: a bass and drums always,
-- chords when the mood is good, an arpeggio when it is cool. Voice 3 is left to the singing (the teacher's notes and the player's).
local G = require("game")
local M = {}

M.on = true
local last_step = -1

local DRUM_KICK = {[0] = true, [8] = true, [10] = true}
local DRUM_SNARE = {[4] = true, [12] = true}

function M.reset() last_step = -1 tone(0) tone(1) tone(2) end

function M.update()
  if not M.on or G.done or not G.song then return end
  local step_f = G.t / G.step_t
  local step = math.floor(step_f)
  if step == last_step then return end
  last_step = step
  local bar = (step // 16) % 4 + 1
  local k = step % 16
  local rank = G.rank
  local s = G.song
  if G.t < 0 and step < -16 * s.intro + 4 then return end -- (silent for the first beat)
  if k % 4 == 0 or k == 6 or k == 14 then tone(1, s.bass[bar], {wave = "square", duty = 0.25, vol = 0.1, decay = 0.22}) end
  if DRUM_KICK[k] then tone(2, 90, {wave = "noise", vol = 0.16, decay = 0.07})
  elseif DRUM_SNARE[k] then tone(2, 1800, {wave = "noise", vol = 0.1, decay = 0.09})
  elseif k % 2 == 0 then tone(2, 7000, {wave = "noise", vol = 0.04, decay = 0.025}) end
  if rank ~= "awful" and (k == 0 or k == 6 or k == 8 or k == 12) then -- chords
    local ch = s.chords[bar]
    tone(0, ch[(k // 4) % 3 + 1], {wave = "triangle", vol = rank == "bad" and 0.08 or 0.14, decay = 0.3})
  end
  if rank == "cool" and k % 2 == 1 then
    local ch = s.chords[bar]
    tone(0, ch[(k // 2) % 3 + 1], {wave = "square", duty = 0.125, vol = 0.07, decay = 0.1}) -- a sparkle
  end
end

return M
