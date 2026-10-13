-- Bodies that turn (lib/physics.lua), checked by tests/turning.script: a box that tips over, a stack, a wheel on a
-- ramp, a polygon, and a raft on a river.
physics = require("physics")
world = physics.world({gravity = 0.3})
floor = world:box(0, 300, 300, 20, {static = true})
ramp = world:poly(0, 0, {160, 240, 290, 300, 160, 300}, {static = true})
wall = world:box(292, 240, 8, 60, {static = true})
tipper = world:box(90, 150, 60, 20, {turns = true, angle = 30})
stack = {}
for i = 1, 3 do stack[i] = world:box(20, 300 - i * 22, 40, 20, {turns = true, friction = 0.8}) end
wheel = world:circle(172, 222, 12, {turns = true, friction = 0.9})
rock = world:poly(200, 40, {0, 0, 30, 10, 20, 30, -10, 20, 5, 12}, {turns = true})
river = world:water(300, 200, 180, 120, {lift = 2, drag = 0.08, flow_x = 1.5})
bank = world:box(300, 315, 180, 5, {static = true})
raft = world:box(320, 150, 70, 16, {turns = true, angle = 20})
hits = 0

function _init() show(0) end

function _update()
  world:step()
  hits = hits + #world:hits()
  if raft.x > 400 then raft.x = 320 end -- the current carries it: back upstream
end

local function draw_body(b, c)
  if b.kind == "circle" then
    circ(b.x, b.y, b.r, c)
    local a = math.rad(b.angle or 0)
    line(b.x, b.y, b.x + math.cos(a) * b.r, b.y + math.sin(a) * b.r, 0x000000)
  else
    poly(world:corners(b), c)
  end
end

function _draw()
  cls(0x1C2430)
  rect(river.x, river.y, river.w, river.h, 0x2C5878)
  draw_body(floor, 0x606870)
  draw_body(ramp, 0x606870)
  draw_body(bank, 0x606870)
  draw_body(wall, 0x606870)
  draw_body(tipper, 0xE0A040)
  for i, b in ipairs(stack) do draw_body(b, i % 2 == 0 and 0xC06040 or 0xE08060) end
  draw_body(wheel, 0x80C0E0)
  draw_body(rock, 0xA0A0A0)
  draw_body(raft, 0xB08050)
end

-- for the script: is a turned body resting flat (its angle near a quarter turn)?
function flat(b, tol) local a = b.angle % 90 return a < tol or a > 90 - tol end
