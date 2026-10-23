-- sound: made from numbers, no files (docs/lua.md, "Sounds made from numbers")
local M = {}

function M.init()
  sound("SFX_STEP", {wave = "noise", freq = 700, slide = -450, sustain = 0.0, decay = 0.05, volume = 0.22, lowpass = 0.5})
  sound("SFX_STATIC", {wave = "noise", freq = 3200, sustain = 0.5, decay = 0.05, volume = 0.5, lowpass = 0.3})
  sound("SFX_WIND", {wave = "noise", freq = 260, sustain = 1.2, decay = 0.2, volume = 0.3, lowpass = 0.12, vibrato = 0.5, vibrato_speed = 3})
  sound("SFX_HEART", {wave = "sine", freq = 74, slide = -40, sustain = 0.0, decay = 0.14, volume = 0.55})
  sound("SFX_KEY", {wave = "square", freq = 880, arp = 1.5, arp_time = 0.07, sustain = 0.06, decay = 0.4, volume = 0.16})
  sound("SFX_DOOR", {wave = "saw", freq = 150, slide = -70, sustain = 0.5, decay = 0.8, volume = 0.3, vibrato = 0.5, vibrato_speed = 9})
  sound("SFX_LOCKED", {wave = "square", freq = 160, sustain = 0.0, decay = 0.08, volume = 0.2})
  sound("SFX_FIGURE", {wave = "saw", freq = 90, slide = -40, sustain = 0.5, decay = 1.2, volume = 0.38, vibrato = 0.6, vibrato_speed = 7})
  sound("SFX_LIT", {wave = "sine", freq = 2300, slide = -700, sustain = 0.05, decay = 0.5, volume = 0.14})
  sound("SFX_CAUGHT", {wave = "noise", freq = 900, slide = -700, sustain = 0.12, decay = 0.9, volume = 0.5, lowpass = 0.7})
  sound("SFX_BLIP", {wave = "square", freq = 880, sustain = 0.0, decay = 0.05, volume = 0.1})
  sound("SFX_TOAST", {wave = "square", freq = 660, arp = 1.5, arp_time = 0.07, sustain = 0.06, decay = 0.2, volume = 0.14})
  sound("SFX_START", {wave = "sine", freq = 110, slide = 60, sustain = 0.6, decay = 1.4, volume = 0.35})
end

local last = {}
function M.play(id, gain, opts)
  local now = ticks()
  if last[id] == now then return end
  last[id] = now
  return sfx(id, gain, opts)
end

return M
