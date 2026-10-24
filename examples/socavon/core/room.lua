-- room: the room on the screen: 28x16 blocks of 8x8 (and two rows under it for the status). Each block is a picture of two
-- colours and takes its colours from the palette bank of its kind, as the Spectrum's attributes did; the room's scheme (rooms.lua)
-- gives every kind its ink and paper, so the same drawings make eight different looking rooms.
local Rooms = require("rooms")
local Tilepos = require("data.tilepos")
local Z = require("core.zx")
local R = {}

R.W, R.H, R.ROWS = 28, 16, 18
R.BANK = {air = 1, wall = 2, floor = 3, crumble = 4, conveyor = 5, hazard = 6, key = 7, portal = 8, deco = 9}
local KIND_OF = {["#"] = "wall", ["="] = "floor", ["-"] = "crumble", [">"] = "conveyor", ["<"] = "conveyor", ["*"] = "hazard",
                 ["^"] = "hazard", v = "hazard", k = "key", X = "portal", ["."] = "air"}
local DECO = {["1"] = "deco_beam_h", ["2"] = "deco_beam_v", ["3"] = "deco_pipe_h", ["4"] = "deco_pipe_v", l = "deco_lamp",
              w = "deco_web", r = "deco_rail", s = "deco_skull", c = "deco_crystal"}
local THEME = {"a", "b", "c", "d"}

local TILE = {}       -- block name -> its map entry (the tile and any flip), read once from the atlas
R.cells, R.n, R.rm, R.keys, R.open = {}, 0, nil, 0, false
R.attr = {}           -- kind -> {bank, ink, paper}
R.crumbling = {}
R.start = {x = 16, y = 104}

function R.init()
  bg(1, {map = "ROOM", prio = 1, wrap = false})
  for name, p in pairs(Tilepos) do TILE[name] = mget(1, p[1], p[2]) & 0xFFF end -- before the first room overwrites the atlas
end

function R.count() return #Rooms end
function R.tile(name) return TILE[name] end

function R.char(tx, ty)
  if tx < 0 or ty < 0 or tx >= R.W or ty >= R.H then return "#" end
  return R.cells[ty * R.W + tx + 1]
end

function R.kind(c) return KIND_OF[c] or (DECO[c] and "deco") or "air" end
function R.is_solid(c) return c == "#" end
function R.is_ledge(c) return c == "=" or c == "-" or c == ">" or c == "<" end
function R.is_hazard(c) return c == "*" or c == "^" or c == "v" end

local function tile_name(c, tx, ty)
  local L = THEME[R.rm.theme] or "a"
  if c == "#" then return "wall_" .. L end
  if c == "=" then return "floor_" .. L end
  if c == "-" then return "crumble_0" end
  if c == ">" then return "conv_r_0" end
  if c == "<" then return "conv_l_0" end
  if c == "*" then return "plant_a" end
  if c == "^" then return "spike" end
  if c == "v" then return "stalac" end
  if c == "k" then return "key" end
  if c == "X" then
    local top = R.char(tx, ty - 1) ~= "X"
    local left = R.char(tx - 1, ty) ~= "X"
    return (R.open and "portal_open_" or "portal_") .. (top and "t" or "b") .. (left and "l" or "r")
  end
  return DECO[c] or "air"
end

function R.draw(tx, ty, name)
  local c = R.char(tx, ty)
  name = name or tile_name(c, tx, ty)
  local e = TILE[name] or TILE.air
  mset(1, tx, ty, e | (R.BANK[R.kind(c)] << 12))
end

function R.set(tx, ty, c, name)
  R.cells[ty * R.W + tx + 1] = c
  R.draw(tx, ty, name)
end

-- every bank's two colours: the keys (and the open portal) flash, ink and paper swapped, as the FLASH attribute did
function R.colours(flash)
  for kind, a in pairs(R.attr) do
    local ink, paper = a[2], a[3]
    if flash and (kind == "key" or (kind == "portal" and R.open)) then ink, paper = paper, ink end
    pal(a[1] * 16 + 1, ink)
    pal(a[1] * 16 + 2, paper)
    pal(a[1] * 16 + 1, ink, true) -- the sprites' ink in this bank
  end
end

function R.load(n)
  local rm = Rooms[n]
  R.n, R.rm, R.keys, R.open, R.crumbling = n, rm, 0, false, {}
  R.attr = {}
  for kind, bank in pairs(R.BANK) do
    local ink, paper = Z.attr(rm.scheme[kind] or rm.scheme.air)
    R.attr[kind] = {bank, ink, paper}
  end
  R.border = Z.rgb(rm.border or "black", false)
  R.cells = {}
  for ty = 0, R.ROWS - 1 do
    local row = rm.tiles[ty + 1]
    for tx = 0, R.W - 1 do
      local c = row and row:sub(tx + 1, tx + 1) or "."
      if c == "P" then R.start = {x = tx * 8, y = ty * 8} c = "." end
      if c == "k" then R.keys = R.keys + 1 end
      R.cells[ty * R.W + tx + 1] = c
    end
  end
  for ty = 0, R.ROWS - 1 do for tx = 0, R.W - 1 do R.draw(tx, ty) end end
  R.colours(false)
end

-- the room as it stands (keys taken, floors fallen, the portal): the explainer shows rooms and must give this one back as it was
function R.snapshot()
  if not R.rm then return nil end
  local cells, crumbling = {}, {}
  for i, c in ipairs(R.cells) do cells[i] = c end
  for k, v in pairs(R.crumbling) do crumbling[k] = v end
  return {n = R.n, cells = cells, keys = R.keys, open = R.open, crumbling = crumbling}
end

function R.restore(s)
  R.load(s.n)
  for i, c in ipairs(s.cells) do R.cells[i] = c end
  R.keys, R.open, R.crumbling = s.keys, s.open, s.crumbling
  for ty = 0, R.ROWS - 1 do for tx = 0, R.W - 1 do R.draw(tx, ty) end end
  R.colours(false)
end

function R.open_portal()
  R.open = true
  for ty = 0, R.H - 1 do for tx = 0, R.W - 1 do if R.char(tx, ty) == "X" then R.draw(tx, ty) end end end
end

-- the animated blocks: conveyors turn, plants sway
local ANIM = {[">"] = {"conv_r_0", "conv_r_1", "conv_r_2"}, ["<"] = {"conv_l_0", "conv_l_1", "conv_l_2"}, ["*"] = {"plant_a", "plant_b"}}
function R.animate(t)
  local step = t // 6
  for ty = 0, R.H - 1 do
    for tx = 0, R.W - 1 do
      local a = ANIM[R.char(tx, ty)]
      if a then R.draw(tx, ty, a[(step + (R.char(tx, ty) == "*" and tx or 0)) % #a + 1]) end
    end
  end
end

-- the bank (and so the ink) of the block at a pixel of the room: what a sprite takes
function R.ink_bank(px, py)
  local c = R.char(math.floor(px) // 8, math.floor(py) // 8)
  return R.BANK[R.kind(c)]
end

return R
