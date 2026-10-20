-- What lib/pointer.lua made of a finger, for tests/pointer.script: counts of each event, the last flick, the target.
pointer = require("pointer")
taps, longs, drags, releases, flick, picked = 0, 0, 0, 0, nil, nil
targets = {{id = "small", x = 100, y = 100, w = 10, h = 10}, {id = "big", x = 300, y = 100, w = 80, h = 80}}
function count(t) return #t end
-- the shapes a test draws: a ring, a polygon's walked edges, a hand's shake
function ring(n, r, cx, cy, a0)
  local p = {}
  for k = 0, n do local a = a0 + k / n * 2 * math.pi; p[#p + 1] = {cx + r * math.cos(a), cy + r * math.sin(a)} end
  return p
end
function poly(c, open)
  local p = {}
  for k = 1, open and #c - 1 or #c do
    local a, b = c[k], c[k % #c + 1]
    for i = 0, 11 do p[#p + 1] = {a[1] + (b[1] - a[1]) * i / 12, a[2] + (b[2] - a[2]) * i / 12} end
  end
  p[#p + 1] = open and c[#c] or c[1]
  return p
end
function jitter(p, m)
  local q = {}
  for k, v in ipairs(p) do q[k] = {v[1] + math.sin(k * 7.3) * m, v[2] + math.cos(k * 3.1) * m} end
  return q
end
function _update()
  pointer.update()
  pointer.update() -- a second call in the same tick changes nothing
  if pointer.tapped then taps = taps + 1; picked = pointer.pick(targets, pointer.x, pointer.y) end
  if pointer.long then longs = longs + 1 end
  if pointer.dragging then drags = drags + 1 end
  if pointer.released then releases = releases + 1 end
  if pointer.flick then flick = pointer.flick end
end
function _draw() cls(0) end
