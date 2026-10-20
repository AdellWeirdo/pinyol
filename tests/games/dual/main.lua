-- Two screens, for tests/dual.script: each its own backdrop and its own text; what the bottom one's touch said.
taps, tx, ty, w, h = 0, nil, nil, SCREEN_W, SCREEN_H
function _update()
  local x, y, down, tapped = touch()
  if tapped then taps, tx, ty = taps + 1, x, y end
end
function _draw()
  screen(1)
  backdrop(rgb(30, 60, 120))
  rect(0, 0, 60, 16, 0xF2B233)
  text("ARRIBA", 4, 2, 0x202838, "bold")
  rect(200, 140, 100, 100, 0xFF0000) -- past the screen's edge: cut
  screen(2)
  backdrop(rgb(120, 40, 40))
  text("ABAJO", 4, 2, 0xF0F0F0, "bold")
  box(0, 0, SCREEN_W, SCREEN_H, 0xFFFFFF)
end
