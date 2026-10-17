-- util: the few Python builtins the board game's core leans on, with Python's meaning (core/*.lua is a port of
-- audreygotchi/core/*.py). Numbers are 32-bit here, as on the console.
local M = {}

function M.int(x) -- Python int(): towards zero
  if x >= 0 then return math.floor(x) end
  return math.ceil(x)
end

function M.round(x, nd) -- Python round(): halves to even; nd decimals as a float
  if nd then
    local m = 10 ^ nd
    return M.round(x * m) / m
  end
  local f = math.floor(x)
  local d = x - f
  if d > 0.5 then return f + 1 end
  if d < 0.5 then return f end
  return (f % 2 == 0) and f or f + 1
end

function M.clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function M.get(t, k, default) -- dict.get
  local v = t and t[k]
  if v == nil then return default end
  return v
end

function M.contains(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

function M.index(list, v) -- list.index, 0-based; nil when missing
  for i, x in ipairs(list) do if x == v then return i - 1 end end
  return nil
end

function M.sum(list) local s = 0 for _, x in ipairs(list) do s = s + x end return s end

function M.copy(t) -- a shallow copy (list(x), dict(x))
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

function M.deepcopy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = M.deepcopy(v) end
  return c
end

function M.keys(t) -- sorted, so every run walks them the same way
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks, function(a, b)
    if type(a) == type(b) then return a < b end
    return type(a) < type(b)
  end)
  return ks
end

function M.len(t) -- len() of a dict
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

function M.slice(list, a, b) -- list[a:b], Python indices (0-based, b exclusive, negatives from the end)
  local n = #list
  a = a or 0
  b = b or n
  if a < 0 then a = math.max(0, n + a) end
  if b < 0 then b = math.max(0, n + b) end
  local out = {}
  for i = a + 1, math.min(b, n) do out[#out + 1] = list[i] end
  return out
end

-- random, as Python's random module: math.random is the game's one generator (seeded once by the front end)
function M.random() return math.random() end
function M.randint(a, b) return math.random(a, b) end
function M.uniform(a, b) return a + (b - a) * math.random() end
function M.choice(list) return list[math.random(#list)] end

function M.sample(list, k) -- k different items, in random order
  local pool = M.copy(list)
  local out = {}
  for _ = 1, k do
    local i = math.random(#pool)
    out[#out + 1] = table.remove(pool, i)
  end
  return out
end

function M.shuffle(list)
  for i = #list, 2, -1 do
    local j = math.random(i)
    list[i], list[j] = list[j], list[i]
  end
  return list
end

function M.weighted(items, weights) -- random.choices(items, weights)[0]
  local total = 0
  for _, w in ipairs(weights) do total = total + math.max(0, w) end
  if total <= 0 then return items[1] end
  local r = math.random() * total
  for i, w in ipairs(weights) do
    r = r - math.max(0, w)
    if r < 0 then return items[i] end
  end
  return items[#items]
end

function M.fmt(n, decimals) -- "%.Nf"
  return string.format("%." .. (decimals or 0) .. "f", n)
end

return M
