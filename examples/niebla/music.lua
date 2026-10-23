-- music: not a tune: a drone that never settles, played live on the synth's voices (tone), a low note that falls a semitone from its neighbour every
-- few seconds, and now and then a high thin one far off. With the Figure close the notes come closer together. No file, nothing to load.
local M = {}
local rng = require("rng")

local LOW = {"E2", "F2", "B1", "C2", "E2", "D#2"}
local HIGH = {"B5", "F#5", "C6", "G5"}
M.on, M.mode, M.t, M.danger = true, nil, 0, 0 -- mode: nil (silent), "title" or "play"

function M.set(mode)
  M.mode, M.t = mode, 0
  if not mode then tone(0) tone(1) tone(2) end
end

function M.update()
  if not M.on or not M.mode then return end
  M.t = M.t + 1
  local gap = M.mode == "play" and math.floor(280 - 160 * M.danger) or 360 -- ticks between the low notes
  if M.t % gap == 1 then
    local i = (M.t // gap) % #LOW + 1
    tone(0, LOW[i], {wave = "triangle", vol = 0.1 + 0.06 * M.danger, decay = 3.4})
    tone(1, LOW[(i + 2) % #LOW + 1], {wave = "sine", vol = 0.08, decay = 3.8}) -- a note a step off it
  end
  if M.t % 410 == 200 then
    tone(2, HIGH[(M.t // 410) % #HIGH + 1], {wave = "sine", vol = 0.05, decay = 1.6, vibrato = 0.3, vibrato_speed = 5})
  end
end

return M
