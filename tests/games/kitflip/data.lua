-- Two objects that look the other way (tests/kitflip_test.py): one with a pivot, which stays where it was, one without,
-- which turns round the middle of its box as before.
local s = {w = 8, h = 8, frames = 1}
return {title = "Kit flip", tile = 16, background = 0x000000,
  sprites = {giro = s, caja = s},
  kinds = {giro = {behaviour = "still", gravity = false, pivot = {1, 7}}, caja = {behaviour = "still", gravity = false}},
  objects = {{kind = "giro", x = 40, y = 20}, {kind = "caja", x = 40, y = 60}}}
