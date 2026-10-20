-- stylus: a finger or a stylus as the DS's games used it (see docs/ds-touch-research.md). Draw a circle, a triangle,
-- a square, a line or a zigzag and it is named; drag the block; flick for its direction; the button clears.
-- block, said and flick are global so tests/stylus.script can read them.
local pointer = require("pointer")
local NAMES = {line = "línea", circle = "círculo", triangle = "triángulo", square = "cuadrado", zigzag = "zigzag"}

block = {x = 60, y = 230, w = 56, h = 56}
local clear = {x = 380, y = 270, w = 90, h = 40}
local grab -- where inside the block it was taken, while it is dragged
local ink = {}      -- strokes drawn and kept, each a list of points
said, score, flick = "dibuja una forma", nil, nil

function _update()
  pointer.update()
  if pointer.pressed(clear) then
    ink, said, score, flick = {}, "dibuja una forma", nil, nil
    return
  end
  if pointer.stroke and not grab and pointer.pick({block}, pointer.stroke[1][1], pointer.stroke[1][2]) then
    grab = {pointer.stroke[1][1] - block.x, pointer.stroke[1][2] - block.y}
  end
  if grab then
    if pointer.down then
      block.x = math.max(0, math.min(SCREEN_W - block.w, pointer.x - grab[1]))
      block.y = math.max(0, math.min(SCREEN_H - block.h, pointer.y - grab[2]))
    else
      grab = nil
    end
  elseif pointer.released and pointer.last then
    local name, s = pointer.recognize(pointer.last)
    if name then
      said, score = NAMES[name], s
      ink[#ink + 1] = pointer.simplify(pointer.last, 2)
    elseif #pointer.last > 8 then
      said, score = "no sé qué es", s
    end
    flick = pointer.flick and pointer.flick.dir or flick
  end
end

local function path(points, colour)
  for k = 2, #points do line(points[k - 1][1], points[k - 1][2], points[k][1], points[k][2], colour) end
end

function _draw()
  cls(0x1A1F2E)
  for _, s in ipairs(ink) do path(s, 0x6FD0A0) end
  if pointer.stroke then path(pointer.stroke, 0xF2B233) end
  rect(block.x, block.y, block.w, block.h, grab and 0xF2B233 or 0x3A4660)
  box(block.x, block.y, block.w, block.h, 0xF0F0F0)
  rect(clear.x, clear.y, clear.w, clear.h, 0x3A4660)
  text("Borrar", clear.x + clear.w // 2, clear.y + 11, 0xF0F0F0, "bold", "center")
  text(said .. (score and string.format(" (%d%%)", math.floor(score * 100 + 0.5)) or ""), SCREEN_W // 2, 14, 0xF0F0F0, "large_bold", "center")
  text("golpe: " .. (flick or "-"), 14, 296, 0x9AA6C0, "main")
end
