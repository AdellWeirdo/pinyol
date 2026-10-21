-- perf("ops"): where a frame's drawing goes (tests/prof.script). Three quads, two lights, four rects, a box, a text.
function _init() show(0) canvas("T", 64, 64) target("T") cls(0xC08040) target() end
function _draw()
  rect(0, 0, 480, 320, 0x101820)
  rect(10, 10, 30, 30, 0xFF0000) rect(50, 10, 30, 30, 0x00FF00) rect(90, 10, 30, 30, 0x0000FF)
  box(10, 60, 100, 40, 0xFFFFFF)
  for i = 0, 2 do quad("T", 150 + i * 100, 60, 240 + i * 100, 60, 240 + i * 100, 150, 150 + i * 100, 150) end
  light(100, 200, 60, 0xFFC060) light(300, 220, 80, 0x60A0FF)
  text("hola", 10, 300)
end
-- perf("lua"): busy() is the dear one, light() the cheap one, both called from _update once heavy is set
function busy() local s = 0 for i = 1, 40000 do s = s + i % 7 end return s end
function light_work() local s = 0 for i = 1, 400 do s = s + i end return s end
function _update() if heavy then busy() light_work() end end
