-- ui: the layer of tiles on top of everything (the Game Boy's "window"): the status bar, the dialogue window, menus.
-- It is a 30x20 map of the `ui` tileset that the game fills with mset, so it uses the palette like any other tile.
local Tiles = require("data.tiles")
local U = {}

local set = Tiles.sets.ui

function U.init()
  bg(0, {map = "UI", prio = 0, wrap = false, pal = false})
  scroll(0, 0, 0)
end

-- the map entry of an 8x8 tile of the ui tileset
function U.tile(name)
  local e = set.tile8[name]
  if not e then error("no ui tile " .. tostring(name), 2) end
  return e
end

function U.set(tx, ty, name) mset(0, tx, ty, name and U.tile(name) or 0) end

-- a 16x16 metatile of the ui tileset at tile cell tx, ty (four tiles)
function U.meta(tx, ty, name)
  local e = set.ground[name]
  if not e then error("no ui metatile " .. tostring(name), 2) end
  for i = 0, 3 do mset(0, tx + i % 2, ty + i // 2, e[i + 1]) end
end

function U.fill(tx, ty, w, h, name)
  local e = name and U.tile(name) or 0
  for y = ty, ty + h - 1 do for x = tx, tx + w - 1 do mset(0, x, y, e) end end
end

-- a framed window of w x h tiles: the corners, the edges and a plain inside
function U.window(tx, ty, w, h)
  U.fill(tx + 1, ty + 1, w - 2, h - 2, "dlg_fill")
  for x = tx + 1, tx + w - 2 do U.set(x, ty, "dlg_t") U.set(x, ty + h - 1, "dlg_b") end
  for y = ty + 1, ty + h - 2 do U.set(tx, y, "dlg_l") U.set(tx + w - 1, y, "dlg_r") end
  U.set(tx, ty, "dlg_tl") U.set(tx + w - 1, ty, "dlg_tr") U.set(tx, ty + h - 1, "dlg_bl") U.set(tx + w - 1, ty + h - 1, "dlg_br")
end

function U.clear(tx, ty, w, h) U.fill(tx, ty, w, h, nil) end

return U
