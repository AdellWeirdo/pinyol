-- textures: every picture of the game, drawn by code at 32x32 (a PlayStation's were this small): no files.
local M = {}

local seed = 5
local function noise(n) seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF return (seed >> 16) % n end
local function rgb(r, g, b) return math.floor(math.max(0, math.min(255, r))) << 16 | math.floor(math.max(0, math.min(255, g))) << 8 | math.floor(math.max(0, math.min(255, b))) end

local function fill(id, c)
  canvas(id, 32, 32); target(id)
  rect(0, 0, 32, 32, rgb(c[1], c[2], c[3]))
end
local function speckle(base, spread, n)
  for _ = 1, n do
    local k = noise(spread * 2 + 1) - spread
    pset(noise(32), noise(32), rgb(base[1] + k, base[2] + k, base[3] + k * 1.1))
  end
end
local function crack(c, n)
  for _ = 1, n do
    local x, y = noise(32), noise(32)
    for _ = 1, 5 + noise(6) do
      pset(x, y, rgb(c[1], c[2], c[3]))
      x, y = (x + noise(3) - 1) % 32, (y + noise(3) - 1) % 32
    end
  end
end

function M.init()
  -- asphalt: dark, wet, cracked, with the kerb's paint at both edges
  fill("TEX_ASPHALT", {70, 74, 84}); speckle({70, 74, 84}, 14, 300); crack({38, 40, 48}, 5)
  rect(0, 0, 32, 1, rgb(150, 130, 60)); rect(0, 31, 32, 1, rgb(150, 130, 60))
  rect(15, 0, 2, 7, rgb(170, 168, 150)); rect(15, 14, 2, 7, rgb(170, 168, 150)); rect(15, 26, 2, 6, rgb(170, 168, 150))
  -- the plaza's paving: slabs
  fill("TEX_PAVING", {96, 98, 100}); speckle({96, 98, 100}, 12, 260)
  for i = 0, 28, 8 do rect(i, 0, 1, 32, rgb(58, 60, 64)); rect(0, i, 32, 1, rgb(58, 60, 64)) end
  -- the pier: planks
  fill("TEX_PLANK", {104, 80, 56}); speckle({104, 80, 56}, 14, 200)
  for y = 0, 28, 6 do rect(0, y, 32, 1, rgb(54, 38, 26)) end
  for _ = 1, 8 do rect(noise(28), noise(5) * 6 + 1, 3, 1, rgb(140, 112, 80)) end
  -- metal: a car's body, a lamp's post
  fill("TEX_METAL", {58, 70, 82}); speckle({58, 70, 82}, 10, 160); rect(0, 14, 32, 1, rgb(90, 104, 118))
  fill("TEX_RUST", {96, 62, 46}); speckle({96, 62, 46}, 16, 260)
  -- glass that glows (a lamp's), a window of a car
  fill("TEX_LAMP", {255, 230, 160}); rect(4, 4, 24, 24, rgb(255, 246, 210))
  fill("TEX_GLASS", {28, 36, 46}); rect(2, 2, 12, 12, rgb(46, 60, 76))
  -- stone: the fountain, the lighthouse
  fill("TEX_STONE", {110, 112, 112}); speckle({110, 112, 112}, 16, 280); crack({70, 72, 72}, 4)
  fill("TEX_LIGHTHOUSE", {200, 196, 190})
  for x = 0, 31 do for y = 0, 31 do if (y // 8) % 2 == 0 then pset(x, y, rgb(196, 54, 48)) end end end
  speckle({200, 196, 190}, 8, 80)
  -- wood: a bench, a door with its brass
  fill("TEX_WOOD", {92, 66, 44}); speckle({92, 66, 44}, 14, 200); for y = 4, 28, 8 do rect(0, y, 32, 1, rgb(50, 34, 22)) end
  fill("TEX_DOOR", {74, 46, 34}); speckle({74, 46, 34}, 10, 160)
  rect(2, 2, 12, 26, rgb(60, 36, 26)); rect(18, 2, 12, 26, rgb(60, 36, 26)); rect(13, 14, 3, 3, rgb(210, 170, 70))
  -- people: a coat, skin, hair
  fill("TEX_COAT", {52, 82, 96}); speckle({52, 82, 96}, 10, 180); rect(15, 0, 2, 32, rgb(34, 54, 66))
  fill("TEX_SKIN", {214, 170, 140}); speckle({214, 170, 140}, 8, 80)
  fill("TEX_HAIR", {40, 30, 26}); speckle({40, 30, 26}, 8, 80)
  fill("TEX_JEANS", {44, 56, 88}); speckle({44, 56, 88}, 8, 120)
  -- the Figure: pale grey, streaked, with dark hollows
  fill("TEX_FIGURE", {176, 176, 170}); speckle({176, 176, 170}, 14, 240)
  for x = 2, 30, 5 do rect(x, 0, 1, 32, rgb(120, 122, 118)) end
  fill("TEX_HOLLOW", {18, 16, 20}); speckle({18, 16, 20}, 6, 60)
  -- the key
  fill("TEX_GOLD", {230, 190, 70}); rect(0, 0, 32, 4, rgb(255, 230, 130))
  target()
end

return M
