-- textures: every picture of the game, drawn by code at 32x32: no files.
local M = {}
local seed = 9
local function noise(n) seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF return (seed >> 16) % n end
local function rgb(r, g, b) return math.floor(math.max(0, math.min(255, r))) << 16 | math.floor(math.max(0, math.min(255, g))) << 8 | math.floor(math.max(0, math.min(255, b))) end

local function fill(id, c, grain)
  canvas(id, 32, 32); target(id)
  rect(0, 0, 32, 32, rgb(c[1], c[2], c[3]))
  for _ = 1, grain or 120 do
    local k = noise(17) - 8
    pset(noise(32), noise(32), rgb(c[1] + k, c[2] + k, c[3] + k))
  end
end

function M.init()
  -- the suits: a coat, with a fold across it and a seam down it
  for name, c in pairs({RED = {196, 52, 56}, BLUE = {58, 96, 190}}) do
    fill("TEX_GI_" .. name, c, 160)
    rect(15, 0, 2, 32, rgb(c[1] * 0.7, c[2] * 0.7, c[3] * 0.7))
    rect(0, 24, 32, 8, rgb(235, 226, 190)); rect(0, 24, 32, 1, rgb(150, 140, 110)) -- the belt, at the foot of the coat
    fill("TEX_PANTS_" .. name, {c[1] * 0.45, c[2] * 0.45, c[3] * 0.45}, 140)
    fill("TEX_BELT_" .. name, {235, 226, 190}, 60); rect(0, 12, 32, 8, rgb(c[1], c[2], c[3]))
  end
  fill("TEX_SKIN_A", {226, 178, 140}, 80); fill("TEX_SKIN_B", {176, 124, 92}, 80)
  fill("TEX_HAIR_A", {34, 26, 22}, 40); fill("TEX_HAIR_B", {210, 190, 90}, 40)
  fill("TEX_SHOE", {40, 36, 44}, 60); rect(0, 24, 32, 8, rgb(230, 230, 230))
  fill("TEX_GLOVE_RED", {240, 220, 200}, 40); fill("TEX_GLOVE_BLUE", {240, 220, 200}, 40)
  -- a face: eyes on the side the fighter looks to (the head's front is +x)
  fill("TEX_FACE_A", {226, 178, 140}, 80); rect(0, 0, 32, 9, rgb(34, 26, 22)); rect(20, 12, 5, 4, rgb(250, 250, 250)); rect(22, 13, 3, 3, rgb(30, 30, 40)); rect(18, 23, 10, 2, rgb(150, 60, 60))
  fill("TEX_FACE_B", {176, 124, 92}, 80); rect(0, 0, 32, 9, rgb(210, 190, 90)); rect(20, 12, 5, 4, rgb(250, 250, 250)); rect(22, 13, 3, 3, rgb(30, 30, 40)); rect(18, 23, 10, 2, rgb(120, 40, 50))
  fill("TEX_SHADOW", {24, 18, 28}, 10)
  target()
end

return M
