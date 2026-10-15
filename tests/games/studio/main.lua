-- The studio from Lua (tests/studio.script): made sounds on steps, played in the audio thread, and where it is.
function _init()
  sound("K", {wave = "sine", freq = 120, slide = -300, sustain = 0.02, decay = 0.2})
  sound("H", "hit", 3)
  ok_k = studio.track(1, {sound = "K", gain = 0.8})
  ok_none = studio.track(2, {sound = "NOPE"})
  studio.track(3, {sound = "H", choke = 1, pitch = 1.5})
  studio.steps(1, {1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0})
  studio.steps(3, {0, 0, 1, 0, 0, 0, 1, 0, false, 0, true, 0, 0, 0, 0.5, 0})
  studio.tempo(128, 58)
  studio.synth(4, {wave = "saw", cutoff = 0.3, res = 0.8, env = 0.6, decay = 0.25, accent = 0.7})
  studio.notes(4, {"A1", 0, {"A2", accent = true}, 0, {45, slide = true}, "C3", false, "E2",
                   "A1", 0, "G1", 0, {"A1", accent = true, slide = true}, "A2", 0, 0})
  seen = {}
end

function _update()
  step, frac = studio.pos()
  if step then seen[step] = true end
end

function _draw()
  cls(0x101418)
  text(step and ("paso " .. step) or "parado", 240, 150, {align = "center", color = 0xFFFFFF})
end
