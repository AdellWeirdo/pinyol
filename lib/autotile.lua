-- autotile: a map's walls, ground or water drawn with the right tile at every edge and corner, worked out from the
-- neighbours, so a level made by code (caves, a dig, a wall knocked down) looks drawn by hand. Two ways:
--
-- Blob (47 tiles; Boris the Brave, "Tilesets", after cr31's blob): each cell looks at its eight neighbours and
-- picks one of 47 tiles. The tiles come in the order of the standard "blob" bitmask (N 1, NE 2, E 4, SE 8, S 16,
-- SW 32, W 64, NW 128; a corner counts only when both sides next to it are set): give them as a table of 256 entries
-- or, simpler, a function of the bitmask.
--   autotile.blob(layer, w, h, is_solid, tile_of)        -- tile_of(mask) -> tile number; mset on the layer
--
-- Dual grid (16 tiles; jess::codes, "Draw fewer tiles"): the picture's cells sit half a tile off the data's, each
-- showing the corner where four data cells meet, so sixteen tiles (every combination of the four) give rounded
-- corners and single-cell details. The map drawn is (w + 1) x (h + 1).
--   autotile.dual(layer, w, h, is_solid, tiles)           -- tiles[0..15]: the tile for NW | NE << 1 | SW << 2 | SE << 3
--
-- Both take is_solid(tx, ty) -> true for a cell that is the material (outside the map counts as solid, so the edges
-- close), and write the layer with mset. autotile.fix(layer, w, h, is_solid, tile_of, tx, ty) redoes one cell and
-- its neighbours after a change (a block dug out), for either way (blob: pass tile_of; dual: pass tiles).
local M = {}

local function solid_or_outside(is_solid, w, h, tx, ty)
  if tx < 0 or ty < 0 or tx >= w or ty >= h then return true end
  return is_solid(tx, ty) and true or false
end

-- the 8-neighbour mask of a cell, corners counted only when both their sides are set
function M.mask(is_solid, w, h, tx, ty)
  local function s(dx, dy) return solid_or_outside(is_solid, w, h, tx + dx, ty + dy) end
  local n, e, so, we = s(0, -1), s(1, 0), s(0, 1), s(-1, 0)
  local m = 0
  if n then m = m + 1 end
  if n and e and s(1, -1) then m = m + 2 end
  if e then m = m + 4 end
  if e and so and s(1, 1) then m = m + 8 end
  if so then m = m + 16 end
  if so and we and s(-1, 1) then m = m + 32 end
  if we then m = m + 64 end
  if we and n and s(-1, -1) then m = m + 128 end
  return m
end

local function blob_cell(layer, w, h, is_solid, tile_of, tx, ty, empty)
  if not is_solid(tx, ty) then mset(layer, tx, ty, empty or 0) return end
  local m = M.mask(is_solid, w, h, tx, ty)
  mset(layer, tx, ty, type(tile_of) == "function" and tile_of(m) or tile_of[m] or 0)
end

function M.blob(layer, w, h, is_solid, tile_of, empty)
  for ty = 0, h - 1 do
    for tx = 0, w - 1 do blob_cell(layer, w, h, is_solid, tile_of, tx, ty, empty) end
  end
end

-- the 47 distinct blob masks, in cr31's order, for a tileset laid out that way: index(mask) -> 0..46
local BLOB_ORDER = {0, 1, 4, 5, 7, 16, 17, 20, 21, 23, 28, 29, 31, 64, 65, 68, 69, 71, 80, 81, 84, 85, 87, 92, 93, 95,
                    112, 113, 116, 117, 119, 124, 125, 127, 193, 197, 199, 209, 213, 215, 221, 223, 241, 245, 247, 253, 255}
local BLOB_INDEX = {}
for i, m in ipairs(BLOB_ORDER) do BLOB_INDEX[m] = i - 1 end
function M.blob_index(mask) return BLOB_INDEX[mask] end -- 0..46, or nil for a mask that cannot happen

local function dual_cell(layer, w, h, is_solid, tiles, cx, cy)
  local function s(tx, ty) return solid_or_outside(is_solid, w, h, tx, ty) end
  local k = 0 -- the four data cells round the picture cell's centre: NW (cx-1, cy-1), NE (cx, cy-1), SW (cx-1, cy), SE (cx, cy)
  if s(cx - 1, cy - 1) then k = k + 1 end
  if s(cx, cy - 1) then k = k + 2 end
  if s(cx - 1, cy) then k = k + 4 end
  if s(cx, cy) then k = k + 8 end
  mset(layer, cx, cy, tiles[k] or 0)
end

function M.dual(layer, w, h, is_solid, tiles)
  for cy = 0, h do
    for cx = 0, w do dual_cell(layer, w, h, is_solid, tiles, cx, cy) end
  end
end

-- after one data cell changed: the cells it can affect, again
function M.fix(layer, w, h, is_solid, tile_of, tx, ty, dual)
  if dual then
    for cy = ty, ty + 1 do for cx = tx, tx + 1 do dual_cell(layer, w, h, is_solid, tile_of, cx, cy) end end
    return
  end
  for cy = ty - 1, ty + 1 do
    for cx = tx - 1, tx + 1 do
      if cx >= 0 and cy >= 0 and cx < w and cy < h then blob_cell(layer, w, h, is_solid, tile_of, cx, cy) end
    end
  end
end

return M
