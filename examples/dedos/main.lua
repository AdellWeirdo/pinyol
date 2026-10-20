-- dedos: every finger on the screen (touches()), the pinch two of them make (lib/pointer.lua), and how much a finger
-- held still shakes: to try the console's touch panel. Numbers on screen are in its 480x320 pixels.
-- shake, pinch_seen and most are global so tests/dedos.script can read them.
local pointer = require("pointer")
local COLOURS = {0xF2B233, 0x6FD0A0, 0xE0605A, 0x6A9CF0, 0xC48AE8}
local STILL = 60 -- ticks of the first finger kept to measure its shake
local path = {}  -- its last positions
shake, pinch_seen, most = nil, nil, 0

function _update()
  pointer.update()
  most = math.max(most, pointer.fingers)
  if pointer.pinch then pinch_seen = pointer.pinch end
  if pointer.began then path = {} end
  if pointer.down then
    path[#path + 1] = {pointer.x, pointer.y}
    if #path > STILL then table.remove(path, 1) end
    if #path == STILL then -- the spread of the last second's points round their middle: 0 is a finger that never moved
      local mx, my = 0, 0
      for _, p in ipairs(path) do mx, my = mx + p[1], my + p[2] end
      mx, my = mx / STILL, my / STILL
      local sum = 0
      for _, p in ipairs(path) do sum = sum + (p[1] - mx) ^ 2 + (p[2] - my) ^ 2 end
      shake = math.sqrt(sum / STILL)
    end
  end
end

function _draw()
  cls(0x1A1F2E)
  local t = touches()
  for i, f in ipairs(t) do
    circ(f[1], f[2], 22, COLOURS[i], false)
    circ(f[1], f[2], 3, COLOURS[i])
    local label = i .. ": " .. f[1] .. ", " .. f[2]
    local w = textw(label, "bold")
    local x = f[1] + 26 + w < SCREEN_W - 4 and f[1] + 26 or f[1] - 26 - w -- to its left near the right edge
    text(label, x, math.max(0, math.min(SCREEN_H - 20, f[2] - 8)), COLOURS[i], "bold")
  end
  if #t >= 2 then line(t[1][1], t[1][2], t[2][1], t[2][2], 0x5A6480) end
  text(#t .. (#t == 1 and " dedo" or " dedos") .. " · máximo " .. most, 10, 8, 0xF0F0F0, "bold")
  if pointer.pinch then
    text(string.format("pellizco x%.2f · giro %d°", pointer.pinch.scale, math.floor(math.deg(pointer.pinch.angle) + 0.5)),
         10, 30, 0x9AA6C0, "main")
  end
  text(shake and string.format("temblor %.1f px (último segundo)", shake) or "deja un dedo quieto un segundo",
       10, 290, 0x9AA6C0, "main")
end
