-- world: the map the hero walks on. An area is a grid of screens; each metatile has an id into the tileset, and the
-- tileset says what it does (solid, water, cut, dig, door...). The ground and the front layer (what the hero walks
-- behind: a tree's top, a roof's edge) are two tile layers the console scrolls; changing a cell (a cut bush, a dug
-- hole) changes four tiles of each with mset, and is kept in `changes` to be saved.
local C = require("core.const")
local Areas = require("data.world").areas
local Tiles = require("data.tiles")
local Game = require("core.game")
local W = {}

W.area, W.aid, W.cells, W.ts = nil, nil, nil, nil
W.sx, W.sy = 0, 0       -- the screen being shown (screens of the area, from 0)
W.cam_x, W.cam_y = 0, 0 -- the area's pixel at the playfield's top-left corner
W.shake_x, W.shake_y = 0, 0
-- what has been cut, dug, opened is Game.changes ([area id] = {[cell index] = metatile name}), so it is saved and starts again with the game

local flag_cache = {}   -- [tileset][id] = {solid = true, becomes = "grass_a"...}
local names = {}        -- [tileset][id] = name
local anim_cells = {}   -- ["sx,sy"] = {[anim name] = {cell indexes}}
local anim_state = {}   -- [anim name] = frame index now

local function tileset_info(ts)
  if not flag_cache[ts] then
    local set = Tiles.sets[ts]
    local fl, nm = {}, {}
    for name, id in pairs(set.id) do
      nm[id] = name
      local f = {}
      for _, s in ipairs(set.flags[name] or {}) do
        local k, v = s:match("^(.-)=(.*)$")
        if k then f[k] = v else f[s] = true end
      end
      fl[id] = f
    end
    flag_cache[ts], names[ts] = fl, nm
  end
  return flag_cache[ts], names[ts]
end

local EMPTY = {}

function W.flags_of(id) return (id and W.flag_table[id]) or EMPTY end
function W.name_of(id) return W.names[id] end
function W.id_of(name) return W.ts.id[name] end

function W.index(gx, gy) return gy * W.area.gw + gx + 1 end

-- the metatile id at a cell, or nil outside the area
function W.cell(gx, gy)
  local a = W.area
  if gx < 0 or gy < 0 or gx >= a.gw or gy >= a.gh then return nil end
  return W.cells[gy * a.gw + gx + 1]
end

function W.cell_flags(gx, gy)
  local id = W.cell(gx, gy)
  if not id then return nil end
  return W.flag_table[id] or EMPTY
end

local function put(layer, gx, gy, e4)
  local tx, ty = gx * 2, gy * 2
  for i = 0, 3 do mset(layer, tx + i % 2, ty + i // 2, e4 and e4[i + 1] or 0) end
end

-- shows metatile `name` at a cell (ground, and front if it has one); cell data and map agree
function W.show(gx, gy, name)
  put(1, gx, gy, W.ts.ground[name])
  put(2, gx, gy, W.ts.front[name])
end

-- changes a cell for good (it is kept in `changes`)
function W.set(gx, gy, name)
  local idx = W.index(gx, gy)
  W.cells[idx] = W.ts.id[name]
  Game.changes[W.aid] = Game.changes[W.aid] or {}
  Game.changes[W.aid][idx] = name
  W.show(gx, gy, name)
end

-- does the box (area pixels) touch a cell with that flag? returns the first cell: gx, gy, id
function W.touching(x, y, w, h, flag)
  local x0, y0 = math.floor(x / C.T), math.floor(y / C.T)
  local x1, y1 = math.floor((x + w - 1) / C.T), math.floor((y + h - 1) / C.T)
  for gy = y0, y1 do
    for gx = x0, x1 do
      local f = W.cell_flags(gx, gy)
      if f and f[flag] then return gx, gy, W.cell(gx, gy) end
    end
  end
  return nil
end

-- blocked: outside the area, or on a cell that is solid or deep water
function W.blocked(x, y, w, h)
  local x0, y0 = math.floor(x / C.T), math.floor(y / C.T)
  local x1, y1 = math.floor((x + w - 1) / C.T), math.floor((y + h - 1) / C.T)
  for gy = y0, y1 do
    for gx = x0, x1 do
      local f = W.cell_flags(gx, gy)
      if not f or f.solid or f.water then return true end
    end
  end
  return false
end

-- ------------------------------------------------------------------ loading an area

-- the tile layers of an area, with the changes made so far put back
function W.load(aid, sx, sy)
  local a = Areas[aid]
  assert(a, "no area " .. tostring(aid))
  W.area, W.aid, W.ts = a, aid, Tiles.sets[a.tileset]
  W.flag_table, W.names = tileset_info(a.tileset)
  W.cells = {}
  for i = 1, #a.cells do W.cells[i] = a.cells[i] end
  bg(1, {map = a.ground, prio = 2, wrap = false, pal = false})
  bg(2, {map = a.front, prio = 0, wrap = false, pal = false})
  for idx, name in pairs(Game.changes[aid] or {}) do
    local gx, gy = (idx - 1) % a.gw, (idx - 1) // a.gw
    W.cells[idx] = W.ts.id[name]
    W.show(gx, gy, name)
  end
  -- animated metatiles: which cells of each screen have them
  anim_cells, anim_state = {}, {}
  for an, def in pairs(Tiles.anim) do
    local first = {}
    for k, n in ipairs(def.frames) do first[W.ts.id[n] or -1] = k end
    for idx = 1, #W.cells do
      if first[W.cells[idx]] then
        local gx, gy = (idx - 1) % a.gw, (idx - 1) // a.gw
        local key = (gx // C.SW) .. "," .. (gy // C.SH)
        anim_cells[key] = anim_cells[key] or {}
        anim_cells[key][an] = anim_cells[key][an] or {}
        table.insert(anim_cells[key][an], idx)
      end
    end
    anim_state[an] = 1
  end
  W.set_screen(sx or 0, sy or 0)
end

function W.set_screen(sx, sy)
  W.sx, W.sy = sx, sy
  W.cam_x, W.cam_y = sx * C.PW, sy * C.PH
  W.sync_anim(sx, sy)
end

-- the animated cells of a screen show the frame the world is on
function W.sync_anim(sx, sy)
  local list = anim_cells[sx .. "," .. sy]
  if not list then return end
  for an, idxs in pairs(list) do
    local frames = Tiles.anim[an].frames
    local name = frames[anim_state[an]]
    for _, idx in ipairs(idxs) do
      local gx, gy = (idx - 1) % W.area.gw, (idx - 1) // W.area.gw
      if not (Game.changes[W.aid] and Game.changes[W.aid][idx]) then put(1, gx, gy, W.ts.ground[name]) end
    end
  end
end

-- the screens that are shown right now (one, or two while the camera slides between them)
function W.update(t, extra_screens)
  for an, def in pairs(Tiles.anim) do
    local frame = (t // def.ticks) % #def.frames + 1
    if frame ~= anim_state[an] then
      anim_state[an] = frame
      W.sync_anim(W.sx, W.sy)
      if extra_screens then for _, s in ipairs(extra_screens) do W.sync_anim(s[1], s[2]) end end
    end
  end
end

-- the console's scroll: the map pixel at the screen's top-left (the status bar covers the first 16 rows)
function W.scroll()
  scroll(1, W.cam_x + W.shake_x, W.cam_y - C.HUD + W.shake_y)
  scroll(2, W.cam_x + W.shake_x, W.cam_y - C.HUD + W.shake_y)
end

function W.screen_of(x, y) return math.floor(x / C.PW), math.floor(y / C.PH) end

-- an area's pixel to the screen's
function W.to_screen(x, y) return x - W.cam_x, y - W.cam_y + C.HUD end

function W.exists(sx, sy)
  local a = W.area
  return sx >= 0 and sy >= 0 and sx < a.sw and sy < a.sh
end

return W
