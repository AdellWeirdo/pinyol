-- A swarm's rules (tests/enjambre.script): room, life, leaving the area, hits, one of them read and moved, drawing
-- with a camera and on a canvas.
function len(s) return #s end -- (tests: a script line takes # for a comment)

function _init()
  show(0)
  canvas("DOT", 6, 6)
  target("DOT") cls(0xFF8040) target()
  canvas("BOARD", 120, 80)
  rain = swarm(300, {-40, -400, 520, 360}) -- (it starts above the screen: the area reaches up for it)
  for i = 0, 299 do rain:add(i * 1.6, -10 - (i % 37) * 9, 0.3, 2 + (i % 5) * 0.5) end
end

function _update() rain:step() end

function _draw()
  cls(0x101830)
  camera(0, -20) -- everything 20 lower: the swarm too
  rain:draw("DOT")
  camera()
  target("BOARD") cls(0x204020) rain:draw("DOT") target()
  img("BOARD", 340, 220)
end
