-- sound: the effects, from numbers (`sound` makes them when the game starts). `Sound.play("boom")` is all a module needs.
local S = {}

local DEFS = {
  knife = {wave = "noise", freq = 2400, slide = -3000, sustain = 0.02, decay = 0.08, highpass = 0.35, lowpass = 0.8, volume = 0.5},
  foam = {wave = "noise", freq = 900, slide = -400, attack = 0.01, sustain = 0.08, decay = 0.15, lowpass = 0.45, lowpass_sweep = -1.2, highpass = 0.1, volume = 0.45},
  croqueta = {wave = "square", freq = 180, slide = -260, duty = 0.35, sustain = 0.03, decay = 0.14, punch = 0.6, lowpass = 0.5, volume = 0.4},
  rice = {wave = "noise", freq = 3000, sustain = 0.05, decay = 0.22, highpass = 0.4, lowpass = 0.9, vibrato = 0.4, vibrato_speed = 30, volume = 0.45},
  cream = {wave = "noise", freq = 900, sustain = 0.02, decay = 0.05, volume = 0.16, lowpass = 0.3},
  cork = {wave = "square", freq = 700, slide = -2500, sustain = 0.01, decay = 0.06, punch = 0.9, volume = 0.45},
  cannon = {wave = "noise", freq = 150, slide = -80, sustain = 0.05, decay = 0.35, punch = 1, lowpass = 0.5, volume = 0.55},
  vulcan = {wave = "noise", freq = 2200, slide = -1800, sustain = 0.01, decay = 0.04, volume = 0.2},
  pea = {wave = "square", duty = 0.25, freq = 900, slide = -2000, sustain = 0.01, decay = 0.06, volume = 0.16},
  rocket = {wave = "noise", freq = 700, slide = 600, sustain = 0.15, decay = 0.25, volume = 0.3, lowpass = 0.4},
  hit = {wave = "fm", freq = 1500, fm_ratio = 2.76, fm_index = 3, sustain = 0, decay = 0.09, volume = 0.4},
  boom = {wave = "noise", freq = 300, slide = -150, sustain = 0.05, decay = 0.35, punch = 0.6, lowpass = 0.7, lowpass_sweep = -0.8, volume = 0.5},
  big = {wave = "noise", freq = 120, slide = -60, sustain = 0.15, decay = 0.9, punch = 0.8, lowpass = 0.6, lowpass_sweep = -0.5, volume = 0.6},
  stab = {wave = "noise", freq = 4200, slide = -3800, sustain = 0.02, decay = 0.07, volume = 0.26},
  jump = {wave = "square", duty = 0.25, freq = 300, slide = 900, sustain = 0.03, decay = 0.1, volume = 0.18},
  land = {wave = "noise", freq = 200, sustain = 0.01, decay = 0.06, lowpass = 0.25, volume = 0.4},
  die = {wave = "saw", freq = 330, slide = -500, sustain = 0.03, decay = 0.18, punch = 0.5, lowpass = 0.55, volume = 0.45},
  pickup = {wave = "square", freq = 988, arp = 1.5, arp_time = 0.06, duty = 0.25, sustain = 0.05, decay = 0.15, volume = 0.3},
  food = {wave = "square", freq = 1046, arp = 1.335, arp_time = 0.07, duty = 0.5, sustain = 0.06, decay = 0.25, volume = 0.3},
  rescue = {wave = "noise", freq = 4000, sustain = 0.005, decay = 0.04, highpass = 0.6, volume = 0.5},
  tractor = {wave = "square", duty = 0.5, freq = 70, sustain = 0.05, decay = 0.05, volume = 0.18, lowpass = 0.2},
  horn = {wave = "square", duty = 0.5, freq = 330, sustain = 0.18, decay = 0.1, volume = 0.3},
  select = {wave = "square", freq = 1320, duty = 0.125, sustain = 0.01, decay = 0.04, volume = 0.3},
  confirm = {wave = "square", freq = 880, arp = 1.5, arp_time = 0.05, duty = 0.25, sustain = 0.04, decay = 0.12, volume = 0.25},
  deny = {wave = "square", duty = 0.5, freq = 180, sustain = 0.06, decay = 0.1, volume = 0.26},
  coin = {wave = "square", freq = 1046, arp = 1.335, arp_time = 0.07, duty = 0.5, sustain = 0.06, decay = 0.25, volume = 0.3},
  alarm = {wave = "square", duty = 0.5, freq = 440, sustain = 0.08, decay = 0.05, volume = 0.2},
  stomp = {wave = "noise", freq = 300, slide = -250, sustain = 0.2, decay = 0.5, volume = 0.5, lowpass = 0.15},
  beam = {wave = "saw", freq = 1400, slide = -2600, sustain = 0.08, decay = 0.4, punch = 0.7, lowpass = 0.7, lowpass_sweep = -0.6, volume = 0.5},
  charge = {wave = "saw", freq = 200, slide = 900, slide_accel = 600, vibrato = 0.3, vibrato_speed = 14, attack = 0.6, sustain = 0.1, decay = 0.05, lowpass = 0.6, volume = 0.35},
  caw = {wave = "saw", freq = 1300, slide = -900, vibrato = 0.5, vibrato_speed = 24, sustain = 0.08, decay = 0.12, lowpass = 0.7, resonance = 0.6, volume = 0.22},
  clank = {wave = "square", duty = 0.125, freq = 1200, slide = -3000, sustain = 0.01, decay = 0.05, volume = 0.2},
}

function S.init()
  for name, d in pairs(DEFS) do sound("SFX_" .. name:upper(), d) end
end

function S.play(name, gain, opts)
  if not DEFS[name] then return end
  return sfx("SFX_" .. name:upper(), gain, opts)
end

return S
