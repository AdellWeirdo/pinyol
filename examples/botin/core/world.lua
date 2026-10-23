-- world: the level being played. Its cells are characters (data/levels.lua, made by gen/levelkit.py); the console draws four layers from them: the far
-- sky (BG3), the hills behind in two bands that scroll at their own speeds (BG2, cut into lines), the ground the hero walks on (BG1) and what is in front
-- of him (BG0, or the water of a sea level). Cells that break are changed in the grid and erased from the ground layer with mset; animated cells (lava, a
-- waterfall, a drip) swap their four tiles a few times a second.
local C = require("core.const")
local U = require("core.util")
local Levels = require("data.levels")
local W = {}

W.lv, W.grid, W.cw, W.ch = nil, nil, 0, 0
W.has_front = false     -- the level, its cells (grid[y][x], from 0), its size in cells
W.px_w, W.px_h = 0, 0
W.cam_x, W.cam_y = 0, 0
W.shake_x, W.shake_y, W.shake_t, W.shake_amp = 0, 0, 0, 0
W.water_y = nil                                -- pixel row of the water's surface, or nil
W.haze_amp = 0                                 -- heat wobble over the whole picture (the escape)
W.dark = nil                                   -- the spotlight: {r = radius} in a cave
W.anim = {}
W.frame_t = 0

local SOLID = {}
for c in ("#bBHFTJKmsM"):gmatch(".") do SOLID[c] = true end
local BREAKABLE = {b = true, B = true, F = true, K = true, J = true}
local HURT = {["^"] = true, v = true, L = true}
W.SOLID, W.BREAKABLE, W.HURT = SOLID, BREAKABLE, HURT

local SPLIT = 80 -- the screen line where the mid hills end and the near ones begin

function W.cell(cx, cy)
  if cx < 0 or cx >= W.cw then return "H" end
  if cy < 0 or cy >= W.ch then return "." end
  return W.grid[cy][cx]
end

function W.is_solid(cx, cy) return SOLID[W.cell(cx, cy)] == true end
function W.solid_px(x, y) return SOLID[W.cell(x // 16, y // 16)] == true end

-- erases a cell (a block that broke): the grid and the four tiles
function W.clear(cx, cy)
  if cx < 0 or cx >= W.cw or cy < 0 or cy >= W.ch then return end
  W.grid[cy][cx] = "."
  for i = 0, 3 do mset(1, cx * 2 + i % 2, cy * 2 + i // 2, 0) end
end

function W.in_water(y) return W.water_y ~= nil and y >= W.water_y end

function W.load(n)
  local lv = Levels[n]
  assert(lv, "no level " .. tostring(n))
  W.lv, W.cw, W.ch = lv, lv.w, lv.h
  W.px_w, W.px_h = lv.w * 16, lv.h * 16
  W.grid = {}
  for y = 0, lv.h - 1 do
    local row, line = {}, lv.rows[y + 1]
    for x = 0, lv.w - 1 do row[x] = line:sub(x + 1, x + 1) end
    W.grid[y] = row
  end
  local B = lv.biome:upper()
  bg(3) -- (the sky is painted into the hills' layer: see gen/bgcomp.py)
  bg(2, {image = B .. "_BGIMG", prio = 2}) -- the hills: a direct-colour picture (gen/bgcomp.py), cheaper than a tile map
  bg(1, {map = lv.fg, prio = 1, wrap = false})
  W.water_y = lv.notes.water_row and lv.notes.water_row * 16 or nil
  W.has_front = lv.has_front
  if lv.has_front then
    bg(0, {map = lv.front, prio = 0, wrap = false})
  else
    bg(0) -- nothing in front of the hero in this level: a layer less to draw
  end
  W.anim = {}
  for _, a in ipairs(lv.anim) do
    for _, c in ipairs(a.cells) do W.anim[#W.anim + 1] = {x = c[1], y = c[2], frames = c[3]} end
  end
  W.cam_x, W.cam_y = 0, 0
  W.shake_t, W.shake_x, W.shake_y = 0, 0, 0
  W.haze_amp = 0
  W.frame_t = -1
  W.sync_anim(0)
  fx_off()
  window_off(0)
  line_off()
  W.fx_setup()
end

-- the animated cells show the frame of the moment (cells that broke are skipped by their grid char)
function W.sync_anim(t)
  local k = (t // 8) % 4
  if k == W.frame_t then return end
  W.frame_t = k
  for _, a in ipairs(W.anim) do
    local c = W.grid[a.y][a.x]
    if c ~= "." and not SOLID[c] then
      local e = a.frames[k + 1]
      for i = 0, 3 do mset(1, a.x * 2 + i % 2, a.y * 2 + i // 2, e[i + 1]) end
    end
  end
end

-- effects that stay on while the level lasts: none (a blended layer or a window costs the console a frame of its time, the explainer says so)
function W.fx_setup() end

function W.shake(amp, ticks)
  W.shake_amp, W.shake_t = amp, ticks
end

-- the camera follows (x, y) with a look ahead on the side the hero faces
function W.follow(x, y, face, snap)
  local tx = x - C.W / 2 + face * 22
  local ty = y - C.H / 2 - 8
  if snap then
    W.cam_x, W.cam_y = tx, ty
  else
    W.cam_x = W.cam_x + (tx - W.cam_x) * 0.12
    local dy = ty - W.cam_y
    if math.abs(dy) > 14 then W.cam_y = W.cam_y + (dy - U.sign(dy) * 14) * 0.15 end
  end
  W.cam_x = U.clamp(W.cam_x, 0, math.max(0, W.px_w - C.W))
  W.cam_y = U.clamp(W.cam_y, 0, math.max(0, W.px_h - C.H))
end

function W.update(t)
  W.sync_anim(t)
  if W.shake_t > 0 then
    W.shake_t = W.shake_t - 1
    local a = W.shake_amp * (W.shake_t > 0 and 1 or 0)
    W.shake_x = ((t * 7) % 3 - 1) * a
    W.shake_y = ((t * 5) % 3 - 1) * a
  else
    W.shake_x, W.shake_y = 0, 0
  end
end

-- the console's scroll: the hills' layer in two bands (the mid hills with the sky behind them, then the near foreground), each at its own pace, and the ground at the camera's
function W.scroll(t)
  local cx, cy = math.floor(W.cam_x) + W.shake_x, math.floor(W.cam_y) + W.shake_y
  scroll(1, cx, cy)
  if W.has_front then scroll(0, cx, cy) end
  local sh = U.clamp(math.floor(cy * 0.25), 0, 16)
  local mx, nx = math.floor(cx * 0.3), math.floor(cx * 0.55)
  for l = 0, SPLIT - 1 do line_scroll(2, l, mx, l + sh) end
  for l = SPLIT, C.H - 1 do line_scroll(2, l, nx, 96 + (l - SPLIT) + sh) end
  if W.water_y then
    -- the sea ripples just under the surface: a few lines of the ground sway (a sway over the whole screen costs the console about 9 ms of a frame, so deep water does not)
    local top = math.floor(W.water_y - W.cam_y)
    for l = math.max(top, 0), math.min(top + 28, C.H - 1) do
      local wave = math.floor(math.sin((l + t * 0.7) / 5) * 1.5 + 0.5)
      line_scroll(1, l, cx + wave, cy)
    end
  end
  if W.haze_amp > 0 then haze(0, C.H - 1, W.haze_amp, t / 9, 14) end
end

return W
