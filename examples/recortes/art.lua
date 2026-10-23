-- art: every picture of the game, drawn by code as paper cut-outs: a coloured shape with a white cut line round it (the paper's edge), on a see-through
-- canvas. A part is drawn once; puppet.lua puts it on four corners wherever it should be and turns it, so the same picture serves every pose.
local M = {}

local function rgb(r, g, b) return r << 16 | g << 8 | b end
local WHITE, INK = 0xFFFFFF, 0x2A2030

-- a canvas the size of a part, see-through
local function part(id, w, h)
  canvas(id, w, h); target(id)
  rect(0, 0, w, h, CLEAR)
end

-- a paper oval with its cut line: white first, the colour inside
local function oval(cx, cy, rx, ry, col, edge)
  local k = edge or 2
  for y = -ry - k, ry + k do
    local fy = y / (ry + k)
    local hw = math.floor((rx + k) * math.sqrt(math.max(0, 1 - fy * fy)))
    rect(cx - hw, cy + y, hw * 2 + 1, 1, WHITE)
  end
  for y = -ry, ry do
    local fy = y / ry
    local hw = math.floor(rx * math.sqrt(math.max(0, 1 - fy * fy)))
    rect(cx - hw, cy + y, hw * 2 + 1, 1, col)
  end
end

local function slab(x, y, w, h, col, edge)
  local k = edge or 2
  rect(x - k, y - k, w + k * 2, h + k * 2, WHITE)
  rect(x, y, w, h, col)
end

function M.init()
  -- the teacher: a frog
  local G, G2, YEL = rgb(86, 170, 82), rgb(58, 128, 62), rgb(244, 226, 120)
  part("P_SAPO_BODY", 40, 44); oval(20, 24, 15, 18, G); oval(20, 28, 9, 12, YEL, 0); slab(14, 8, 12, 5, rgb(200, 50, 60), 1); rect(19, 8, 2, 5, rgb(120, 20, 30))
  part("P_SAPO_HEAD", 48, 36); oval(24, 18, 20, 13, G); oval(11, 8, 7, 7, G); oval(37, 8, 7, 7, G)
  circ(11, 8, 4, WHITE, true); circ(37, 8, 4, WHITE, true); circ(12, 9, 2, INK, true); circ(36, 9, 2, INK, true)
  rect(9, 22, 30, 2, rgb(150, 40, 50)); rect(13, 17, 22, 1, G2)
  box(4, 3, 14, 10, INK); box(30, 3, 14, 10, INK); rect(18, 7, 12, 1, INK)
  part("P_SAPO_HEAD_O", 48, 36); oval(24, 18, 20, 13, G); oval(11, 8, 7, 7, G); oval(37, 8, 7, 7, G)
  circ(11, 8, 4, WHITE, true); circ(37, 8, 4, WHITE, true); circ(12, 9, 2, INK, true); circ(36, 9, 2, INK, true)
  oval(24, 24, 11, 6, rgb(150, 40, 50), 0); rect(16, 20, 16, 2, rgb(240, 230, 220))
  box(4, 3, 14, 10, INK); box(30, 3, 14, 10, INK); rect(18, 7, 12, 1, INK)
  part("P_SAPO_ARM", 12, 30); slab(3, 2, 6, 24, G); oval(6, 27, 4, 3, G2)
  part("P_SAPO_LEG", 16, 26); slab(5, 2, 7, 16, G); oval(7, 21, 7, 3, G2)
  part("P_STICK", 8, 56); slab(2, 2, 3, 50, rgb(150, 100, 56), 1); oval(3, 51, 3, 3, rgb(220, 70, 60), 1)

  -- the player: a rabbit
  local W2, PK, BL = rgb(246, 240, 232), rgb(244, 170, 186), rgb(70, 110, 190)
  part("P_LILA_BODY", 36, 40); oval(18, 22, 13, 15, W2); slab(8, 16, 20, 18, BL, 1); rect(17, 16, 2, 18, rgb(40, 70, 140)); circ(18, 26, 1, rgb(250, 220, 90), true)
  part("P_LILA_HEAD", 40, 34); oval(20, 18, 16, 13, W2); circ(13, 14, 2, INK, true); circ(27, 14, 2, INK, true)
  oval(10, 21, 3, 2, PK, 0); oval(30, 21, 3, 2, PK, 0); rect(19, 19, 2, 2, PK); rect(16, 24, 8, 1, INK)
  part("P_LILA_HEAD_O", 40, 34); oval(20, 18, 16, 13, W2); circ(13, 14, 2, INK, true); circ(27, 14, 2, INK, true)
  oval(10, 21, 3, 2, PK, 0); oval(30, 21, 3, 2, PK, 0); rect(19, 19, 2, 2, PK); oval(20, 25, 5, 4, rgb(150, 40, 60), 0)
  part("P_LILA_EAR", 14, 44); oval(7, 22, 5, 19, W2); oval(7, 23, 2, 14, PK, 0)
  part("P_LILA_ARM", 12, 26); slab(3, 2, 6, 20, W2); oval(6, 23, 4, 3, W2)
  part("P_LILA_LEG", 16, 26); slab(5, 2, 7, 15, W2); oval(8, 21, 7, 3, W2)

  part("P_SHADOW", 64, 16); for y = -8, 7 do local hw = math.floor(31 * math.sqrt(math.max(0, 1 - (y / 8) ^ 2))) rect(32 - hw, 8 + y, hw * 2 + 1, 1, 0xA2703F) end
  -- the stage: boards, a curtain fold, a spotlight's cone, a paper note, a bubble
  part("P_NOTE", 24, 24); circ(12, 12, 10, WHITE, true); circ(12, 12, 8, rgb(250, 200, 70), true)
  part("P_BUBBLE", 64, 32); oval(32, 14, 30, 12, WHITE, 0); tri(16, 22, 30, 22, 14, 31, WHITE, true)
  part("P_FLOOR", 32, 32); rect(0, 0, 32, 32, rgb(190, 140, 90)); for i = 0, 28, 8 do rect(0, i, 32, 1, rgb(120, 84, 52)) end
  rect(0, 0, 2, 32, rgb(120, 84, 52)); rect(16, 0, 2, 32, rgb(120, 84, 52))
  part("P_CURTAIN", 32, 32); rect(0, 0, 32, 32, rgb(176, 48, 62))
  for x = 0, 28, 8 do rect(x, 0, 3, 32, rgb(130, 30, 46)); rect(x + 3, 0, 2, 32, rgb(210, 80, 90)) end
  -- the wall of the set and the paper hills, as the PPU's layers (240x160, doubled): the sky's wall, and two ridges that slide
  canvas("BG_WALL", 240, 160); target("BG_WALL")
  grad(0, 0, 240, 160, 0xFCE4A8, 0xF0A070, {dither = true})
  for i = 0, 6 do circ(20 + i * 36, 18 + (i % 2) * 10, 14, 0xFFF6D8, true) end -- paper clouds
  -- the stage's floor: boards that run toward the audience
  rect(0, 127, 240, 33, 0xC08C5A)
  rect(0, 127, 240, 2, 0x8A5E38)
  for i = 0, 240, 20 do line(120 + (i - 120) * 0.35, 127, i, 160, 0x8A5E38) end
  line(0, 142, 240, 142, 0x9C6E44); line(0, 154, 240, 154, 0x9C6E44)
  canvas("BG_FG", 240, 160); target("BG_FG")
  rect(0, 0, 240, 160, CLEAR)
  for _, x0 in ipairs({0, 222}) do -- the two curtains, folds and all
    rect(x0, 0, 18, 160, 0xB0303E)
    for k = 0, 14, 5 do rect(x0 + k, 0, 2, 160, 0x7E1E2E); rect(x0 + k + 2, 0, 1, 160, 0xD85060) end
  end
  rect(0, 0, 240, 11, 0x8E2434) -- the valance
  for x = 0, 240, 16 do tri(x, 11, x + 16, 11, x + 8, 19, 0x8E2434, true) end
  canvas("BG_HILLS", 240, 160); target("BG_HILLS")
  rect(0, 0, 240, 160, CLEAR)
  local pts = {0, 160}
  for x = 0, 240, 12 do pts[#pts + 1] = x; pts[#pts + 1] = 96 + math.floor(10 * math.sin(x / 240 * math.pi * 4)) end
  pts[#pts + 1] = 240; pts[#pts + 1] = 160
  poly(pts, 0x6CB4A0, true)
  canvas("BG_HILLS2", 240, 160); target("BG_HILLS2")
  rect(0, 0, 240, 160, CLEAR)
  pts = {0, 160}
  for x = 0, 240, 12 do pts[#pts + 1] = x; pts[#pts + 1] = 112 + math.floor(8 * math.sin(x / 240 * math.pi * 6 + 1)) end
  pts[#pts + 1] = 240; pts[#pts + 1] = 160
  poly(pts, 0x4C8C80, true)
  target()
end

return M
