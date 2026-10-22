-- sound: the machine's sounds, made from numbers (docs/lua.md, "Sounds made from numbers"): no files. The cabinets
-- made noise with a few oscillators and a noise source, and so do these.
local M = {}

function M.init()
  sound("SFX_SHOT", {wave = "square", freq = 1900, slide = -9000, sustain = 0.01, decay = 0.07, volume = 0.16, duty = 0.25})
  sound("SFX_MOVE", {wave = "square", freq = 330, sustain = 0.0, decay = 0.02, volume = 0.07})
  sound("SFX_HIT", {wave = "noise", freq = 900, slide = -1600, sustain = 0.02, decay = 0.2, volume = 0.34, lowpass = 0.6})
  sound("SFX_POP", {wave = "noise", freq = 320, slide = -300, sustain = 0.05, decay = 0.32, volume = 0.4, lowpass = 0.45})
  sound("SFX_SPIKE", {wave = "saw", freq = 700, slide = -500, sustain = 0.01, decay = 0.1, volume = 0.18})
  sound("SFX_ZAP", {wave = "saw", freq = 180, slide = 3000, sustain = 0.28, decay = 0.5, volume = 0.45, vibrato = 0.6, vibrato_speed = 38})
  sound("SFX_DIE", {wave = "saw", freq = 640, slide = -640, sustain = 0.25, decay = 1.0, volume = 0.45, vibrato = 0.3, vibrato_speed = 16})
  sound("SFX_WARP", {wave = "sine", freq = 110, slide = 1100, sustain = 0.55, decay = 0.45, volume = 0.34})
  sound("SFX_LEVEL", {wave = "square", freq = 440, arp = 1.5, arp_time = 0.09, sustain = 0.18, decay = 0.35, volume = 0.22})
  sound("SFX_START", {wave = "square", freq = 220, arp = 2, arp_time = 0.12, sustain = 0.3, decay = 0.5, volume = 0.25, again = 0})
  sound("SFX_BLIP", {wave = "square", freq = 880, sustain = 0.0, decay = 0.05, volume = 0.1})
  sound("SFX_TOAST", {wave = "square", freq = 660, arp = 1.5, arp_time = 0.07, sustain = 0.06, decay = 0.2, volume = 0.14})
end

local last = {}
function M.play(id, gain, opts) -- a sound, never twice in the same tick (the zapper kills a dozen at once)
  local now = ticks()
  if last[id] == now then return end
  last[id] = now
  sfx(id, gain, opts)
end

return M
