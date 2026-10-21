-- steer: how things move on their own, Craig Reynolds's steering behaviours (1999) and his boids (1987): each one
-- is a wish for a velocity, and the thing accelerates towards it, limited by how fast it can go and turn, so paths
-- come out smooth and alive. seek, flee, arrive (slowing into the target), wander (a roaming that does not jitter),
-- pursue (ahead of a moving target), separate (keep apart), and flock (align, cohere, separate: birds, fish, bats).
--
--   local steer = require("steer")
--   e = {x = 100, y = 100, vx = 0, vy = 0, max_speed = 2, max_force = 0.1}  -- any table with these
--   steer.apply(e, steer.seek(e, tx, ty))           -- seek, flee, arrive(e, tx, ty, slow_radius), wander(e), pursue(e, other)
--   steer.apply(e, steer.flock(e, others, {align = 1, cohere = 1, separate = 1.5, radius = 40}))
--   fx, fy = steer.combine({steer.seek(e, tx, ty), 1}, {steer.separate(e, others, 20), 2})   -- weighted
--
-- A behaviour returns a force (fx, fy); apply() adds it (held to max_force), moves the thing (held to max_speed).
-- Pairs of neighbours cost: fifty birds are fine in Lua; for a hundred and more keep them in a spatial hash
-- (steer.hash) and pass hash:near(e, radius) as `others`.
local M = {}

local function limit(x, y, max)
  local d = math.sqrt(x * x + y * y)
  if d > max and d > 0 then return x / d * max, y / d * max end
  return x, y
end

function M.apply(e, fx, fy)
  fx, fy = limit(fx or 0, fy or 0, e.max_force or 0.1)
  e.vx, e.vy = limit((e.vx or 0) + fx, (e.vy or 0) + fy, e.max_speed or 2)
  e.x, e.y = e.x + e.vx, e.y + e.vy
end

function M.seek(e, tx, ty)
  local dx, dy = limit(tx - e.x, ty - e.y, e.max_speed or 2)
  return dx - (e.vx or 0), dy - (e.vy or 0)
end
function M.flee(e, tx, ty)
  local fx, fy = M.seek(e, tx, ty)
  return -fx, -fy
end
function M.arrive(e, tx, ty, slow)
  local dx, dy = tx - e.x, ty - e.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 0.01 then return -(e.vx or 0), -(e.vy or 0) end
  local speed = (e.max_speed or 2) * math.min(1, d / (slow or 40))
  return dx / d * speed - (e.vx or 0), dy / d * speed - (e.vy or 0)
end
function M.wander(e, opts) -- a target on a circle ahead, nudged a little each tick: a roam without jitter
  opts = opts or {}
  e.wander = (e.wander or 0) + (math.random() * 2 - 1) * (opts.jitter or 0.3)
  local speed = math.sqrt((e.vx or 0) ^ 2 + (e.vy or 0) ^ 2)
  local hx, hy = speed > 0.01 and (e.vx / speed) or 1, speed > 0.01 and (e.vy / speed) or 0
  local dist, r = opts.distance or 30, opts.radius or 15
  local cx, cy = e.x + hx * dist, e.y + hy * dist
  return M.seek(e, cx + math.cos(e.wander) * r, cy + math.sin(e.wander) * r)
end
function M.pursue(e, other, ahead)
  local dx, dy = other.x - e.x, other.y - e.y
  local t = math.sqrt(dx * dx + dy * dy) / (e.max_speed or 2)
  t = math.min(t, ahead or 30)
  return M.seek(e, other.x + (other.vx or 0) * t, other.y + (other.vy or 0) * t)
end
function M.separate(e, others, radius)
  local fx, fy, n = 0, 0, 0
  for _, o in ipairs(others) do
    if o ~= e then
      local dx, dy = e.x - o.x, e.y - o.y
      local d2 = dx * dx + dy * dy
      if d2 > 0 and d2 < radius * radius then
        local d = math.sqrt(d2)
        fx, fy, n = fx + dx / d / d, fy + dy / d / d, n + 1
      end
    end
  end
  if n == 0 then return 0, 0 end
  local sx, sy = limit(fx / n, fy / n, 1)
  return sx * (e.max_speed or 2) - (e.vx or 0), sy * (e.max_speed or 2) - (e.vy or 0)
end
function M.flock(e, others, opts)
  opts = opts or {}
  local r = opts.radius or 40
  local ax, ay, cx, cy, n = 0, 0, 0, 0, 0
  for _, o in ipairs(others) do
    if o ~= e then
      local dx, dy = o.x - e.x, o.y - e.y
      if dx * dx + dy * dy < r * r then ax, ay, cx, cy, n = ax + (o.vx or 0), ay + (o.vy or 0), cx + o.x, cy + o.y, n + 1 end
    end
  end
  local fx, fy = 0, 0
  if n > 0 then
    local sx, sy = limit(ax / n, ay / n, e.max_speed or 2) -- align: their mean heading
    fx, fy = fx + (sx - (e.vx or 0)) * (opts.align or 1), fy + (sy - (e.vy or 0)) * (opts.align or 1)
    local kx, ky = M.arrive(e, cx / n, cy / n, r) -- cohere: towards their middle, gently when near it
    fx, fy = fx + kx * (opts.cohere or 1), fy + ky * (opts.cohere or 1)
  end
  local px, py = M.separate(e, others, opts.separation or r / 2)
  return fx + px * (opts.separate or 1.5), fy + py * (opts.separate or 1.5)
end
function M.combine(...) -- {fx, fy, weight} pairs: ({steer.seek(...)}, w) ... as {{fx, fy}, w}
  local fx, fy = 0, 0
  for _, p in ipairs({...}) do fx, fy = fx + p[1] * (p[3] or 1), fy + p[2] * (p[3] or 1) end
  return fx, fy
end

-- a spatial hash: cells of `size`; hash:rebuild(list) each tick, hash:near(e, radius) -> the ones within reach
local H = {}
H.__index = H
function M.hash(size)
  return setmetatable({size = size or 32, cells = {}}, H)
end
function H:rebuild(list)
  self.cells = {}
  for _, e in ipairs(list) do
    local k = math.floor(e.x / self.size) * 100003 + math.floor(e.y / self.size)
    local c = self.cells[k]
    if not c then c = {} self.cells[k] = c end
    c[#c + 1] = e
  end
end
function H:near(e, radius)
  local out = {}
  local n = math.ceil(radius / self.size)
  local gx, gy = math.floor(e.x / self.size), math.floor(e.y / self.size)
  for dy = -n, n do
    for dx = -n, n do
      local c = self.cells[(gx + dx) * 100003 + gy + dy]
      if c then for _, o in ipairs(c) do out[#out + 1] = o end end
    end
  end
  return out
end

return M
