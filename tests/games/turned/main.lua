-- A canvas drawn again every frame and shown turned (tests/turned.script): what is shown must be what it holds now,
-- not a turned copy kept from before. It takes three colours in turn, so frames (checked every other one) differ.
n = 0
function _init() show(0) canvas("C", 32, 48) end
function _update() n = n + 1 end
function _draw()
  target("C")
  cls(({0xFF0000, 0x00FF00, 0x0000FF})[n % 3 + 1])
  target()
  img("C", 200, 100, {angle = 90})
end
