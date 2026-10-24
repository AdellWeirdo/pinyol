-- rng: random numbers a game can count on. math.random is one stream for everything, so a particle drawn changes the
-- next room's layout; here each thing gets its own stream from a seed (a level, a run, a creature), and the same seed
-- always gives the same numbers whatever else happened. Underneath, Squirrel Eiserloh's noise (GDC 2017, "Noise-based
-- RNG"): a hash of (position, seed), so the n-th number can also be asked for directly, in any order.
--
--   local rng = require("rng")
--   local r = rng.new(seed)              -- a stream (seed: any integer; the day's, the run's, the room's number)
--   r:int(a, b)  r:float()  r:float(a, b)  r:chance(p)  r:pick(list)  r:shuffle(list)  r:sign()
--   r:gauss()                            -- roughly a bell curve, mean 0, most within -3..3
--   rng.hash(i [, seed]) -> 0..1          -- the i-th number of a seed, without a stream (a tile's flower, a star's twinkle)
--   rng.fbm(x, y [, octaves [, lacunarity [, gain]]]) -- noise() stacked (fractal): hills with detail, clouds
local M = {}
local R = {}
R.__index = R

local function squirrel(n, seed) -- Squirrel3: a 32-bit hash of an index and a seed
  n = (n * 0xB5297A4D) & 0xFFFFFFFF
  n = (n + (seed or 0)) & 0xFFFFFFFF
  n = n ~ (n >> 8)
  n = (n + 0x68E31DA4) & 0xFFFFFFFF
  n = n ~ (n << 8) & 0xFFFFFFFF
  n = (n + 0x1B56C4E9) & 0xFFFFFFFF
  n = n ~ (n >> 8)
  return n & 0xFFFFFFFF
end

local function unit(n) -- a 32-bit hash as 0..1 (the console's integers are 32 bits: a high bit reads as a sign)
  if n < 0 then n = n + 4294967296.0 end
  return n / 4294967296.0
end

function M.hash(i, seed) return unit(squirrel(math.floor(i), seed)) end

function M.new(seed)
  return setmetatable({seed = math.floor(seed or 0), i = 0}, R)
end

function R:next() -- the next 32-bit number
  self.i = self.i + 1
  return squirrel(self.i, self.seed)
end
function R:float(a, b)
  local f = unit(self:next())
  if a == nil then return f end
  return a + (b - a) * f
end
function R:int(a, b) -- a..b, both in
  if b == nil then a, b = 1, a end
  return a + self:next() % (b - a + 1)
end
function R:chance(p) return self:float() < p end
function R:sign() return self:next() % 2 == 0 and 1 or -1 end
function R:pick(t) return t[self:int(#t)] end
function R:shuffle(t) -- in place, Fisher-Yates
  for i = #t, 2, -1 do
    local j = self:int(i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end
function R:gauss() -- the sum of three, less a half each: a bell
  return (self:float() + self:float() + self:float()) * 2 - 3
end
function R:reset(seed) self.seed, self.i = math.floor(seed or self.seed), 0 end

function M.fbm(x, y, octaves, lacunarity, gain)
  local total, amp, freq, norm = 0, 1, 1, 0
  for _ = 1, octaves or 4 do
    total = total + noise(x * freq, (y or 0) * freq) * amp
    norm = norm + amp
    amp, freq = amp * (gain or 0.5), freq * (lacunarity or 2)
  end
  return total / norm
end

return M
