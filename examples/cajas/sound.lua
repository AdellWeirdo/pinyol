-- sound: made from numbers, no files
local M = {}
function M.init()
  sound("SFX_WHOOSH", {wave = "noise", freq = 2400, slide = -1800, sustain = 0.0, decay = 0.09, volume = 0.12, lowpass = 0.7})
  sound("SFX_HIT", {wave = "noise", freq = 700, slide = -500, sustain = 0.02, decay = 0.14, volume = 0.4, lowpass = 0.5})
  sound("SFX_HIT_BIG", {wave = "noise", freq = 500, slide = -420, sustain = 0.04, decay = 0.22, volume = 0.5, lowpass = 0.4})
  sound("SFX_BLOCK", {wave = "square", freq = 220, slide = -60, sustain = 0.0, decay = 0.08, volume = 0.2, duty = 0.3})
  sound("SFX_JUMP", {wave = "sine", freq = 200, slide = 300, sustain = 0.0, decay = 0.12, volume = 0.16})
  sound("SFX_LAND", {wave = "noise", freq = 300, slide = -150, sustain = 0.0, decay = 0.08, volume = 0.16, lowpass = 0.3})
  sound("SFX_BELL", {wave = "sine", freq = 880, sustain = 0.1, decay = 0.9, volume = 0.3})
  sound("SFX_KO", {wave = "saw", freq = 300, slide = -250, sustain = 0.2, decay = 0.8, volume = 0.4, vibrato = 0.3, vibrato_speed = 10})
  sound("SFX_FIGHT", {wave = "square", freq = 330, arp = 2, arp_time = 0.07, sustain = 0.15, decay = 0.3, volume = 0.22})
  sound("SFX_WIN", {wave = "square", freq = 523, arp = 1.5, arp_time = 0.1, sustain = 0.3, decay = 0.6, volume = 0.24})
  sound("SFX_TOAST", {wave = "square", freq = 660, arp = 1.5, arp_time = 0.07, sustain = 0.06, decay = 0.2, volume = 0.14})
  sound("SFX_BLIP", {wave = "square", freq = 880, sustain = 0.0, decay = 0.05, volume = 0.1})
end
local last = {}
function M.play(id, gain, opts)
  local now = ticks()
  if last[id] == now then return end
  last[id] = now
  return sfx(id, gain, opts)
end
return M
