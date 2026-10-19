-- w:drive: a flipper (a static polygon turned about its end) holds a ball still and throws it when swung up. Two worlds with
-- the same flipper and ball: one driven with w:drive, one only turned (its angle and place set, no speed): the second is the
-- wall that jumps, which hardly throws at all.
local physics = require("physics")
local PIVOT_X, PIVOT_Y, LEN, THICK = 100, 200, 70, 10

local function make(driven)
  local w = physics.world({gravity = 0.25})
  local f = w:poly(PIVOT_X, PIVOT_Y - THICK / 2, {0, 0, LEN, 0, LEN, THICK, 0, THICK}, {static = true, bounce = 0.3})
  w:drive(f, 0, PIVOT_X, PIVOT_Y)
  local ball = w:circle(PIVOT_X + 40, PIVOT_Y - 60, 5, {bounce = 0.3})
  return {w = w, f = f, ball = ball, driven = driven, up = 0, angle = 0}
end

local function turn(s, angle)
  if s.driven then
    s.w:drive(s.f, angle)
  else -- the same poses without the speeds: the polygon is moved, not driven
    local a = angle % 360
    local c, sn = math.cos(math.rad(a)), math.sin(math.rad(a))
    local arm = s.arm or {s.f.x - PIVOT_X, s.f.y - PIVOT_Y}
    s.arm = arm
    s.f.x, s.f.y, s.f.angle = PIVOT_X + arm[1] * c - arm[2] * sn, PIVOT_Y + arm[1] * sn + arm[2] * c, a
  end
end

function _init()
  show(0)
  A, B = make(true), make(false)
  other = A.w:poly(300, 100, {0, 0, 50, 0, 50, 8, 0, 8}, {static = true}) -- far from the ball: stopped mid-swing
  A.w:drive(other, 0, 300, 100)
  other_turns = false
  swing = false
  ticks_since = 0
end

function _update()
  if other_turns then A.w:drive(other, (other.angle - 15) % 360) end
  for _, s in ipairs({A, B}) do
    if swing then
      s.angle = math.max(-45, s.angle - 15) -- up 45 degrees in three ticks
      turn(s, s.angle)
    end
    s.w:step()
    s.up = math.max(s.up, -s.ball.vy)
  end
  if swing then ticks_since = ticks_since + 1 end
end

function _draw() cls(0) end
