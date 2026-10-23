-- miner: the player. The jump is a Spectrum jump: it goes straight up or along, and once in the air there is no steering. Walls stop him,
-- ledges hold him from above, crumbling floors go in three steps, belts carry him, a fall of more than four blocks kills.
-- gen/rooms_design.py has a copy of these numbers and checks that every key and every portal can be reached.
local R = require("core.room")
local I = require("core.input")
local M = {}

local GRAVITY, JUMP, MAX_FALL, DEADLY = 0.19, -3.4, 3, 36
M.GRAVITY, M.JUMP, M.MAX_FALL, M.DEADLY = GRAVITY, JUMP, MAX_FALL, DEADLY

M.x, M.y, M.vx, M.vy, M.ground, M.face, M.top, M.dead, M.anim = 0, 0, 0, 0, true, 1, 0, 0, 0
M.on_jump, M.on_land, M.on_die = nil, nil, nil  -- hooks the game sets (sounds)
M.fell = false

function M.reset()
  M.x, M.y, M.vx, M.vy, M.ground, M.face, M.top, M.dead, M.anim = R.start.x, R.start.y, 0, 0, true, 1, R.start.y, 0, 0
  M.win = false
end

function M.die()
  if M.dead > 0 then return end
  M.dead = 1
  if M.on_die then M.on_die() end
end

local function crumble_step(tx, ty)
  local k = ty * R.W + tx + 1
  R.crumbling[k] = (R.crumbling[k] or 0) + 1
  local stage = R.crumbling[k] // 10
  if stage >= 3 then
    R.set(tx, ty, ".")
    R.crumbling[k] = nil
  elseif stage > 0 then
    R.draw(tx, ty, "crumble_" .. stage)
  end
end

local function update_walk()
  local solid, ledge, char = R.is_solid, R.is_ledge, R.char
  local onfloor = M.ground
  if onfloor then
    local dx = (I.btn("right") and 1 or 0) - (I.btn("left") and 1 or 0)
    if dx ~= 0 then M.face = dx end
    M.vx = dx
    if I.btnp("a") then
      M.vy, M.ground, M.top = JUMP, false, M.y
      if M.on_jump then M.on_jump() end
    end
  end
  local nx = M.x + M.vx -- across: the body is x+4 .. x+11
  local edge = M.vx > 0 and nx + 11 or nx + 4
  if M.vx == 0 or not (solid(char(edge // 8, (M.y + 2) // 8)) or solid(char(edge // 8, (M.y + 13) // 8))) then M.x = nx end
  if M.ground then
    local tx, ty = math.floor(M.x + 8) // 8, (math.floor(M.y) + 16) // 8
    local under = char(tx, ty)
    if under == ">" then M.x = M.x + 0.6 elseif under == "<" then M.x = M.x - 0.6 end
    if under == "-" then crumble_step(tx, ty) end
    if not ledge(under) and not solid(under) and not ledge(char((M.x + 4) // 8, ty)) and not ledge(char((M.x + 11) // 8, ty)) then
      M.ground, M.vy, M.top = false, 0, M.y -- off an edge
    end
    return
  end
  M.vy = math.min(M.vy + GRAVITY, MAX_FALL)
  local old = M.y + 16
  M.y = M.y + M.vy
  if M.vy < 0 and solid(char(math.floor(M.x + 8) // 8, math.floor(M.y) // 8)) then M.y, M.vy = (math.floor(M.y) // 8 + 1) * 8, 0 end
  if M.vy > 0 then
    for _, px in ipairs({M.x + 4, M.x + 11}) do
      local fy = math.floor(M.y + 16)
      local c, top = char(math.floor(px) // 8, fy // 8), (fy // 8) * 8
      if (solid(c) or ledge(c)) and old <= top + 1 then
        if top - 16 - M.top > DEADLY then M.fell = true M.die() end -- too long a fall
        M.y, M.vy, M.ground, M.vx = top - 16, 0, true, 0
        if M.on_land then M.on_land() end
        return
      end
    end
  end
end

-- what the body touches: the four corners of the inner box
function M.corners()
  return {{M.x + 5, M.y + 4}, {M.x + 10, M.y + 4}, {M.x + 5, M.y + 14}, {M.x + 10, M.y + 14}}
end

function M.update()
  if M.dead > 0 then M.dead = M.dead + 1 return end
  M.anim = M.anim + 1
  update_walk()
  if M.y > R.H * 8 then M.die() end
end

-- the frame to draw
function M.frame()
  if M.win then return (M.anim // 10) % 2 == 0 and "win_0" or "win_1" end
  if M.dead > 0 then return "die_" .. math.min(3, M.dead // 8) end
  if not M.ground then return M.vy < 0 and "jump_up" or "jump_down" end
  if M.vx ~= 0 then return "walk_" .. (M.anim // 4) % 4 end
  return "stand"
end

return M
