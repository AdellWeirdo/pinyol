-- people: the player (a person in a coat with a torch) and the Figure (tall, pale, faceless), each of a few boxes. Limbs swing in three baked poses
-- (back, straight, forward), see models.lua; the stride picks one for each leg and each arm.
local Models, View = require("models"), require("view")
local M = {}
local P, F = {}, {}  -- the person's models, the Figure's
local POSES = {30, 0, -30} -- pitch of a limb: back, straight, forward (the foot goes back with a positive pitch)

local function limbs(tab, name, w, h, d, tex_pivot)
  for i, a in ipairs(POSES) do
    local s = Models.solid(); s:limb(w, h, d, 0, 0, 0, a); tab[name .. i] = s:build()
  end
end

function M.init()
  local s
  -- the person: 18 tall
  s = Models.solid(); s:box(5.6, 6.6, 3.2, 0, 0, 0); P.torso = s:build()
  s = Models.solid(); s:box(2.9, 2.9, 2.9, 0, 0, 0); P.head = s:build()
  s = Models.solid(); s:box(3.2, 1.3, 3.2, 0, 0, 0); P.hair = s:build()
  s = Models.solid(); s:box(1.6, 1.6, 5.4, 0, 0, 0); P.torch = s:build()
  limbs(P, "leg", 2.4, 8.4, 2.6); limbs(P, "arm", 1.7, 6.4, 1.8)
  -- the Figure: 27 tall, thin, a little hunched, arms that hang too low
  s = Models.solid(); s:box(5, 9, 2.8, 0, 0, 0); F.torso = s:build()
  s = Models.solid(); s:box(3, 3.4, 3, 0, 0, 0); F.head = s:build()
  limbs(F, "leg", 1.8, 13, 1.8); limbs(F, "arm", 1.3, 14.5, 1.3)
end

-- the pose (1 back, 2 straight, 3 forward) of a limb at a point of the stride (phase, radians), the other limb of the pair a half stride off
local function pose(phase, other)
  local s = math.sin(phase + (other and math.pi or 0))
  return s > 0.35 and 1 or s < -0.35 and 3 or 2
end

-- a part at (ox, oy, oz) in the body's space (x right, y up, z forward), the body turned `h` degrees
local function put(model, tex, x, z, h, ox, oy, oz, amb)
  local r = math.rad(h)
  local c, s = math.cos(r), math.sin(r)
  return View.call(model, tex, x + ox * c + oz * s, oy, z - ox * s + oz * c, h, amb)
end

-- the player: x, z, heading, stride phase (nil: standing), lit by `amb`
function M.draw_player(x, z, h, phase, amb)
  local n, moving = 0, phase ~= nil
  local ph = phase or 0
  local lp, rp = moving and pose(ph) or 2, moving and pose(ph, true) or 2
  n = n + put(P["leg" .. lp], "TEX_JEANS", x, z, h, -1.4, 8.4, 0, amb)
  n = n + put(P["leg" .. rp], "TEX_JEANS", x, z, h, 1.4, 8.4, 0, amb)
  n = n + put(P.torso, "TEX_COAT", x, z, h, 0, 11.7, 0, amb)
  n = n + put(P.head, "TEX_SKIN", x, z, h, 0, 16.5, 0, amb)
  n = n + put(P.hair, "TEX_HAIR", x, z, h, 0, 18.4, -0.1, amb)
  n = n + put(P["arm" .. rp], "TEX_COAT", x, z, h, -3.7, 14.6, 0, amb)
  -- the arm that holds the torch is raised: the torch points where the player looks
  n = n + put(P.torch, "TEX_METAL", x, z, h, 3.6, 11.4, 3.2, amb)
  n = n + put(P["arm" .. 2], "TEX_COAT", x, z, h, 3.7, 14.6, 0, amb)
  return n
end

function M.draw_figure(x, z, h, phase, amb)
  local n = 0
  local lp, rp = pose(phase), pose(phase, true)
  n = n + put(F["leg" .. lp], "TEX_FIGURE", x, z, h, -1.6, 13, 0, amb)
  n = n + put(F["leg" .. rp], "TEX_FIGURE", x, z, h, 1.6, 13, 0, amb)
  n = n + put(F.torso, "TEX_FIGURE", x, z, h, 0, 17.5, 0.4, amb)
  n = n + put(F.head, "TEX_HOLLOW", x, z, h, 0, 23.7, 0.9, amb)
  n = n + put(F["arm" .. rp], "TEX_FIGURE", x, z, h, -3.4, 21.5, 0.4, amb)
  n = n + put(F["arm" .. lp], "TEX_FIGURE", x, z, h, 3.4, 21.5, 0.4, amb)
  return n
end

return M
