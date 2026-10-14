-- Grids (src/lua_grid.c), checked by tests/grid.script: walls (#), mud that costs 3 (~), open floor (.).
MAP = {
  "..........",
  ".####..~~.",
  "....#..~~.",
  ".##.#.###.",
  "....#...#.",
  ".#....#.#.",
  "......#...",
}
g = grid(10, 7)
for y, row in ipairs(MAP) do
  for x = 1, 10 do
    local c = row:sub(x, x)
    g:set(x - 1, y - 1, c == "#" and 0 or c == "~" and 3 or 1)
  end
end

-- a path is good if each step is to a neighbour (4 ways, or 8), never a wall, and ends at the goal
function good(path, x0, y0, x1, y1, diag)
  local x, y = x0, y0
  for _, p in ipairs(path) do
    local dx, dy = math.abs(p[1] - x), math.abs(p[2] - y)
    if (diag and (dx > 1 or dy > 1)) or (not diag and dx + dy ~= 1) or g:get(p[1], p[2]) == 0 then return false end
    x, y = p[1], p[2]
  end
  return x == x1 and y == y1
end

function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

function _init() show(0) end
function _update() end
function _draw()
  cls(0x101418)
  for y, row in ipairs(MAP) do
    for x = 1, 10 do
      local c = row:sub(x, x)
      rect(40 + (x - 1) * 40, 20 + (y - 1) * 40, 38, 38, c == "#" and 0x505860 or c == "~" and 0x6A4A2A or 0x203040)
    end
  end
  if shown then
    for _, p in ipairs(shown) do circ(60 + p[1] * 40, 40 + p[2] * 40, 8, 0xFFE070) end
  end
end
