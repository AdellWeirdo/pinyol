-- ents: everything that moves and is drawn: the hero, people, enemies, shots, things on the ground. Each is a table
-- with a `kind`, `x`, `y` (its sprite's top-left, in the area's pixels) and optional `update(self)` and `draw(self)`.
local E = {}

E.list = {}
E.hero = nil
local next_id = 0

function E.add(e)
  next_id = next_id + 1
  e.eid = next_id
  E.list[#E.list + 1] = e
  return e
end

function E.remove(e) e.dead = true end

-- clears everything but the hero (a new screen, a new area)
function E.clear(keep)
  local out = {}
  for _, e in ipairs(E.list) do if keep and keep(e) then out[#out + 1] = e end end
  E.list = out
end

function E.update()
  for i = 1, #E.list do
    local e = E.list[i]
    if e.update and not e.dead then e:update() end
  end
  local out = {}
  for _, e in ipairs(E.list) do if not e.dead then out[#out + 1] = e end end
  E.list = out
end

function E.each(kind)
  local i = 0
  return function()
    while true do
      i = i + 1
      local e = E.list[i]
      if not e then return nil end
      if (kind == nil or e.kind == kind) and not e.dead then return e end
    end
  end
end

function E.count(kind)
  local n = 0
  for e in E.each(kind) do n = n + 1 end
  return n
end

-- the nearest-to-the-bottom first: that one is drawn first, so it takes the sprite slot that is in front
local function key(e) return (e.y or 0) + (e.sort or 15) end
function E.draw()
  local order = {}
  for _, e in ipairs(E.list) do if e.draw and not e.dead and not e.hidden then order[#order + 1] = e end end
  table.sort(order, function(a, b)
    local ka, kb = key(a), key(b)
    if ka ~= kb then return ka > kb end
    return a.eid < b.eid
  end)
  for _, e in ipairs(order) do e:draw() end
end

-- the first entity that is solid and touches the box, other than `ignore`
function E.solid_at(x, y, w, h, ignore)
  for _, e in ipairs(E.list) do
    if e.solid and e ~= ignore and not e.dead then
      local bx, by, bw, bh = e.x + (e.hx or 0), e.y + (e.hy or 0), e.hw or 16, e.hh or 16
      if x < bx + bw and bx < x + w and y < by + bh and by < y + h then return e end
    end
  end
  return nil
end

return E
