-- music: a driving loop on the synth's voices (tone): a bass pulse, drums, and a riff that comes in with the later rounds. 140 beats a minute, a sixteenth
-- every 6.4 ticks. No file, nothing to load.
local M = {}
M.on, M.mode, M.t, M.intensity = true, nil, 0, 1 -- mode: nil (silent), "title" or "fight"
local STEP = 6.43
local last = -1
local BASS = {"E2", "E2", "G2", "E2", "A2", "E2", "G2", "D2"}
local RIFF = {"E4", false, "G4", false, "B4", "A4", false, "G4", "E4", false, "D4", false, "E4", false, false, false}

function M.set(mode, intensity)
  M.mode, M.t, M.intensity, last = mode, 0, intensity or 1, -1
  if not mode then tone(0) tone(1) tone(2) end
end

function M.update()
  if not M.on or not M.mode then return end
  M.t = M.t + 1
  local step = math.floor(M.t / STEP)
  if step == last then return end
  last = step
  local k = step % 16
  local soft = M.mode == "title"
  if k % 2 == 0 then tone(1, BASS[(step // 2) % 8 + 1], {wave = "square", duty = 0.25, vol = soft and 0.07 or 0.1, decay = 0.1}) end
  if k == 0 or k == 8 or (k == 10 and M.intensity >= 2) then tone(2, 90, {wave = "noise", vol = 0.15, decay = 0.07})
  elseif k == 4 or k == 12 then tone(2, 1700, {wave = "noise", vol = 0.1, decay = 0.09})
  elseif k % 2 == 0 and not soft then tone(2, 7000, {wave = "noise", vol = 0.04, decay = 0.025}) end
  if M.intensity >= 2 and not soft then
    local n = RIFF[k + 1]
    if n then tone(0, n, {wave = "square", duty = 0.125, vol = 0.08 + 0.02 * M.intensity, decay = 0.14}) end
  end
end

return M
