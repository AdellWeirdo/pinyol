-- rules: the rules of Tumba, the same as gen/rules.py (which finds each level's par); tests/tumba.script plays those solutions
-- through this to prove the two agree. A level is 16x16 cells of characters (see gen/rules.py); a state is the hero's cell and what he
-- has taken. `slide` runs one move and says what the hero passed through, step by step, so the game can animate it.
local R = {}

R.N = 16
local DIRS = {U = {0, -1}, D = {0, 1}, L = {-1, 0}, R = {1, 0}}
local GATE = {u = "U", d = "D", l = "L", r = "R"}
R.DIRS = DIRS

-- a level from its rows: {g = grid (a table of rows of characters we can change), start, pads, gems = list, ...}
function R.new(rows)
  local lv = {g = {}, pads = {}, gems = {}, gem_index = {}, cracks = {}, crack_index = {}, doors = {}, door_index = {},
              keys = {}, key_index = {}}
  for y = 1, R.N do
    lv.g[y] = {}
    for x = 1, R.N do
      local c = rows[y]:sub(x, x)
      if c == "S" then lv.start = {x - 1, y - 1} c = "." end
      if c == "1" or c == "2" then lv.pads[c] = lv.pads[c] or {} table.insert(lv.pads[c], {x - 1, y - 1}) end
      if c == "o" then lv.gems[#lv.gems + 1] = {x - 1, y - 1} lv.gem_index[(y - 1) * R.N + x - 1] = #lv.gems - 1 end
      if c == "c" then lv.cracks[#lv.cracks + 1] = {x - 1, y - 1} lv.crack_index[(y - 1) * R.N + x - 1] = #lv.cracks - 1 end
      if c == "D" then lv.doors[#lv.doors + 1] = {x - 1, y - 1} lv.door_index[(y - 1) * R.N + x - 1] = #lv.doors - 1 end
      if c == "k" then lv.keys[#lv.keys + 1] = {x - 1, y - 1} lv.key_index[(y - 1) * R.N + x - 1] = #lv.keys - 1 end
      lv.g[y][x] = c
    end
  end
  return lv
end

function R.cell(lv, x, y) return lv.g[y + 1][x + 1] end

function R.initial(lv)
  return {x = lv.start[1], y = lv.start[2], gems = 0, keys_held = 0, cracks = 0, doors = 0, keys = 0}
end

function R.copy(st)
  return {x = st.x, y = st.y, gems = st.gems, keys_held = st.keys_held, cracks = st.cracks, doors = st.doors, keys = st.keys}
end

function R.all_gems(lv, st) return st.gems == (1 << #lv.gems) - 1 end

-- the cell now (a gem taken, a crack broken, a door opened, a key taken are floor)
function R.now(lv, st, x, y)
  local c = lv.g[y + 1][x + 1]
  local k = y * R.N + x
  if c == "o" and (st.gems >> lv.gem_index[k]) & 1 == 1 then return "." end
  if c == "c" and (st.cracks >> lv.crack_index[k]) & 1 == 1 then return "." end
  if c == "D" and (st.doors >> lv.door_index[k]) & 1 == 1 then return "." end
  if c == "k" and (st.keys >> lv.key_index[k]) & 1 == 1 then return "." end
  return c
end

-- one move in direction d from state st. Returns result ("moved", "dead", "win", "none"), the new state, the steps and the events.
-- steps: a list of {x, y, teleport = true?} the hero goes through; events: {kind, x, y}: gem key door crack mud tele gate
function R.slide(lv, st, d)
  local s = R.copy(st)
  local dx, dy = DIRS[d][1], DIRS[d][2]
  local steps, ev = {}, {}
  local x, y = s.x, s.y
  local all = R.all_gems(lv, s)
  local tele_used = false -- a slide teleports once
  while true do
    local nx, ny = x + dx, y + dy
    if nx < 0 or nx >= R.N or ny < 0 or ny >= R.N then break end
    local c = R.now(lv, s, nx, ny)
    local k = ny * R.N + nx
    if c == "#" then break end
    if c == "c" then
      s.cracks = s.cracks | (1 << lv.crack_index[k])
      ev[#ev + 1] = {"crack", nx, ny, #steps}
      break
    end
    if c == "D" then
      if s.keys_held > 0 then
        s.keys_held = s.keys_held - 1
        s.doors = s.doors | (1 << lv.door_index[k])
        ev[#ev + 1] = {"door", nx, ny, #steps}
      else
        break
      end
    end
    if c == "E" and not all then break end
    if GATE[c] then
      if GATE[c] ~= d then break end
      ev[#ev + 1] = {"gate", nx, ny, #steps}
    end
    x, y = nx, ny
    steps[#steps + 1] = {x, y}
    if c == "^" then
      ev[#ev + 1] = {"dead", x, y, #steps}
      return "dead", s, steps, ev
    end
    if c == "o" then
      s.gems = s.gems | (1 << lv.gem_index[k])
      ev[#ev + 1] = {"gem", x, y, #steps}
      all = R.all_gems(lv, s)
    end
    if c == "k" then
      s.keys = s.keys | (1 << lv.key_index[k])
      s.keys_held = s.keys_held + 1
      ev[#ev + 1] = {"key", x, y, #steps}
    end
    if c == "E" then
      s.x, s.y = x, y
      ev[#ev + 1] = {"win", x, y, #steps}
      return "win", s, steps, ev
    end
    if c == "m" then
      ev[#ev + 1] = {"mud", x, y, #steps}
      break
    end
    if (c == "1" or c == "2") and not tele_used then
      tele_used = true
      local a, b = lv.pads[c][1], lv.pads[c][2]
      local to = (x == a[1] and y == a[2]) and b or a
      x, y = to[1], to[2]
      steps[#steps + 1] = {x, y, teleport = true}
      ev[#ev + 1] = {"tele", x, y, #steps}
    end
  end
  s.x, s.y = x, y
  local same = s.x == st.x and s.y == st.y and s.gems == st.gems and s.keys_held == st.keys_held and s.cracks == st.cracks
               and s.doors == st.doors and s.keys == st.keys
  if same and #ev == 0 then return "none", s, steps, ev end
  return "moved", s, steps, ev
end

return R
