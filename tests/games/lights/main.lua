-- light() on canvases (tests/lights.script): a round glow that adds, takes away, holds at full, makes a beam
function _init() show(0) end
local function scene(name, base, f)
  canvas(name, 160, 160) target(name) cls(base) f() target()
end
function _draw()
  scene("GLOW", 0x000000, function() light(80, 80, 60, 0xFFFFFF) end)
  scene("RED", 0x000000, function() light(80, 80, 60, 0xFF0000) end)
  scene("HALF", 0x000000, function() light(80, 80, 60, 0xFFFFFF, {intensity = 0.5}) end)
  scene("FULL", 0xFFFFFF, function() light(80, 80, 60, 0xFFFFFF) end)
  scene("SUM", 0x808080, function() light(80, 80, 60, 0xFFFFFF) end)
  scene("SHADOW", 0xFFFFFF, function() light(80, 80, 60, 0xFFFFFF, {sub = true}) end)
  scene("DARK", 0x000000, function() light(80, 80, 60, 0xFFFFFF, {sub = true}) end)
  scene("BEAM", 0x000000, function() light(80, 80, 70, 0xFFFFFF, {cone = {angle = 0, width = 60}}) end)
  scene("EDGE", 0x101010, function() light(10, 10, 60, 0xFFFFFF) end) -- near a corner: clipped by the picture
  scene("TWO", 0x000000, function() light(60, 80, 50, 0xFF0000) light(100, 80, 50, 0x0000FF) end)
  rect(0, 0, 480, 320, 0x101820)
  light(240, 160, 100, 0xFFC060) light(120, 100, 70, 0x60A0FF, {cone = {angle = 30, width = 50}})
  light(360, 220, 60, 0xFFFFFF, {sub = true})
end
function ch(c) return c >> 16 & 255, c >> 8 & 255, c & 255 end
function px(name, x, y) return pget(x, y, name) or 0 end
function red(name, x, y) return (px(name, x, y) >> 16) & 255 end
function grn(name, x, y) return (px(name, x, y) >> 8) & 255 end
function blu(name, x, y) return px(name, x, y) & 255 end

lights = require("lights")
