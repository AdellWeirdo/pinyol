-- view: the picture. The arena is the PPU's background layer (a rooftop at night, painted once, half the screen's size); the fighters are meshes over it.
local Cam, F, Poses = require("cam"), require("fighter"), require("poses")
local M = {}

M.COL_A = {gi = "TEX_GI_RED", pants = "TEX_PANTS_RED", belt = "TEX_BELT_RED", face = "TEX_FACE_A", hair = "TEX_HAIR_A", glove = "TEX_GLOVE_RED"}
M.COL_B = {gi = "TEX_GI_BLUE", pants = "TEX_PANTS_BLUE", belt = "TEX_BELT_BLUE", face = "TEX_FACE_B", hair = "TEX_HAIR_B", glove = "TEX_GLOVE_BLUE"}

local backdrop_dither = nil
local function paint_backdrop()
  canvas("BG_ARENA", 240, 160); target("BG_ARENA")
  local _, fy = Cam.project(0, 0, 0)
  local fl = math.floor((fy - 38) / 2) -- where the floor starts, in the layer's pixels
  grad(0, 0, 240, fl, 0x0A0C20, 0x4A2A5A, {dither = M.dither})
  -- the skyline: towers with lit windows, and two neon signs
  local x = 0
  local seed = 7
  while x < 240 do
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    local w, h = 14 + (seed >> 8) % 18, 26 + (seed >> 12) % 40
    rect(x, fl - h, w, h, 0x141428)
    for wy = fl - h + 4, fl - 6, 6 do
      for wx = x + 3, x + w - 5, 5 do
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        if (seed >> 10) % 3 == 0 then rect(wx, wy, 2, 3, 0xF0D070) end
      end
    end
    x = x + w + 1
  end
  rect(14, fl - 46, 26, 5, 0xFF4890); rect(15, fl - 45, 24, 3, 0xFFC0E0)
  rect(196, fl - 40, 28, 5, 0x40E0F0); rect(197, fl - 39, 26, 3, 0xC8F8FF)
  -- the floor: dark tiles running to the audience, a line at the back
  rect(0, fl, 240, 160 - fl, 0x262034)
  rect(0, fl, 240, 2, 0x6A5A90)
  for i = -6, 6 do line(120 + i * 8, fl + 2, 120 + i * 30, 160, 0x3A3250) end
  for k = 1, 5 do local y = fl + 2 + math.floor((160 - fl) * (k / 5) ^ 1.6) line(0, y, 240, y, 0x34304A) end
  target()
  bg(3, {image = "BG_ARENA"})
  backdrop_dither = M.dither
end

M.dither = true
function M.sky()
  if backdrop_dither ~= M.dither then paint_backdrop() end
end

-- the fighters: far one first by their x (it does not matter: they do not overlap in z), shadows under them
function M.fighters(W, t)
  local n = F.shadow(W.p.x) + F.shadow(W.c.x)
  n = n + F.draw(W.p, Poses.of(W.p, t), M.COL_A)
  n = n + F.draw(W.c, Poses.of(W.c, t), M.COL_B)
  return n
end

return M
