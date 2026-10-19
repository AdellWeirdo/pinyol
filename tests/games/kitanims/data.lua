-- Named animations as the editor writes them now, each at its own speed, one that stops, and one said the old way
-- (tests/kitanims.script). Nobody moves: each plays its idle.
local frames3 = {w = 8, h = 8, frames = 3}
return {
  title = "Kit anims", tile = 16, background = 0x1D2B53,
  sprites = {rapido = frames3, lento = frames3, una_vez = frames3, viejo = frames3},
  kinds = {
    rapido = {behaviour = "still", gravity = false, animate = 8, anims = {idle = {frames = {0, 1, 2}, fps = 30}}}, -- 2 ticks
    lento = {behaviour = "still", gravity = false, animate = 8, anims = {idle = {frames = {0, 1}}}},             -- its own 8
    una_vez = {behaviour = "still", gravity = false, animate = 3, anims = {idle = {frames = {0, 1, 2}, loop = false}}},
    viejo = {behaviour = "still", gravity = false, animate = 4, anims = {idle = {0, 2}}},                         -- {first, last}
  },
  objects = {{kind = "rapido", x = 16, y = 16}, {kind = "lento", x = 48, y = 16}, {kind = "una_vez", x = 80, y = 16},
             {kind = "viejo", x = 112, y = 16}},
}
