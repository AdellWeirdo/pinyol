-- music: a four-bar groove in E minor played live by the synth's voices (tone): a bass, an arpeggio that joins when the run starts, and
-- drums on the noise voice. A 16th note every 7 ticks (about 128 beats a minute). The voices are the console's own (docs/lua.md, `tone`):
-- no file, nothing to load.
local M = {}

local STEP = 7
local BASS = { -- four bars of sixteen steps: a note name where it plays
  {"E2", false, false, "E2", false, false, "E3", false, "E2", false, false, "G2", false, false, "E2", "D2"},
  {"C2", false, false, "C2", false, false, "C3", false, "C2", false, false, "E2", false, false, "C2", "B1"},
  {"D2", false, false, "D2", false, false, "D3", false, "D2", false, false, "F#2", false, false, "D2", "E2"},
  {"B1", false, false, "B1", false, false, "B2", false, "B1", false, false, "D2", false, false, "F#2", "A2"},
}
local ARP = { -- the chord's tones, two to a beat
  {"E4", "G4", "B4", "G4", "E5", "B4", "G4", "B4"},
  {"E4", "G4", "C5", "G4", "E5", "C5", "G4", "C5"},
  {"F#4", "A4", "D5", "A4", "F#5", "D5", "A4", "D5"},
  {"D4", "F#4", "B4", "F#4", "D5", "B4", "F#4", "B4"},
}

M.on, M.mode, M.t = true, nil, 0 -- mode: nil (silent), "soft" (bass and drums), "full" (and the arpeggio)

function M.set(mode)
  if mode ~= M.mode then M.mode = mode; M.t = 0 end
  if not mode then tone(0) tone(1) tone(2) end
end

function M.update()
  if not M.on or not M.mode then return end
  M.t = M.t + 1
  if M.t % STEP ~= 1 then return end
  local step = (M.t // STEP) % 64
  local bar, k = step // 16 + 1, step % 16 + 1
  local soft = M.mode == "soft"
  local b = BASS[bar][k]
  if b then tone(1, b, {wave = "square", duty = 0.25, vol = soft and 0.07 or 0.1, decay = 0.28}) end
  if not soft and k % 2 == 1 then tone(0, ARP[bar][(k - 1) // 2 + 1], {wave = "triangle", vol = 0.2, decay = 0.16}) end
  if k == 1 or k == 9 then tone(2, 90, {wave = "noise", vol = soft and 0.1 or 0.16, decay = 0.09}) -- a kick
  elseif k % 4 == 3 then tone(2, 7000, {wave = "noise", vol = soft and 0.03 or 0.05, decay = 0.03}) end -- a hat
end

return M
