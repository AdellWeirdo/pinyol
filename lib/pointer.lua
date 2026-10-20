-- pointer: a stylus or a finger, as the DS's games used it: taps, long presses, drags, flicks, strokes drawn and
-- recognised, and the target nearest where a touch began.
--
--   local pointer = require("pointer")
--   in _update (once): pointer.update()
--     pointer.down, pointer.x, pointer.y         -- the finger now, in the screen's 480x320 pixels (as text() uses)
--     pointer.began, pointer.tapped, pointer.long, pointer.released   -- true on the one tick it happens (began: it went down)
--     pointer.dragging, pointer.dx, pointer.dy   -- moved past the slop since it went down; the move since last tick
--     pointer.flick                              -- on lift, a fast short stroke: {dx, dy, vx, vy, dir = "up"|"down"|"left"|"right"}
--     pointer.vx, pointer.vy                     -- on every lift, pixels a tick the finger was going (0 when it stopped first)
--     pointer.stroke                             -- the points of the stroke going on; pointer.last on lift
--   pointer.pressed(item)                        -- true when that {x, y, w, h} was tapped
--   pointer.pick(items, x, y)                    -- the item ({x, y, w, h}) nearest (x, y), each at least 40 px to hit
--   pointer.simplify(points, eps)                -- fewer points keeping the shape (Ramer-Douglas-Peucker)
--   pointer.recognize(points)                    -- "line", "circle", "triangle", "square" or "zigzag", and a score 0..1
--
-- Points are {x, y}. Numbers at the top are the ones to tune: the slop is how far a finger may wander and still be a tap.
-- Skipped on purpose: the DS's filter of five raw samples (the engine reads one point a tick; see docs/ds-touch-research.md)
-- and a left-handed flip.
local M = {}

M.SLOP = 12        -- pixels: further than this from where it went down is a drag, not a tap
M.LONG = 30        -- ticks held still that make a long press
M.FLICK_SPEED = 6  -- pixels per tick over the last few ticks, at least, to be a flick
M.MIN_TARGET = 40  -- pixels: a smaller target is hit as if it were this big (a fingertip; the DS's stylus needed less)
M.MIN_SCORE = 0.7  -- a recognised shape below this is "nothing" (nil)

local sx, sy, held, still
M.down, M.x, M.y, M.dx, M.dy, M.stroke, M.last = false, 0, 0, 0, 0, nil, nil

local function reset_events()
  M.began, M.tapped, M.long, M.released, M.flick, M.vx, M.vy = false, false, false, false, nil, 0, 0
end

function M.update()
  reset_events()
  local x, y, down, tapped, released = pen()
  M.dx, M.dy = 0, 0
  if tapped then
    M.began = true
    sx, sy, held, still = x, y, 0, true
    M.stroke, M.dragging = {{x, y}}, false
  elseif down and M.stroke then
    held = held + 1
    M.dx, M.dy = x - M.x, y - M.y
    local pts = M.stroke
    local p = pts[#pts]
    if p[1] ~= x or p[2] ~= y then pts[#pts + 1] = {x, y} end
    if still and math.abs(x - sx) + math.abs(y - sy) > M.SLOP then still, M.dragging = false, true end
    if still and held == M.LONG then M.long = true end
  end
  if released and M.stroke then
    local pts = M.stroke
    M.released, M.last, M.stroke, M.dragging = true, pts, nil, false
    if still and held < M.LONG then M.tapped = true end
    local n = math.min(#pts, 5) -- the last few ticks' speed
    local a, b = pts[#pts - n + 1], pts[#pts]
    if a and not still and n > 1 then
      local dx, dy = b[1] - a[1], b[2] - a[2]
      M.vx, M.vy = dx / (n - 1), dy / (n - 1) -- on every lift: what a list goes on with
      if math.sqrt(dx * dx + dy * dy) / (n - 1) >= M.FLICK_SPEED then
        local dir = math.abs(dx) > math.abs(dy) and (dx > 0 and "right" or "left") or (dy > 0 and "down" or "up")
        M.flick = {dx = dx, dy = dy, dir = dir, vx = M.vx, vy = M.vy}
      end
    end
  end
  if down or tapped then M.x, M.y = x, y end
  M.down = down
end

function M.pick(items, x, y)
  local best, bd
  for _, it in ipairs(items) do
    local w, h = math.max(it.w, M.MIN_TARGET), math.max(it.h, M.MIN_TARGET)
    local cx, cy = it.x + it.w / 2, it.y + it.h / 2
    if math.abs(x - cx) <= w / 2 and math.abs(y - cy) <= h / 2 then
      local d = (x - cx) ^ 2 + (y - cy) ^ 2
      if not bd or d < bd then best, bd = it, d end
    end
  end
  return best
end

function M.pressed(item) -- true on the tick the item was tapped (it is a target as pick takes it)
  return M.tapped and M.pick({item}, M.x, M.y) == item
end

local function seg_dist(p, a, b)
  local dx, dy = b[1] - a[1], b[2] - a[2]
  local len2 = dx * dx + dy * dy
  local t = len2 > 0 and math.max(0, math.min(1, ((p[1] - a[1]) * dx + (p[2] - a[2]) * dy) / len2)) or 0
  local qx, qy = a[1] + t * dx - p[1], a[2] + t * dy - p[2]
  return math.sqrt(qx * qx + qy * qy)
end

local function rdp(pts, i, j, eps, keep)
  local far, at = 0, nil
  for k = i + 1, j - 1 do
    local d = seg_dist(pts[k], pts[i], pts[j])
    if d > far then far, at = d, k end
  end
  if at and far > eps then
    keep[at] = true
    rdp(pts, i, at, eps, keep)
    rdp(pts, at, j, eps, keep)
  end
end

function M.simplify(pts, eps)
  if #pts < 3 then return pts end
  local keep = {[1] = true, [#pts] = true}
  rdp(pts, 1, #pts, eps or 3, keep)
  local out = {}
  for k = 1, #pts do if keep[k] then out[#out + 1] = pts[k] end end
  return out
end

-- Recognition: the $1 unistroke recogniser (Wobbrock, Wilson, Li 2007): resample to N points, turn the first point
-- (seen from the middle) to angle 0, scale to a square, centre, and take the template with the least mean distance.
local N, SIZE = 48, 100

local function length(pts)
  local d = 0
  for k = 2, #pts do d = d + math.sqrt((pts[k][1] - pts[k - 1][1]) ^ 2 + (pts[k][2] - pts[k - 1][2]) ^ 2) end
  return d
end

local function resample(pts)
  local step, acc, out = length(pts) / (N - 1), 0, {pts[1]}
  if step == 0 then return nil end
  local p = {}
  for k = 1, #pts do p[k] = pts[k] end
  local k = 2
  while k <= #p do
    local a, b = p[k - 1], p[k]
    local d = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
    if acc + d >= step and d > 0 then
      local t = (step - acc) / d
      local q = {a[1] + t * (b[1] - a[1]), a[2] + t * (b[2] - a[2])}
      out[#out + 1] = q
      table.insert(p, k, q)
      acc = 0
    else
      acc = acc + d
    end
    k = k + 1
  end
  while #out < N do out[#out + 1] = p[#p] end
  return out
end

local function centroid(pts)
  local cx, cy = 0, 0
  for _, q in ipairs(pts) do cx, cy = cx + q[1], cy + q[2] end
  return cx / #pts, cy / #pts
end

local function normalise(pts) -- turn, scale to SIZE x SIZE, centre on the origin
  local pts = resample(pts)
  if not pts then return nil end
  local cx, cy = centroid(pts)
  local ang = -math.atan(pts[1][2] - cy, pts[1][1] - cx)
  local c, s = math.cos(ang), math.sin(ang)
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  local out = {}
  for k, q in ipairs(pts) do
    local x, y = (q[1] - cx) * c - (q[2] - cy) * s, (q[1] - cx) * s + (q[2] - cy) * c
    out[k] = {x, y}
    x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y)
  end
  local w, h = math.max(x1 - x0, 1e-6), math.max(y1 - y0, 1e-6)
  local k = SIZE / math.max(w, h) -- one scale for both: a line stays flat, a circle round
  for _, q in ipairs(out) do q[1], q[2] = q[1] * k, q[2] * k end
  local mx, my = centroid(out)
  for _, q in ipairs(out) do q[1], q[2] = q[1] - mx, q[2] - my end
  return out
end

local function distance(a, b)
  local d = 0
  for k = 1, N do d = d + math.sqrt((a[k][1] - b[k][1]) ^ 2 + (a[k][2] - b[k][2]) ^ 2) end
  return d / N
end

local function polygon(corners, closed) -- a template from its corners, each edge walked
  local pts = {}
  local n = #corners
  for k = 1, closed and n or n - 1 do
    local a, b = corners[k], corners[k % n + 1]
    for i = 0, 15 do pts[#pts + 1] = {a[1] + (b[1] - a[1]) * i / 16, a[2] + (b[2] - a[2]) * i / 16} end
  end
  if closed then pts[#pts + 1] = pts[1] else pts[#pts + 1] = corners[n] end
  return pts
end

local SHAPES = {
  line = {polygon({{0, 0}, {100, 0}}, false)},
  circle = {(function()
    local p = {}
    for k = 0, 63 do p[#p + 1] = {math.cos(k / 64 * 2 * math.pi) * 50, math.sin(k / 64 * 2 * math.pi) * 50} end
    p[#p + 1] = p[1]
    return p
  end)()},
  triangle = {polygon({{50, 0}, {100, 100}, {0, 100}}, true)},
  square = {polygon({{0, 0}, {100, 0}, {100, 100}, {0, 100}}, true)},
  zigzag = {polygon({{0, 0}, {30, 100}, {50, 0}, {80, 100}, {100, 0}}, false)},
}

local templates -- built on the first recognise: name -> list of normalised variants (every start, both ways)

local function variants(pts, closed)
  local base = resample(pts)
  local n, out = #base, {}
  for _, rev in ipairs({false, true}) do
    for s = 0, closed and 7 or 0 do -- a closed shape may be begun anywhere: eight starts
      local v, off = {}, closed and math.floor(s * (n - 1) / 8) or 0
      for k = 1, n do
        local i = closed and (off + k - 1) % (n - 1) + 1 or k
        v[k] = base[rev and n + 1 - i or i]
      end
      out[#out + 1] = normalise(v)
    end
  end
  return out
end

function M.recognize(pts)
  if not pts or #pts < 8 or length(pts) < 30 then return nil end
  if not templates then
    templates = {}
    for name, list in pairs(SHAPES) do
      local first, last = list[1][1], list[1][#list[1]]
      local closed = first[1] == last[1] and first[2] == last[2]
      templates[name] = variants(list[1], closed)
    end
  end
  local cand = normalise(pts)
  if not cand then return nil end
  local best, bd = nil, math.huge
  for name, list in pairs(templates) do
    for _, t in ipairs(list) do
      local d = distance(cand, t)
      if d < bd then best, bd = name, d end
    end
  end
  local score = 1 - bd / (0.5 * math.sqrt(2 * SIZE * SIZE))
  if score < M.MIN_SCORE then return nil, score end
  return best, score
end

return M
