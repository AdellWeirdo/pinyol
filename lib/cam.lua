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
local ok_juice, juice = pcall(require, "juice")
local M = {}
local C = {}
C.__index = C

function M.new(o)
  o = o or {}
  local self = setmetatable({x = 0, y = 0, w = o.w or SCREEN_W, h = o.h or SCREEN_H, bounds = o.bounds,
                             dz_w = o.deadzone and o.deadzone[1] or 0, dz_h = o.deadzone and o.deadzone[2] or 0,
                             lerp = o.lerp or 1, lead = o.lead or 0, forward_only = o.forward_only or false,
                             lx = 0, ly = 0}, C)
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

function C:visible(x, y, w, h) -- is that box on the screen?
  return x + (w or 0) > self.x and x < self.x + self.w and y + (h or 0) > self.y and y < self.y + self.h
end

return M
