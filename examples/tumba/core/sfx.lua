-- sfx: the sounds, made from numbers (sound recipes), as PICO-8's sfx editor made them.
local S = {}

function S.init()
  sound("SFX_SLIDE", {wave = "noise", freq = 1800, slide = -900, sustain = 0.05, decay = 0.12, volume = 0.18})
  sound("SFX_BUMP", {wave = "square", freq = 150, slide = -80, sustain = 0.02, decay = 0.07, volume = 0.3})
  sound("SFX_GEM", {wave = "square", freq = 880, arp = 1.5, arp_time = 0.04, sustain = 0.05, decay = 0.1, volume = 0.22})
  sound("SFX_KEY", {wave = "square", freq = 660, arp = 2, arp_time = 0.05, sustain = 0.08, decay = 0.12, volume = 0.22})
  sound("SFX_CRACK", {wave = "noise", freq = 700, slide = -300, sustain = 0.04, decay = 0.2, volume = 0.3})
  sound("SFX_DOOR", {wave = "square", freq = 220, slide = 400, sustain = 0.1, decay = 0.2, volume = 0.25})
  sound("SFX_TELE", {wave = "square", freq = 300, slide = 1500, sustain = 0.03, decay = 0.12, volume = 0.2})
  sound("SFX_MUD", {wave = "noise", freq = 300, sustain = 0.03, decay = 0.1, volume = 0.2})
  sound("SFX_UNDO", {wave = "square", freq = 500, slide = -300, sustain = 0.02, decay = 0.08, volume = 0.18})
  sound("SFX_SELECT", {wave = "square", freq = 600, sustain = 0.02, decay = 0.05, volume = 0.18})
  sound("SFX_OK", {wave = "square", freq = 440, arp = 2, arp_time = 0.05, sustain = 0.06, decay = 0.12, volume = 0.22})
  sound("SFX_DEAD", {wave = "square", freq = 440, slide = -900, sustain = 0.15, decay = 0.25, volume = 0.3})
  sound("SFX_TOAST", {wave = "square", freq = 988, arp = 1.5, arp_time = 0.06, sustain = 0.1, decay = 0.2, volume = 0.2})
end

function S.play(id) sfx(id) end

return S
