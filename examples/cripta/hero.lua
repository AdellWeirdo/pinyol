-- hero: how the hero moves through the castle, from a table of what is pressed. Its x, y are the castle's pixels, not a room's: walking off a
-- room's edge is walking on, and the game only changes which room it draws. No drawing and no buttons read, so the tests can play jumps and dashes
-- with the same code the game runs, and check them against what world.lua's solver assumes (a jump climbs 3 tiles, two climb 5, a dash
-- goes through a cracked wall and breaks it).
local W = require("world")

local M = {}
M.GRAVITY, M.JUMP, M.JUMP2, M.RUN, M.ACCEL, M.MAX_FALL = 0.24, -5.2, -4.4, 1.8, 0.3, 5
M.DASH_SPEED, M.DASH_TICKS, M.DASH_REST = 4, 12, 30
M.BOX_X0, M.BOX_X1, M.BOX_Y0, M.BOX_Y1 = 3, 12, 2, 15 -- the body inside its 16 x 16 sprite

function M.new(x, y) return {x = x, y = y, vx = 0, vy = 0, ground = false, coyote = 0, air_jumps = 0, face = 1, dash = 0, dash_rest = 0} end

local function hit(px, py) -- a pixel inside a wall (a cracked wall is one until it breaks)
  local c = W.wcell(px // W.T, py // W.T)
  return c == W.WALL or c == W.CRACKED
end

local function break_at(tx, ty) -- a castle tile's cracked wall broken, and the rest of its column of cracked wall
  while W.wcell(tx, ty - 1) == W.CRACKED do ty = ty - 1 end
  local n = 0
  while W.wcell(tx, ty) == W.CRACKED do
    local r, lx, ly = W.room_at(tx, ty)
    W.break_wall(r, lx, ly)
    n, ty = n + 1, ty + 1
  end
  return n
end

-- One tick. `inp` = {left, right, jump (pressed this tick), hold (jump held), dash (pressed)}; `ab` = {wings, gust}.
-- Returns what happened: {jumped, double, dashed, broke = n, landed}.
function M.step(h, inp, ab)
  local ev = {}
  h.dash_rest = math.max(0, h.dash_rest - 1)
  if h.dash > 0 then
    h.dash = h.dash - 1
    h.vx, h.vy = h.face * M.DASH_SPEED, 0
  else
    if inp.left and not inp.right then h.vx, h.face = math.max(h.vx - M.ACCEL, -M.RUN), -1
    elseif inp.right and not inp.left then h.vx, h.face = math.min(h.vx + M.ACCEL, M.RUN), 1
    else h.vx = h.vx * 0.7 if math.abs(h.vx) < 0.05 then h.vx = 0 end end
    h.coyote = h.ground and 6 or math.max(h.coyote - 1, 0)
    if h.ground then h.air_jumps = ab.wings and 1 or 0 end
    if inp.jump then
      if h.coyote > 0 then h.vy, h.coyote, h.ground, ev.jumped = M.JUMP, 0, false, true
      elseif h.air_jumps > 0 then h.vy, h.air_jumps, ev.jumped, ev.double = M.JUMP2, h.air_jumps - 1, true, true end
    end
    if not inp.hold and h.vy < -2 then h.vy = -2 end -- a short press, a short jump
    h.vy = math.min(h.vy + M.GRAVITY, M.MAX_FALL)
    if inp.dash and ab.gust and h.dash_rest == 0 then h.dash, h.dash_rest, ev.dashed = M.DASH_TICKS, M.DASH_REST, true end
  end
  -- across, in steps of a pixel at most so a dash cannot pass through a thin wall
  local steps = math.max(1, math.ceil(math.abs(h.vx)))
  for _ = 1, steps do
    local nx = h.x + h.vx / steps
    local edge = h.vx > 0 and math.floor(nx + M.BOX_X1) or math.floor(nx + M.BOX_X0)
    local blocked = false
    for _, py in ipairs({h.y + M.BOX_Y0, h.y + 8, h.y + M.BOX_Y1}) do
      if hit(edge, math.floor(py)) then
        if h.dash > 0 and W.wcell(edge // W.T, math.floor(py) // W.T) == W.CRACKED then -- the dash breaks it
          ev.broke = (ev.broke or 0) + break_at(edge // W.T, math.floor(py) // W.T)
        else
          blocked = true
        end
      end
    end
    if blocked then h.vx = 0 h.dash = 0 break end
    h.x = nx
  end
  -- down and up; a platform holds only from above
  local old_bottom = h.y + M.BOX_Y1
  h.y = h.y + h.vy
  local was = h.ground
  h.ground = false
  if h.vy >= 0 then
    for _, px in ipairs({h.x + M.BOX_X0 + 1, h.x + M.BOX_X1 - 1}) do
      local fy = math.floor(h.y + M.BOX_Y1 + 1)
      local c = W.wcell(math.floor(px) // W.T, fy // W.T)
      local top = (fy // W.T) * W.T
      if c == W.WALL or c == W.CRACKED or (c == W.PLATFORM and old_bottom < top) then
        h.y, h.vy, h.ground = top - M.BOX_Y1 - 1, 0, true
      end
    end
  else
    for _, px in ipairs({h.x + M.BOX_X0 + 1, h.x + M.BOX_X1 - 1}) do
      local ty = math.floor(h.y + M.BOX_Y0)
      if hit(math.floor(px), ty) then h.y, h.vy = (ty // W.T + 1) * W.T - M.BOX_Y0, 0 end
    end
  end
  if h.ground and not was then ev.landed = true end
  return ev
end

-- the room the hero is in (by the middle of its body), and the hero's place in it
function M.room(h)
  local r = W.room_at((h.x + 8) // W.T, (h.y + 8) // W.T)
  return r
end

return M
