-- bot: a very small player for the title's attract mode: runs right shooting, jumps in front of gulls that come close, looks up at the flyers, throws a pressure cooker now and then.
local Foes = require("core.foes")
local In = require("core.input")
local B = {}
local t = 0
local jump_t = 0

function B.start() t = 0 jump_t = 0 In.state = {} end

function B.step(chef)
  t = t + 1
  local s = {a = true, right = true}
  local near_ground, air_up = false, false
  for _, f in ipairs(Foes.list) do
    if f.state ~= "dying" then
      local dx = f.x - chef.x
      if f.d.ground and dx > 0 and dx < 130 then near_ground = true end
      if f.d.fly and math.abs(dx) < 120 and f.y < chef.y - 60 then air_up = true end
    end
  end
  if air_up then s.up = true end
  if near_ground and chef.ground and jump_t <= 0 then jump_t = 22 end
  if jump_t > 0 then s.b = true jump_t = jump_t - 1 end
  if t % 300 == 150 then s.c = true end
  In.state = s
end

return B
