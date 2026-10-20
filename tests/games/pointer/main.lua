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
-- two fingers: the last pinch seen, the most fingers, the middle's path
pinch_seen, most, moved2 = nil, 0, 0
local base_update = _update
function _update()
  base_update()
  most = math.max(most, pointer.fingers)
  if pointer.pinch then pinch_seen = pointer.pinch; moved2 = moved2 + pointer.pinch.dx end
end
-- digits: a figure written with the pen (pointer.written), and each digit drawn by a hand of its own (not the
-- library's templates: other corners, slanted, shaken, smaller, elsewhere on the screen)
written_digit = nil
local update2 = _update
function _update()
  update2()
  if pointer.written then written_digit = pointer.digit(pointer.written) end
end
local HAND = {
  [0] = {{{48, 2}, {28, 12}, {22, 50}, {30, 88}, {50, 98}, {72, 86}, {78, 48}, {70, 12}, {50, 2}}},
  [1] = {{{52, 4}, {49, 97}}},
  [2] = {{{22, 22}, {40, 4}, {62, 3}, {77, 18}, {74, 40}, {24, 96}, {82, 97}}},
  [3] = {{{22, 12}, {50, 2}, {74, 12}, {72, 36}, {48, 47}, {74, 60}, {76, 86}, {50, 99}, {22, 90}}},
  [4] = {{{58, 3}, {18, 62}, {86, 63}}, {{68, 32}, {67, 98}}},
  [5] = {{{74, 3}, {30, 3}, {27, 42}, {58, 37}, {76, 58}, {74, 84}, {55, 98}, {26, 92}}},
  [6] = {{{68, 3}, {36, 22}, {24, 58}, {32, 90}, {55, 98}, {74, 82}, {68, 58}, {42, 54}, {25, 70}}},
  [7] = {{{22, 3}, {78, 4}, {44, 97}}},
  [8] = {{{68, 12}, {48, 2}, {30, 14}, {34, 34}, {52, 47}, {74, 66}, {70, 90}, {48, 99}, {27, 86}, {32, 64}, {52, 47}, {68, 30}, {66, 10}}},
  [9] = {{{76, 22}, {56, 3}, {34, 8}, {27, 28}, {40, 44}, {64, 42}, {76, 22}, {75, 62}, {68, 98}}},
}
local function dense(stroke, ox, oy, k, slant) -- walked every 2 px, slanted, shaken a little, as a pen gives it
  local out = {}
  for i = 1, #stroke - 1 do
    local a, b = stroke[i], stroke[i + 1]
    local n = math.max(1, math.floor(math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2) * k / 2))
    for j = 0, n - 1 do
      local x, y = a[1] + (b[1] - a[1]) * j / n, a[2] + (b[2] - a[2]) * j / n
      local m = #out + 1
      out[m] = {ox + (x + slant * (100 - y)) * k + math.sin(m * 1.7) * 1.2, oy + y * k + math.cos(m * 2.3) * 1.2}
    end
  end
  local z = stroke[#stroke]
  out[#out + 1] = {ox + (z[1] + slant * (100 - z[2])) * k, oy + z[2] * k}
  return out
end
function check_digits(k, slant) -- "" when every digit is read right, else what was read for each wrong one
  local bad = ""
  for d = 0, 9 do
    local strokes = {}
    for i, s in ipairs(HAND[d]) do strokes[i] = dense(s, 150, 60, k, slant) end
    local got = pointer.digit(strokes)
    if got ~= d then bad = bad .. d .. ">" .. tostring(got) .. " " end
  end
  return bad
end
