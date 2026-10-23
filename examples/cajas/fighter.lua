-- fighter: a boxy fighter of eleven parts, seen from the side. A pose is a set of joint angles (degrees, from straight down, forward positive) and the
-- hips' place; the parts are moved with a little forward kinematics, here in Lua, and each is one mesh() call turned about z only (a limb swinging in the
-- plane of the screen: the one turn mesh() can do under the camera's tilt). Poses blend, so a move is a few key poses and the frames between.
local Models = require("models")
local Cam = require("cam")
local M = {}

local parts = {}
local OPTS, POS, LIGHT = {pos = {0, 0, 0}, rot = {0, 0, 0}, focal = Cam.FOCAL, cx = Cam.CX, cy = Cam.CY, near = 8, snap = true, dither = true},
                         {0, 0, 0}, {dir = {0, 0, 0}, ambient = 0.46, gain = 0.32}
local ROT = {0, 0, 0}
M.snap, M.dither = true, true

-- the body, in tenths of a metre
local TORSO, HEAD, UARM, FARM, THIGH, SHIN = 6.4, 3.0, 3.4, 3.0, 4.4, 4.0

function M.init()
  local s
  s = Models.solid(); s:box(3.6, TORSO, 5.4, 0, 0, 0); parts.torso = s:build()
  s = Models.solid(); s:box(3.2, HEAD, 3.2, 0, 0, 0); parts.head = s:build()
  -- the limbs are one flat face each (a fist, a foot a second one): a box would show three, and the fighters are small on the screen
  s = Models.solid(); s:panel(1.9, UARM, 0, 0, 0); parts.uarm = s:build()
  s = Models.solid(); s:panel(1.7, FARM - 0.6, 0, 0, 0); s:panel(2.0, 2.0, 0.1, -(FARM - 0.6) + 0.1, 0); parts.farm = s:build()
  s = Models.solid(); s:panel(2.5, THIGH, 0, 0, 0); parts.thigh = s:build()
  s = Models.solid(); s:panel(2.1, SHIN - 0.9, 0, 0, 0); s:panel(3.8, 1.0, 0.9, -(SHIN - 0.9) + 0.1, 0); parts.shin = s:build()
  s = Models.solid(); s:floor(-3, 3, -2, 2, 0); parts.shadow = s:build()
end

local KEYS = {"py", "lean", "head", "an", "en", "af", "ef", "hn", "kn", "hf", "kf"}
-- the neutral stance: guard up, knees a little bent, one leg forward. py = nil: the hips are put where the lowest foot touches the ground
M.POSES = {
  idle = {lean = 5, head = 0, an = 25, en = 75, af = 45, ef = 85, hn = 16, kn = 14, hf = -14, kf = 12},
  walk_a = {lean = 6, head = 0, an = 10, en = 45, af = 35, ef = 70, hn = 34, kn = 20, hf = -28, kf = 18},
  walk_b = {lean = 6, head = 0, an = 35, en = 80, af = 10, ef = 50, hn = -28, kn = 18, hf = 34, kf = 20},
  crouch = {lean = 14, head = 4, an = 25, en = 80, af = 50, ef = 90, hn = 78, kn = 120, hf = 62, kf = 112},
  jump = {lean = 4, head = 0, an = 30, en = 70, af = 50, ef = 80, hn = 55, kn = 85, hf = 30, kf = 60},
  block = {lean = -2, head = 6, an = 62, en = 118, af = 74, ef = 125, hn = 18, kn = 18, hf = -14, kf = 14},
  block_low = {lean = 10, head = 8, an = 62, en = 118, af = 74, ef = 125, hn = 78, kn = 120, hf = 62, kf = 112},
  punch_a = {lean = 0, head = 2, an = -30, en = 110, af = 55, ef = 100, hn = 16, kn = 14, hf = -14, kf = 12},
  punch_b = {lean = 12, head = 4, an = 88, en = 6, af = 55, ef = 100, hn = 22, kn = 12, hf = -18, kf = 12},
  kick_a = {lean = -4, head = 0, an = 30, en = 90, af = 50, ef = 90, hn = 55, kn = 105, hf = -6, kf = 6},
  kick_b = {lean = -16, head = -4, an = 20, en = 70, af = 60, ef = 90, hn = 88, kn = 4, hf = -6, kf = 4},
  sweep_a = {lean = 18, head = 6, an = 25, en = 80, af = 50, ef = 90, hn = 70, kn = 100, hf = 62, kf = 112},
  sweep_b = {lean = 22, head = 8, an = 25, en = 80, af = 50, ef = 90, hn = 86, kn = 4, hf = 78, kf = 126},
  jkick = {lean = -10, head = 0, an = 30, en = 80, af = 50, ef = 90, hn = 84, kn = 14, hf = 50, kf = 80},
  hit = {lean = -20, head = -16, an = -20, en = 40, af = 5, ef = 30, hn = 10, kn = 10, hf = -20, kf = 10},
  hit_low = {lean = 14, head = 10, an = 40, en = 60, af = 40, ef = 70, hn = 40, kn = 60, hf = 20, kf = 40},
  down = {lean = -88, head = -10, an = -40, en = 20, af = -30, ef = 20, hn = 88, kn = 4, hf = 86, kf = 6, py = 1.9},
  win = {lean = 2, head = 0, an = 170, en = 8, af = 30, ef = 70, hn = 12, kn = 10, hf = -12, kf = 10},
}

local function mix(a, b, k)
  local p = {}
  for _, key in ipairs(KEYS) do
    local x, y = a[key], b[key]
    if x and y then p[key] = x + (y - x) * k end
  end
  if a.py or b.py then p.py = (a.py or b.py) + ((b.py or a.py) - (a.py or b.py)) * k end
  return p
end
M.mix = mix

local function rad(d) return d * math.pi / 180 end

-- the joints of a pose: positions (x forward, y up, from the hips' place) and the angle of each segment
local function skeleton(p)
  local f = {}
  local lean = rad(p.lean)
  -- the hips are the origin; the legs: thigh hn from the hip, shin hn - kn from the knee
  local function leg(h, k)
    local th, sh = rad(h), rad(h - k)
    local kx, ky = THIGH * math.sin(th), -THIGH * math.cos(th)
    local fx, fy = kx + SHIN * math.sin(sh), ky - SHIN * math.cos(sh)
    return {th = h, sh = h - k, kx = kx, ky = ky, fx = fx, fy = fy}
  end
  f.ln, f.lf = leg(p.hn, p.kn), leg(p.hf, p.kf)
  f.lowest = math.min(f.ln.fy, f.lf.fy)
  f.torso_top = {x = TORSO * math.sin(lean), y = TORSO * math.cos(lean)}
  local sx, sy = f.torso_top.x - 0.5 * math.sin(lean), f.torso_top.y - 0.5 * math.cos(lean) -- the shoulder: a little under the top
  local function arm(a, e)
    local ta, ea = rad(a), rad(a - e)
    local ex, ey = sx + UARM * math.sin(ta), sy - UARM * math.cos(ta)
    local hx, hy = ex + FARM * math.sin(ea), ey - FARM * math.cos(ea)
    return {th = a, fa = a - e, sx = sx, sy = sy, ex = ex, ey = ey, hx = hx, hy = hy}
  end
  f.an, f.af = arm(p.an, p.en), arm(p.af, p.ef)
  f.shoulder = {x = sx, y = sy}
  return f
end
M.skeleton = skeleton

-- where the near hand and foot are (for a hit's reach), relative to the hips: (forward, up)
function M.tips(p)
  local sk = skeleton(p)
  return sk.an.hx, sk.an.hy, sk.ln.fx, sk.ln.fy, sk.lowest
end

local light_for = -1
local function call(model, tex, x, y, z, rotz, pitch_deg, scale)
  if light_for ~= Cam.version then
    local mx, my, mz = Cam.dir_to_cam(-0.4, 0.8, -0.5)
    LIGHT.dir[1], LIGHT.dir[2], LIGHT.dir[3] = -mx, -my, -mz
    light_for = Cam.version
  end
  local px, py, pz = Cam.to_cam(x, y, z)
  local o = OPTS
  o.pos = POS
  POS[1], POS[2], POS[3] = px, py, pz
  o.rot = ROT
  ROT[1], ROT[2], ROT[3] = Cam.pitch_deg(), 0, rotz or 0
  o.light = LIGHT
  o.snap, o.dither = M.snap, M.dither
  return mesh(model, tex, o)
end

-- draw one fighter: f = {x, y (the hips' height offset for a jump), face (+1 right, -1 left), pose (a blended pose), colours = {gi, pants, belt, skin, face, hair}}
-- near-side limbs are in front (z a little less), far-side behind
function M.draw(f, pose, colours)
  local face = f.face
  local sk = skeleton(pose)
  local py = pose.py and (pose.py + (f.y or 0)) or (-sk.lowest + (f.y or 0))
  local x0, y0 = f.x, py
  local n = 0
  local function at(lx, ly) return x0 + face * lx, y0 + ly end
  local function seg(model, tex, lx, ly, ang, z)
    local wx, wy = at(lx, ly)
    return call(model, tex, wx, wy, z, -face * ang)
  end
  -- far side first: arm, leg
  n = n + seg(parts.thigh, colours.pants, 0, 0, sk.lf.th, 1.2)
  n = n + seg(parts.shin, colours.pants, sk.lf.kx, sk.lf.ky, sk.lf.sh, 1.2)
  n = n + seg(parts.uarm, colours.gi, sk.af.sx, sk.af.sy, sk.af.th, 2.6)
  n = n + seg(parts.farm, colours.glove, sk.af.ex, sk.af.ey, sk.af.fa, 2.6)
  -- the body
  local lean = pose.lean
  local tcx, tcy = sk.torso_top.x / 2, sk.torso_top.y / 2
  n = n + seg(parts.torso, colours.gi, tcx, tcy, lean, 0)
  local hxp, hyp = sk.torso_top.x + 1.0 * math.sin(rad(lean + pose.head)), sk.torso_top.y + 1.5
  n = n + seg(parts.head, colours.face, hxp, hyp, lean + pose.head, 0)
  -- near side
  n = n + seg(parts.thigh, colours.pants, 0, 0, sk.ln.th, -1.2)
  n = n + seg(parts.shin, colours.pants, sk.ln.kx, sk.ln.ky, sk.ln.sh, -1.2)
  n = n + seg(parts.uarm, colours.gi, sk.an.sx, sk.an.sy, sk.an.th, -2.6)
  n = n + seg(parts.farm, colours.glove, sk.an.ex, sk.an.ey, sk.an.fa, -2.6)
  return n
end

function M.shadow(x, scale)
  return call(parts.shadow, "TEX_SHADOW", x, 0.04, 0, 0)
end

return M
