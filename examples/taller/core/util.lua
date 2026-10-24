-- util: small helpers every module uses
local U = {}

function U.clamp(v, a, b) return v < a and a or (v > b and b or v) end
function U.sign(v) return v > 0 and 1 or (v < 0 and -1 or 0) end
function U.approach(v, target, step)
  if v < target then return math.min(v + step, target) end
  return math.max(v - step, target)
end
function U.overlap(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end
function U.dist(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return math.sqrt(dx * dx + dy * dy)
end

-- the four ways a character faces, as unit steps
U.DIRS = {down = {0, 1}, up = {0, -1}, left = {-1, 0}, right = {1, 0}}
U.OPPOSITE = {down = "up", up = "down", left = "right", right = "left"}

-- the direction of a vector (the dominant axis)
function U.dir_of(dx, dy)
  if math.abs(dx) > math.abs(dy) then return dx < 0 and "left" or "right" end
  return dy < 0 and "up" or "down"
end

-- a white hit-flash on `o` (a foe, a prop, the hero): at most three a second for each, and none for a player who asked for fewer flashes (a combo must not strobe)
function U.blink(o)
  if settings().reduce_flashing then return false end
  local t = ticks()
  if t < (o.flash_next or 0) then return false end
  o.flash_next = t + 20
  return true
end

function U.copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = type(v) == "table" and U.copy(v) or v end
  return out
end

-- a number from the cell, the same every run: variation that needs no random numbers
function U.hash(x, y, salt)
  local h = (x * 73856093) ~ (y * 19349663) ~ ((salt or 0) * 83492791)
  return (h & 0x7FFFFFFF)
end

return U
