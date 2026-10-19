-- line_fx (tests/linefx.script): a backdrop faded by an amount that grows down the screen, then plain again.
-- The first 40 frames use line_fx, the next 40 line_off, so a frame's picture says which one drew it.
n = 0
function _init() show(0) end
function _update() n = n + 1 end
function _draw()
  for y = 0, 159 do line_backdrop(y, 0x40A0FF) end
  fade("dark", 32, 8)               -- the backdrop is the first target: bit 32
  if n % 80 < 40 then
    for y = 0, 159 do line_fx(y, y // 10) end
  else
    line_off()
    for y = 0, 159 do line_backdrop(y, 0x40A0FF) end
  end
end
