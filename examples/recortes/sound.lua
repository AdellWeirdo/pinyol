-- sound: the little effects, made from numbers (the music and the singing are tone voices: see music.lua and main.lua)
local M = {}

function M.init()
  sound("SFX_COOL", {wave = "square", freq = 1320, arp = 1.5, arp_time = 0.04, sustain = 0.05, decay = 0.2, volume = 0.12})
  sound("SFX_MISS", {wave = "noise", freq = 500, slide = -300, sustain = 0.03, decay = 0.16, volume = 0.22, lowpass = 0.4})
  sound("SFX_BAD", {wave = "saw", freq = 200, slide = -90, sustain = 0.05, decay = 0.2, volume = 0.18})
  sound("SFX_START", {wave = "square", freq = 330, arp = 1.5, arp_time = 0.08, sustain = 0.2, decay = 0.3, volume = 0.2})
  sound("SFX_DONE", {wave = "square", freq = 523, arp = 2, arp_time = 0.1, sustain = 0.3, decay = 0.5, volume = 0.22})
  sound("SFX_TOAST", {wave = "square", freq = 660, arp = 1.5, arp_time = 0.07, sustain = 0.06, decay = 0.2, volume = 0.14})
  sound("SFX_BLIP", {wave = "square", freq = 880, sustain = 0.0, decay = 0.05, volume = 0.1})
  sound("SFX_COUNT", {wave = "sine", freq = 440, sustain = 0.0, decay = 0.12, volume = 0.2})
end

local last = {}
function M.play(id, gain)
  local now = ticks()
  if last[id] == now then return end
  last[id] = now
  sfx(id, gain)
end

return M
