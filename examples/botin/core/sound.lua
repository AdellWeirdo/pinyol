-- sound: the effects, made from numbers (a Game Boy Advance had the old four voices and two channels of samples; these are the voices' kind of sounds).
-- `Sound.play("coin")` is all a module needs.
local S = {}

local DEFS = {
  jump = {wave = "square", duty = 0.25, freq = 330, slide = 900, sustain = 0.04, decay = 0.1, volume = 0.3},
  land = {wave = "noise", freq = 500, slide = -400, sustain = 0.02, decay = 0.06, volume = 0.2, lowpass = 0.4},
  coin = {wave = "square", duty = 0.5, freq = 988, arp = 1.5, arp_time = 0.04, sustain = 0.04, decay = 0.1, volume = 0.22},
  coin_big = {wave = "square", duty = 0.25, freq = 784, arp = 2, arp_time = 0.05, sustain = 0.08, decay = 0.18, volume = 0.26},
  ram = {wave = "noise", freq = 2600, slide = -3500, sustain = 0.05, decay = 0.12, volume = 0.3, lowpass = 0.6},
  smash = {wave = "noise", freq = 900, slide = -700, sustain = 0.08, decay = 0.28, volume = 0.45, lowpass = 0.35},
  brk = {wave = "noise", freq = 1800, slide = -2400, sustain = 0.04, decay = 0.18, volume = 0.35},
  hit = {wave = "square", duty = 0.125, freq = 700, slide = -2200, sustain = 0.04, decay = 0.14, volume = 0.3},
  stun = {wave = "square", duty = 0.5, freq = 440, slide = 500, sustain = 0.03, decay = 0.1, volume = 0.26},
  grab = {wave = "square", duty = 0.5, freq = 330, slide = 330, sustain = 0.03, decay = 0.06, volume = 0.22},
  throw = {wave = "noise", freq = 2200, slide = -3200, sustain = 0.03, decay = 0.1, volume = 0.3, lowpass = 0.5},
  hurt = {wave = "square", duty = 0.5, freq = 520, slide = -1100, sustain = 0.12, decay = 0.22, volume = 0.38},
  die = {wave = "square", duty = 0.25, freq = 600, slide = -1500, sustain = 0.3, decay = 0.4, volume = 0.38},
  heart = {wave = "square", duty = 0.5, freq = 660, arp = 1.5, arp_time = 0.06, sustain = 0.1, decay = 0.16, volume = 0.3},
  jewel = {wave = "square", duty = 0.25, freq = 523, arp = 1.5, arp_time = 0.09, sustain = 0.2, decay = 0.4, volume = 0.32},
  spring = {wave = "square", duty = 0.5, freq = 220, slide = 2400, sustain = 0.05, decay = 0.2, volume = 0.3},
  frog = {wave = "square", duty = 0.5, freq = 140, slide = 600, sustain = 0.12, decay = 0.25, volume = 0.4},
  alarm = {wave = "square", duty = 0.5, freq = 880, sustain = 0.05, decay = 0.05, volume = 0.18},
  splash = {wave = "noise", freq = 1200, slide = -2000, sustain = 0.05, decay = 0.2, volume = 0.3, lowpass = 0.4},
  swim = {wave = "noise", freq = 700, slide = 900, sustain = 0.02, decay = 0.12, volume = 0.16, lowpass = 0.3},
  key = {wave = "square", duty = 0.25, freq = 1175, arp = 1.33, arp_time = 0.05, sustain = 0.06, decay = 0.14, volume = 0.26},
  chest = {wave = "square", duty = 0.25, freq = 392, arp = 2, arp_time = 0.07, sustain = 0.14, decay = 0.3, volume = 0.3},
  fire = {wave = "noise", freq = 1500, slide = 800, sustain = 0.1, decay = 0.2, volume = 0.3, lowpass = 0.5},
  select = {wave = "square", duty = 0.25, freq = 660, sustain = 0.02, decay = 0.05, volume = 0.22},
  confirm = {wave = "square", duty = 0.25, freq = 523, arp = 1.5, arp_time = 0.05, sustain = 0.05, decay = 0.1, volume = 0.26},
  deny = {wave = "square", duty = 0.5, freq = 180, sustain = 0.06, decay = 0.1, volume = 0.28},
  boom = {wave = "noise", freq = 600, slide = -500, sustain = 0.2, decay = 0.5, volume = 0.5, lowpass = 0.25},
}

function S.init()
  for name, d in pairs(DEFS) do sound("SFX_" .. name:upper(), d) end
end

function S.play(name, gain, opts)
  if not DEFS[name] then return end
  return sfx("SFX_" .. name:upper(), gain, opts)
end

return S
