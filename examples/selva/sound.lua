-- sound: made from numbers, no files (docs/lua.md, "Sounds made from numbers")
local M = {}

function M.init()
  sound("SFX_JUMP", {wave = "square", freq = 330, slide = 700, sustain = 0.02, decay = 0.14, volume = 0.2, duty = 0.4})
  sound("SFX_FRUIT", {wave = "square", freq = 880, arp = 1.5, arp_time = 0.05, sustain = 0.04, decay = 0.12, volume = 0.16})
  sound("SFX_CRATE", {wave = "noise", freq = 600, slide = -900, sustain = 0.03, decay = 0.22, volume = 0.38, lowpass = 0.55})
  sound("SFX_STOMP", {wave = "sine", freq = 160, slide = -120, sustain = 0.02, decay = 0.16, volume = 0.4})
  sound("SFX_BUMP", {wave = "sine", freq = 120, slide = -60, sustain = 0.0, decay = 0.1, volume = 0.32})
  sound("SFX_HURT", {wave = "saw", freq = 520, slide = -520, sustain = 0.12, decay = 0.3, volume = 0.36, vibrato = 0.3, vibrato_speed = 22})
  sound("SFX_FALL", {wave = "sine", freq = 700, slide = -650, sustain = 0.1, decay = 0.5, volume = 0.34})
  sound("SFX_SPIN", {wave = "noise", freq = 1400, slide = 1800, sustain = 0.18, decay = 0.12, volume = 0.18, lowpass = 0.7})
  sound("SFX_OVER", {wave = "saw", freq = 420, slide = -380, sustain = 0.3, decay = 0.9, volume = 0.36, vibrato = 0.4, vibrato_speed = 14})
  sound("SFX_START", {wave = "square", freq = 262, arp = 1.5, arp_time = 0.09, sustain = 0.2, decay = 0.3, volume = 0.22})
  sound("SFX_TOAST", {wave = "square", freq = 660, arp = 1.5, arp_time = 0.07, sustain = 0.06, decay = 0.2, volume = 0.14})
  sound("SFX_STEP", {wave = "noise", freq = 500, slide = -300, sustain = 0.0, decay = 0.04, volume = 0.16, lowpass = 0.4})
  sound("SFX_LAND", {wave = "noise", freq = 380, slide = -200, sustain = 0.01, decay = 0.1, volume = 0.22, lowpass = 0.35})
  sound("SFX_MILE", {wave = "square", freq = 523, arp = 1.5, arp_time = 0.06, sustain = 0.12, decay = 0.3, volume = 0.2})
  sound("SFX_BLIP", {wave = "square", freq = 880, sustain = 0.0, decay = 0.05, volume = 0.1})
end

local last = {}
function M.play(id, gain, opts)
  local now = ticks()
  if last[id] == now then return end
  last[id] = now
  sfx(id, gain, opts)
end

return M
