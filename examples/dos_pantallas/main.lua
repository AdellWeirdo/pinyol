-- dos_pantallas: two screens as the DS's games used them (docs/ds-dual-screen-design.md, ds-touch-research.md).
-- Bottom, the touch one: a map of five figures; a tap picks the nearest one, a flick sends it. Top: a close view of
-- the picked one. A button beats a touch order (as in Nintendo's patent): the cross moves the picked figure and stops it.
-- units, sel and pointer are global so tests/dos_pantallas.script can read them.
pointer = require("pointer")
pointer.MIN_TARGET = 24 -- the map is 240x160: a smaller fingertip than the console's whole screen

local NAMES = {"Ana", "Biel", "Cleo", "Dani", "Eli"}
local COLOURS = {0xF2B233, 0x6FD0A0, 0xE0605A, 0x6A9CF0, 0xC48AE8}
units = {}
sel = 1

function _init()
  for i = 1, 5 do
    units[i] = {name = NAMES[i], col = COLOURS[i], x = 30 + (i - 1) * 40, y = 40 + (i % 2) * 60, vx = 0, vy = 0}
  end
end

local function targets()
  local t = {}
  for i, u in ipairs(units) do t[i] = {x = u.x - 4, y = u.y - 4, w = 8, h = 8, i = i} end
  return t
end

function _update()
  pointer.update()
  if pointer.tapped then -- the figure nearest the touch
    local hit = pointer.pick(targets(), pointer.x, pointer.y)
    if hit then sel = hit.i end
  end
  if pointer.flick and pointer.last then -- the figure nearest where the flick began goes the way it went
    local hit = pointer.pick(targets(), pointer.last[1][1], pointer.last[1][2])
    if hit then
      local f = pointer.flick
      local n = math.max(math.abs(f.dx), math.abs(f.dy), 1)
      units[hit.i].vx, units[hit.i].vy = f.dx / n * 2, f.dy / n * 2
      sel = hit.i
    end
  end
  if btnp("a") then sel = sel % #units + 1 end
  local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
  local dy = (btn("down") and 1 or 0) - (btn("up") and 1 or 0)
  for i, u in ipairs(units) do
    if i == sel and (dx ~= 0 or dy ~= 0) then
      u.vx, u.vy = 0, 0 -- the button beats the touch order
      u.x, u.y = u.x + dx, u.y + dy
    end
    u.x, u.y = u.x + u.vx, u.y + u.vy
    u.vx, u.vy = u.vx * 0.97, u.vy * 0.97
    u.x, u.y = math.max(4, math.min(W - 4, u.x)), math.max(4, math.min(H - 4, u.y))
  end
end

function _draw()
  local me = units[sel]
  screen(1) -- the close view: the picked figure in the middle, everything else round it three times bigger
  backdrop(rgb(26, 48, 40))
  for gx = -2, 2 do line(120 + gx * 60 - (me.x * 3) % 60, 0, 120 + gx * 60 - (me.x * 3) % 60, SCREEN_H, 0x2E5A48) end
  for gy = -2, 2 do line(0, 80 + gy * 60 - (me.y * 3) % 60, SCREEN_W, 80 + gy * 60 - (me.y * 3) % 60, 0x2E5A48) end
  for i, u in ipairs(units) do
    circ(120 + (u.x - me.x) * 3, 80 + (u.y - me.y) * 3, i == sel and 14 or 9, u.col, true)
  end
  text(me.name, 6, 4, 0xF0F0F0, "bold")
  text(string.format("%d, %d", math.floor(me.x + 0.5), math.floor(me.y + 0.5)), 6, 136, 0xB8D8C8, "main")

  screen(2) -- the map, where the finger is
  backdrop(rgb(32, 38, 58))
  for i, u in ipairs(units) do
    circ(u.x, u.y, 4, u.col, true)
    if i == sel then circ(u.x, u.y, 8, 0xFFFFFF, false) end
  end
  if pointer.stroke then
    for k = 2, #pointer.stroke do
      local a, b = pointer.stroke[k - 1], pointer.stroke[k]
      line(a[1], a[2], b[1], b[2], 0xF2B233)
    end
  end
  text("toca · lanza", 6, 136, 0x8A94B0, "main")
end
