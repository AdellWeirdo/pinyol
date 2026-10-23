-- spr: the sprites of the frame. Every picture is a frame of a sheet with a name (data/frames.lua), so the game says S.draw("HERO", "walk_3", x, y). The
-- 128 slots are handed out in the order of drawing: the first drawn is in front. S.rects keeps what was drawn so the explainer can count the sprites
-- the way the console would (128 in all, and the cost of a line).
local F = require("data.frames")
local Banks = require("data.banks")
local S = {}

local handles = {}
local slot = 0
S.rects = {}
S.n = 0
S.lines = {} -- sprites on each line, for the explainer

function S.begin()
  spr_clear()
  slot = 0
  S.n = 0
  for i = #S.rects, 1, -1 do S.rects[i] = nil end
end

local function handle(id)
  local h = handles[id]
  if not h then
    h = sheet(id)
    handles[id] = h
  end
  return h
end

function S.has(id, name) return F[id] and F[id][name] ~= nil end
function S.size(id) return F[id].w, F[id].h end

-- S.draw(sheet, frame, x, y [, {flip, prio, bank = "name" or number, blend, mat}]): x, y on the screen (the sprite's top-left)
function S.draw(id, name, x, y, o)
  if slot >= 128 then return end
  local sh = F[id]
  local frame = sh and sh[name]
  if not frame then error("no frame " .. tostring(id) .. "." .. tostring(name), 2) end
  o = o or {}
  local b = o.bank
  if type(b) == "string" then b = Banks.obj[b] end
  local flags = prio(o.prio or 1) | bank(b or (sh.banks and sh.banks[name]) or sh.bank or 0)
  if o.flip then flags = flags | FLIP_X end
  if o.blend then flags = flags | BLEND end
  if o.mat then flags = flags | spr_mat(o.mat) | (o.double and DOUBLE or 0) end
  if o.mosaic then flags = flags | MOSAIC end
  x, y = math.floor(x), math.floor(y)
  if x > 240 or y > 160 or x < -sh.w or y < -sh.h then return end
  local part = frame // 64 -- a sheet of more than 64 frames is kept in pieces (HERO, HERO_2...)
  spr(slot, handle(part == 0 and id or (id .. "_" .. (part + 1))), frame % 64, x, y, flags)
  slot = slot + 1
  S.n = S.n + 1
  S.rects[#S.rects + 1] = {x, y, sh.w, sh.h}
end

function S.slots() return slot end

-- the frame of an animation that has `n` frames, changing every `every` ticks
function S.cycle(prefix, n, t, every)
  return prefix .. "_" .. ((t // every) % n)
end

return S
