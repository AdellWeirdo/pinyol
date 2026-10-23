-- sound: the game's effects, all made from numbers with `sound` (a Game Boy had two pulse voices, a wave and a noise, and
-- this is how they were used for effects), and the music's names. `Sound.play("hit")` is all a module needs.
local S = {}

local DEFS = {
  swing = {wave = "noise", freq = 3000, slide = -6000, sustain = 0.02, decay = 0.06, volume = 0.3, lowpass = 0.5},
  hit = {wave = "square", duty = 0.25, freq = 220, slide = -500, sustain = 0.03, decay = 0.08, volume = 0.35},
  cut = {wave = "noise", freq = 2400, slide = -3000, sustain = 0.03, decay = 0.07, volume = 0.3},
  dig = {wave = "noise", freq = 600, slide = -900, sustain = 0.05, decay = 0.1, volume = 0.3},
  hurt = {wave = "square", duty = 0.5, freq = 500, slide = -1000, sustain = 0.15, decay = 0.2, volume = 0.35},
  kill = {wave = "square", duty = 0.125, freq = 700, slide = -2200, sustain = 0.05, decay = 0.15, volume = 0.3},
  heart = {wave = "square", duty = 0.5, freq = 660, arp = 1.5, arp_time = 0.06, sustain = 0.08, decay = 0.1, volume = 0.3},
  cherry = {wave = "square", duty = 0.25, freq = 988, arp = 1.33, arp_time = 0.04, sustain = 0.03, decay = 0.1, volume = 0.25},
  shoot = {wave = "square", duty = 0.125, freq = 900, slide = -1500, sustain = 0.02, decay = 0.08, volume = 0.3},
  blip = {wave = "square", duty = 0.5, freq = 440, sustain = 0.02, decay = 0.03, volume = 0.18},
  select = {wave = "square", duty = 0.25, freq = 660, sustain = 0.02, decay = 0.05, volume = 0.25},
  confirm = {wave = "square", duty = 0.25, freq = 523, arp = 1.5, arp_time = 0.05, sustain = 0.04, decay = 0.08, volume = 0.28},
  deny = {wave = "square", duty = 0.5, freq = 180, sustain = 0.06, decay = 0.1, volume = 0.3},
  door = {wave = "noise", freq = 400, slide = -300, sustain = 0.08, decay = 0.15, volume = 0.3},
  chest = {wave = "square", duty = 0.25, freq = 392, arp = 2, arp_time = 0.07, sustain = 0.12, decay = 0.2, volume = 0.3},
  item = {wave = "square", duty = 0.5, freq = 523, arp = 1.5, arp_time = 0.08, sustain = 0.15, decay = 0.25, volume = 0.3},
  secret = {wave = "square", duty = 0.5, freq = 784, arp = 1.26, arp_time = 0.07, sustain = 0.1, decay = 0.3, volume = 0.28},
  splash = {wave = "noise", freq = 1200, slide = -2000, sustain = 0.05, decay = 0.2, volume = 0.3, lowpass = 0.4},
  low = {wave = "square", duty = 0.5, freq = 1200, sustain = 0.02, decay = 0.04, volume = 0.15},
}

function S.init()
  for name, d in pairs(DEFS) do sound("SFX_" .. name:upper(), d) end
end

function S.play(name, gain, opts)
  if not DEFS[name] then return end
  return sfx("SFX_" .. name:upper(), gain, opts)
end

return S
