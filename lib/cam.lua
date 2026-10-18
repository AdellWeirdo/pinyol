-- cam: a camera that follows something, as Godot's Camera2D and Phaser's startFollow do: it lets the target move
-- inside a dead zone without moving, catches up smoothly (lerp), looks ahead where it is going, never shows outside
-- the level's bounds, and can be told never to go back.
--
--   local cam = require("cam")
--   local c = cam.new({bounds = {0, 0, 3840, 320}, deadzone = {80, 60}, lerp = 0.15, lead = 40})
--   c:follow(hero)          -- anything with x, y (or c:follow(hero, 0, -40): a point above its feet)
--   c:update()              -- once a tick
--   c:apply()               -- in _draw: camera(...) at c.x, c.y, with juice's shake if there is one; then camera()
-- c.x, c.y is the top-left corner of what is seen (480x320 by default: {w = 240, h = 160} for the world's PPU, with
-- scroll(n, c.x, c.y)). c:snap() jumps straight to the target; c:look(x, y) aims at a point for a while (a door
-- opening), c:look() gives it back to the target. forward_only = true: it never scrolls back left (a run-and-gun).
--
-- Zoom and turn (for a scene drawn with rect, img, quad, light...: not the PPU's layers): the scene is drawn on a canvas and put on the
-- screen as a quad, scaled and turned about the screen's middle. Not zoomed or turned it is drawn straight, at no cost.
--   c:draw(function() ...the world... end)   -- instead of c:apply() ... camera(); or c:begin() ... c:finish() (each can take a canvas to draw on)
--   c:zoom_to(2)  c:rotate_to(15)           -- ease there (the second number: how fast, 0.12 a tick); c:zoom_now(2), c:rotate_now(0) at once
--   c:punch(0.08, 12)                       -- a hit: zooms in 8 % and eases back in 12 ticks
-- Measured on the console: not zoomed or turned, nothing; zoomed and turned, a canvas of the whole screen is ~80 ms a frame (12 fps: the canvas is
-- filled in the slow memory, then a quad of it drawn), and cam.new({w = 240, h = 160}) (half the pixels: a chunkier picture) ~31 ms (30 fps).
-- So it is for a moment (a hit, a reveal, a boss's entrance, a frozen frame), not for a whole level.
-- c.zoom and c.rot are what it is now (rot in degrees, clockwise); c.bg the colour seen past the edges when zoomed out (black).
local ok_juice, juice = pcall(require, "juice")
local M = {}
local C = {}
C.__index = C

function M.new(o)
  o = o or {}
  local self = setmetatable({x = 0, y = 0, w = o.w or SCREEN_W, h = o.h or SCREEN_H, bounds = o.bounds,
                             dz_w = o.deadzone and o.deadzone[1] or 0, dz_h = o.deadzone and o.deadzone[2] or 0,
                             lerp = o.lerp or 1, lead = o.lead or 0, forward_only = o.forward_only or false,
                             lx = 0, ly = 0, zoom = 1, rot = 0, bg = o.bg or 0x000000, punch_amt = 0, punch_t = 0, punch_len = 1}, C)
  return self
end

function C:follow(target, ox, oy) self.target, self.ox, self.oy, self.lx = target, ox or 0, oy or 0, 0 return self end
function C:look(x, y) self.at_x, self.at_y = x, x and (y or self.y + self.h / 2) return self end

local function clamp(self, x, y)
  local b = self.bounds
  if b then
    x = math.max(b[1], math.min(b[1] + math.max(0, b[3] - self.w), x))
    y = math.max(b[2], math.min(b[2] + math.max(0, b[4] - self.h), y))
  end
  return x, y
end

local function aim(self) -- where the centre should be
  if self.at_x then return self.at_x, self.at_y end
  local t = self.target
  if not t then return self.x + self.w / 2, self.y + self.h / 2 end
  local tx, ty = t.x + self.ox, t.y + self.oy
  if self.lead ~= 0 and t.vx then -- look ahead where it moves
    self.lx = self.lx + ((t.vx > 0.1 and self.lead or t.vx < -0.1 and -self.lead or self.lx) - self.lx) * 0.05
  end
  return tx + self.lx, ty
end

function C:update()
  local tx, ty = aim(self)
  local cx, cy = self.x + self.w / 2, self.y + self.h / 2
  local gx, gy = cx, cy -- the target only moves the camera once it leaves the dead zone
  if tx > cx + self.dz_w / 2 then gx = tx - self.dz_w / 2 elseif tx < cx - self.dz_w / 2 then gx = tx + self.dz_w / 2 end
  if ty > cy + self.dz_h / 2 then gy = ty - self.dz_h / 2 elseif ty < cy - self.dz_h / 2 then gy = ty + self.dz_h / 2 end
  local nx = self.x + (gx - cx) * self.lerp
  local ny = self.y + (gy - cy) * self.lerp
  if self.forward_only then nx = math.max(self.x, nx) end
  self.x, self.y = clamp(self, nx, ny)
  if self.zoom_goal then self.zoom = self.zoom + (self.zoom_goal - self.zoom) * self.zoom_lerp end
  if self.rot_goal then self.rot = self.rot + (self.rot_goal - self.rot) * self.rot_lerp end
  if self.punch_t < self.punch_len then self.punch_t = self.punch_t + 1 end
end

function C:snap()
  local tx, ty = aim(self)
  self.x, self.y = clamp(self, tx - self.w / 2, ty - self.h / 2)
  return self
end

function C:apply() -- camera() at the view, shaken by juice if it is shaking
  local sx, sy = 0, 0
  if ok_juice then sx, sy = juice.offset() end
  camera(math.floor(self.x) + sx, math.floor(self.y) + sy)
end

function C:zoom_to(z, lerp) self.zoom_goal, self.zoom_lerp = z, lerp or 0.12 return self end
function C:rotate_to(deg, lerp) self.rot_goal, self.rot_lerp = deg, lerp or 0.12 return self end
function C:zoom_now(z) self.zoom, self.zoom_goal = z, nil return self end
function C:rotate_now(deg) self.rot, self.rot_goal = deg, nil return self end
function C:punch(amount, ticks) self.punch_amt, self.punch_len, self.punch_t = amount or 0.06, math.max(1, ticks or 12), 0 return self end

function C:scale() -- the zoom as it is drawn: the camera's, and a punch's that eases out
  local k = 1 - self.punch_t / self.punch_len
  return self.zoom * (1 + self.punch_amt * k * k)
end

-- the canvas's four corners on the screen (top-left, top-right, bottom-right, bottom-left: quad's order), scaled and turned about the middle
function C:corners()
  local z, r = self:scale(), math.rad(self.rot)
  local cs, sn = math.cos(r), math.sin(r)
  local mx, my = SCREEN_W / 2, SCREEN_H / 2
  local out = {}
  for i, c in ipairs({{0, 0}, {self.w, 0}, {self.w, self.h}, {0, self.h}}) do
    local dx, dy = (c[1] - self.w / 2) * z, (c[2] - self.h / 2) * z
    out[2 * i - 1], out[2 * i] = mx + dx * cs - dy * sn, my + dx * sn + dy * cs
  end
  return table.unpack(out)
end

local CAMERA_CANVAS = "CAM_VIEW"

function C:begin(dest) -- what is drawn from now to finish() is the world, as the camera sees it (dest: on that canvas, not the screen)
  self.indirect, self.dest = math.abs(self:scale() - 1) > 0.002 or math.abs(self.rot) > 0.05, dest
  if not self.indirect then
    if dest then target(dest) end
    self:apply()
    return
  end
  canvas(CAMERA_CANVAS, self.w, self.h)
  target(CAMERA_CANVAS)
  cls(self.bg)
  self:apply()
end

function C:finish() -- the screen again (or the canvas it was drawn on, then the screen)
  camera()
  if self.indirect then
    target(self.dest)
    rect(0, 0, SCREEN_W, SCREEN_H, self.bg) -- what shows past the view when zoomed out
    quad(CAMERA_CANVAS, self:corners())
  end
  target()
end

function C:draw(fn, dest) self:begin(dest) fn() self:finish() end

function C:visible(x, y, w, h) -- is that box on the screen? (zoomed out, more is seen; turned, the screen's corners reach farther)
  local z = self:scale()
  local hw, hh = self.w / 2 / z, self.h / 2 / z
  if math.abs(self.rot) > 0.05 then local d = math.sqrt(hw * hw + hh * hh) hw, hh = d, d end
  local cx, cy = self.x + self.w / 2, self.y + self.h / 2
  return x + (w or 0) > cx - hw and x < cx + hw and y + (h or 0) > cy - hh and y < cy + hh
end

return M
