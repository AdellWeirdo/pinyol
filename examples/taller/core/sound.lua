-- sound: the effects, from numbers (`sound` makes them when the game starts). `Sound.play("punch")` is all a module needs.
local S = {}

local DEFS = {
  punch = {wave = "noise", freq = 700, slide = -500, sustain = 0.01, decay = 0.07, punch = 0.8, lowpass = 0.5, volume = 0.45},
  heavy = {wave = "noise", freq = 260, slide = -180, sustain = 0.04, decay = 0.2, punch = 1, lowpass = 0.45, volume = 0.6},
  whoosh = {wave = "noise", freq = 1800, slide = -1200, attack = 0.03, sustain = 0.02, decay = 0.08, highpass = 0.3, lowpass = 0.7, volume = 0.18},
  hit = {wave = "fm", freq = 1500, fm_ratio = 2.76, fm_index = 3, sustain = 0, decay = 0.09, volume = 0.38},
  clank = {wave = "square", duty = 0.125, freq = 1200, slide = -3000, sustain = 0.01, decay = 0.05, volume = 0.22},
  steam = {wave = "noise", freq = 3200, sustain = 0.1, decay = 0.35, highpass = 0.5, lowpass = 0.9, volume = 0.3},
  gears = {wave = "square", duty = 0.25, freq = 2200, arp = 1.5, arp_time = 0.03, sustain = 0.02, decay = 0.09, volume = 0.2},
  jump = {wave = "square", duty = 0.25, freq = 300, slide = 900, sustain = 0.03, decay = 0.1, volume = 0.18},
  land = {wave = "noise", freq = 200, sustain = 0.01, decay = 0.06, lowpass = 0.25, volume = 0.4},
  down = {wave = "noise", freq = 300, slide = -200, sustain = 0.03, decay = 0.2, punch = 0.7, lowpass = 0.35, volume = 0.5},
  boom = {wave = "noise", freq = 300, slide = -150, sustain = 0.05, decay = 0.35, punch = 0.6, lowpass = 0.7, lowpass_sweep = -0.8, volume = 0.5},
  big = {wave = "noise", freq = 120, slide = -60, sustain = 0.15, decay = 0.9, punch = 0.8, lowpass = 0.6, lowpass_sweep = -0.5, volume = 0.6},
  die = {wave = "saw", freq = 330, slide = -500, sustain = 0.03, decay = 0.18, punch = 0.5, lowpass = 0.55, volume = 0.45},
  pickup = {wave = "square", freq = 988, arp = 1.5, arp_time = 0.06, duty = 0.25, sustain = 0.05, decay = 0.15, volume = 0.3},
  part = {wave = "square", freq = 523, arp = 1.5, arp_time = 0.05, duty = 0.5, sustain = 0.1, decay = 0.3, volume = 0.32},
  oil = {wave = "sine", freq = 660, slide = 500, sustain = 0.05, decay = 0.25, volume = 0.3},
  coin = {wave = "square", freq = 1046, arp = 1.335, arp_time = 0.07, duty = 0.5, sustain = 0.06, decay = 0.25, volume = 0.3},
  special = {wave = "saw", freq = 200, slide = 1200, slide_accel = 400, vibrato = 0.3, vibrato_speed = 18, attack = 0.2, sustain = 0.2, decay = 0.15, lowpass = 0.7, volume = 0.35},
  break_ = {wave = "noise", freq = 1200, slide = -600, sustain = 0.03, decay = 0.2, lowpass = 0.6, volume = 0.4},
  bell = {wave = "fm", freq = 880, fm_ratio = 3.5, fm_index = 2, attack = 0.005, sustain = 0.05, decay = 0.7, volume = 0.3},
  ring = {wave = "fm", freq = 440, fm_ratio = 2, fm_index = 4, sustain = 0.1, decay = 0.5, volume = 0.3},
  stomp = {wave = "noise", freq = 300, slide = -250, sustain = 0.2, decay = 0.5, volume = 0.5, lowpass = 0.15},
  select = {wave = "square", freq = 1320, duty = 0.125, sustain = 0.01, decay = 0.04, volume = 0.3},
  confirm = {wave = "square", freq = 880, arp = 1.5, arp_time = 0.05, duty = 0.25, sustain = 0.04, decay = 0.12, volume = 0.25},
  deny = {wave = "square", duty = 0.5, freq = 180, sustain = 0.06, decay = 0.1, volume = 0.26},
  alarm = {wave = "square", duty = 0.5, freq = 440, sustain = 0.08, decay = 0.05, volume = 0.2},
}

function S.init()
  for name, d in pairs(DEFS) do sound("SFX_" .. name:upper(), d) end
end

function S.play(name, gain, opts)
  if not DEFS[name] then return end
  return sfx("SFX_" .. name:upper(), gain, opts)
end

return S
