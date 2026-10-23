-- chars: the two paper dolls, each of a handful of parts hung from each other. They sway on the beat, open their mouths when they sing, and the rabbit's ears
-- say how the mood is (up when it is cool, drooping when it is awful). All of it is quad(): turned, scaled and bent pictures.
local Puppet = require("puppet")
local M = {}

local part = Puppet.part
local S = 1.25 -- how big they are drawn

local function rot(x, y, deg) -- a point turned about the origin
  local r = math.rad(deg)
  return x * math.cos(r) - y * math.sin(r), x * math.sin(r) + y * math.cos(r)
end

-- the maestro: a frog with a pointer. st: {t (ticks), beat (ticks a beat), sing (mouth open), energy (0..1), arm (a raised arm, degrees)}
function M.sapo(cx, floor_y, st)
  local ph = st.t / st.beat * math.pi * 2
  local bob = math.sin(ph) * 3 * st.energy
  local sway = math.sin(ph / 2) * 4 * st.energy
  local px, py = cx, floor_y - 25 * S + bob
  local swing = math.sin(ph) * 7 * st.energy
  part("P_SAPO_LEG", 16, 26, 8, 2, px - 8 * S, py, swing, S, 0)
  part("P_SAPO_LEG", 16, 26, 8, 2, px + 8 * S, py, -swing, S, 0, nil)
  -- the body hangs from the hips, tilted a little
  local tx, ty = rot(0, -34 * S, sway)
  part("P_SAPO_BODY", 40, 44, 20, 40, px, py + 4 * S, sway, S, math.sin(ph) * 1.5)
  local shx, shy = px + tx, py + 4 * S + ty
  local hx, hy = rot(0, -4 * S, sway)
  part(st.sing and "P_SAPO_HEAD_O" or "P_SAPO_HEAD", 48, 36, 24, 32, shx + hx, shy + hy, sway * 1.5 + math.sin(ph * 2) * 3 * st.energy, S, 0)
  local ax, ay = rot(-15 * S, 4 * S, sway)
  part("P_SAPO_ARM", 12, 30, 6, 2, shx + ax, shy + ay, 10 + swing, S, 0)
  local bx, by = rot(15 * S, 4 * S, sway)
  local arm = -30 - (st.arm or 0)
  part("P_SAPO_ARM", 12, 30, 6, 2, shx + bx, shy + by, arm, S, 0)
  -- the pointer in that hand
  local hxp, hyp = rot(0, 26 * S, arm)
  part("P_STICK", 8, 56, 4, 6, shx + bx + hxp, shy + by + hyp, arm - 20, S, 0)
end

-- the rabbit: st.mood is "awful".."cool"; st.hop (0..1) a jump when a note lands
function M.lila(cx, floor_y, st)
  local ph = st.t / st.beat * math.pi * 2
  local lift = ({awful = 0, bad = 0.3, good = 0.7, cool = 1})[st.mood or "good"]
  local bob = math.sin(ph) * (1 + 2 * lift) * st.energy - (st.hop or 0) * 16
  local sway = math.sin(ph / 2) * (2 + 4 * lift) * st.energy
  local px, py = cx, floor_y - 24 * S + bob
  local swing = math.sin(ph) * 8 * st.energy
  part("P_LILA_LEG", 16, 26, 8, 2, px - 7 * S, py, swing, S, 0)
  part("P_LILA_LEG", 16, 26, 8, 2, px + 7 * S, py, -swing, S, 0)
  local tx, ty = rot(0, -32 * S, sway)
  part("P_LILA_BODY", 36, 40, 18, 36, px, py + 4 * S, sway, S, math.sin(ph) * 1.5)
  local shx, shy = px + tx, py + 4 * S + ty
  local hxp, hyp = rot(0, -3 * S, sway)
  local hdeg = sway * 1.5 + (st.tilt or 0)
  local headx, heady = shx + hxp, shy + hyp
  -- the ears, from the top of the head: up and apart when cool, drooping when awful
  local spread = 8 + (1 - lift) * 62
  local ex, ey = rot(0, -28 * S, hdeg)
  part("P_LILA_EAR", 14, 44, 7, 40, headx + ex - 7 * S, heady + ey + 6 * S, hdeg - spread, S, math.sin(ph) * 3 * lift + (1 - lift) * 6)
  part("P_LILA_EAR", 14, 44, 7, 40, headx + ex + 7 * S, heady + ey + 6 * S, hdeg + spread, S, -math.sin(ph) * 3 * lift - (1 - lift) * 6)
  part(st.sing and "P_LILA_HEAD_O" or "P_LILA_HEAD", 40, 34, 20, 30, headx, heady, hdeg, S, 0)
  local ax, ay = rot(-14 * S, 4 * S, sway)
  part("P_LILA_ARM", 12, 26, 6, 2, shx + ax, shy + ay, 12 + swing - (st.arm or 0), S, 0)
  local bx, by = rot(14 * S, 4 * S, sway)
  part("P_LILA_ARM", 12, 26, 6, 2, shx + bx, shy + by, -12 - swing + (st.arm or 0), S, 0)
end

return M
