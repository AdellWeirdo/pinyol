-- textures: every picture of the game, drawn by code at 32x32 (a PlayStation's textures were this small, and a quad stays in the memory
-- cache): no files. Each is a canvas the quads and meshes read like any picture.
local M = {}

local seed = 11
local function noise(n) seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF return (seed >> 16) % n end
local function rgb(r, g, b) return math.floor(math.max(0, math.min(255, r))) << 16 | math.floor(math.max(0, math.min(255, g))) << 8 | math.floor(math.max(0, math.min(255, b))) end

local function speckle(w, h, base, spread, n) -- grain over a picture, a few steps lighter or darker
  for _ = 1, n do
    local k = noise(spread * 2 + 1) - spread
    pset(noise(w), noise(h), rgb(base[1] + k, base[2] + k * 0.8, base[3] + k * 0.6))
  end
end

local function fill(id, w, h, c)
  canvas(id, w, h); target(id)
  rect(0, 0, w, h, rgb(c[1], c[2], c[3]))
end

function M.init()
  -- the path: sandy slabs, each edged darker, grain
  fill("TEX_PATH", 32, 32, {176, 136, 82})
  speckle(32, 32, {176, 136, 82}, 14, 260)
  rect(0, 0, 32, 2, rgb(112, 80, 44)) -- a slab's edge, across the way
  rect(0, 30, 32, 2, rgb(206, 166, 106))
  rect(0, 0, 4, 32, rgb(92, 58, 38)); rect(28, 0, 4, 32, rgb(92, 58, 38)) -- the kerbs, down both sides
  rect(4, 0, 1, 32, rgb(214, 176, 118)); rect(27, 0, 1, 32, rgb(214, 176, 118))
  for y = 0, 28, 8 do rect(0, y, 4, 1, rgb(60, 36, 24)); rect(28, y, 4, 1, rgb(60, 36, 24)) end
  -- the path further away, darker: it is drawn with no light (a lit quad costs more than twice as much), so the fog is baked into the picture
  for step, k in ipairs({0.74, 0.5}) do
    canvas("TEX_PATH_" .. step, 32, 32); target("TEX_PATH_" .. step)
    local c = math.floor(k * 255)
    img("TEX_PATH", 0, 0, {mul = c << 16 | c << 8 | c})
  end
  -- a crate: planks, a brace across, nails
  fill("TEX_CRATE", 32, 32, {196, 140, 68})
  speckle(32, 32, {196, 140, 68}, 16, 200)
  for y = 8, 24, 8 do rect(0, y, 32, 1, rgb(110, 70, 30)) end
  rect(0, 0, 32, 3, rgb(120, 76, 34)); rect(0, 29, 32, 3, rgb(120, 76, 34))
  rect(0, 0, 3, 32, rgb(120, 76, 34)); rect(29, 0, 3, 32, rgb(120, 76, 34))
  for i = 3, 28 do pset(i, i, rgb(100, 62, 26)); pset(i + 1, i, rgb(100, 62, 26)); pset(31 - i, i, rgb(100, 62, 26)); pset(30 - i, i, rgb(100, 62, 26)) end
  for _, p in ipairs({{5, 5}, {26, 5}, {5, 26}, {26, 26}}) do rect(p[1], p[2], 2, 2, rgb(230, 210, 160)) end
  -- the fox: orange fur, darker streaks; its white; its dark (legs, ears)
  fill("TEX_FOX", 32, 32, {232, 112, 40})
  speckle(32, 32, {232, 112, 40}, 18, 220)
  for x = 3, 29, 6 do rect(x, 0, 1, 32, rgb(196, 84, 26)) end
  fill("TEX_FOXW", 32, 32, {252, 240, 222})
  speckle(32, 32, {252, 240, 222}, 8, 120)
  fill("TEX_FOXD", 32, 32, {70, 38, 28})
  speckle(32, 32, {70, 38, 28}, 10, 120)
  -- trees: bark, leaves
  fill("TEX_BARK", 32, 32, {96, 62, 36})
  for x = 0, 31, 4 do rect(x, 0, 1 + noise(2), 32, rgb(64, 40, 22)) end
  speckle(32, 32, {96, 62, 36}, 12, 160)
  fill("TEX_LEAF", 32, 32, {40, 112, 58})
  speckle(32, 32, {40, 112, 58}, 26, 420)
  for _ = 1, 14 do local x, y = noise(32), noise(32) line(x, y, x + 4, y + 2, rgb(22, 74, 38)) end
  -- a pit: dark, with a hot rim
  fill("TEX_PIT", 32, 32, {14, 8, 20})
  speckle(32, 32, {14, 8, 20}, 8, 100)
  rect(0, 0, 32, 2, rgb(150, 40, 30)); rect(0, 30, 32, 2, rgb(150, 40, 30))
  -- a spike trap: pale teeth on dark
  fill("TEX_SPIKE", 32, 32, {52, 34, 40})
  for x = 0, 28, 8 do tri(x, 31, x + 8, 31, x + 4, 4, rgb(226, 220, 200)) end
  -- the fruit: a round one, red with a light spot and a leaf
  canvas("SPR_FRUIT", 16, 16); target("SPR_FRUIT")
  rect(0, 0, 16, 16, CLEAR) -- see-through
  circ(8, 9, 6, rgb(224, 56, 42), true); circ(8, 9, 6, rgb(150, 28, 30), false)
  circ(6, 7, 2, rgb(255, 182, 140), true)
  rect(7, 1, 2, 3, rgb(46, 120, 52)); rect(9, 2, 3, 2, rgb(70, 160, 60))
  target()
end

return M
