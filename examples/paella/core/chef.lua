-- chef: the player. A chef is two sprites pinned at the hips, as Metal Slug did it: legs (idle, run, crawl, jump) and a torso (idle, aim in four directions, fire, throw, stab) so every
-- aim works with every leg animation. A hit kills (one life), a grenade is a pressure cooker, the knife stabs what is close, and the Maestro's paellera blocks what comes at his front.
local C = require("core.const")
local S = require("core.spr")
local W = require("core.weapons")
local Shots = require("core.shots")
local Foes = require("core.foes")
local Fx = require("core.fx")
local Sound = require("core.sound")
local In = require("core.input")
local Run = require("core.run")
local Hook = require("core.juice_hook")
local Music = require("core.music")
local Chef = {}

local self_ = nil

function Chef.new(id, x)
  local c = {id = id, x = x, y = C.FLOOR, vx = 0, vy = 0, dir = 1, crouch = false, ground = true, t = 0, cool = 0, grenades = C.GRENADES, lives = C.LIVES, state = "play",
             inv = 0, aim = "fwd", fire_t = 99, stab_t = 0, throw_t = 0, throw_done = false, weapon = W.DEFS[id], base = W.DEFS[id], up_shots = 0, shield = 0, dead_t = 0,
             vehicle = nil, land_t = 0, win_t = 0, moving = false, stabbed = nil}
  c.hurt, c.hit_box, c.blocks, c.hurt_at = Chef.hurt, Chef.hit_box, Chef.blocks, Chef.hurt_at
  self_ = c
  return c
end

function Chef.get() return self_ end

local function dims(c) return C.HERO_W, c.crouch and C.CROUCH_H or C.HERO_H end

function Chef.hit_box()
  local c = self_
  if c.vehicle then return c.vehicle.x - 70, C.FLOOR - 90, 140, 90 end
  local w, h = dims(c)
  return c.x - w / 2, c.y - h, w, h
end

function Chef.hurt()
  local c = self_
  if c.state ~= "play" or c.inv > 0 then return end
  if c.vehicle then c.vehicle.damage(1) return end
  if c.shield > 0 then
    c.shield, c.inv = 0, 60
    Fx.add("hit", c.x, c.y - 40)
    Sound.play("clank", 0.6)
    return
  end
  c.state, c.dead_t, c.vy, c.vx = "dead", 0, -6, -c.dir * 1.5
  c.ground = false
  Run.deaths = Run.deaths + 1
  Sound.play("die", 0.8)
  Music.jingle("muerte", 2)
  Hook.shake(4)
  c.lives = c.lives - 1
end

function Chef.hurt_at(x, y, r)
  local c = self_
  local bx, by, bw, bh = Chef.hit_box()
  if math.abs(bx + bw / 2 - x) < r + bw / 2 and math.abs(by + bh / 2 - y) < r + bh / 2 then Chef.hurt() end
end

-- does the Maestro's pan stop this shot? (crouching, facing it)
function Chef.blocks(s)
  local c = self_
  if c.id ~= "arrocero" or not c.crouch or not c.ground then return false end
  return (s.x - c.x) * c.dir > 0
end
Chef.hit_box_fn = Chef.hit_box

function Chef.pickup_weapon(c, kind)
  c.weapon = W.upgrade(c.base, kind)
  c.up_shots = 60
  Sound.play("pickup")
  Music.jingle("arma", 1)
end

local function muzzle(c)
  local fr = c.torso_frame or "aim_fwd"
  local ox, oy = S.point("chef_" .. c.id .. "_torso", "muzzle", fr, c.x, c.y - 56, c.dir < 0)
  return ox, oy
end

local function fire(c)
  local w = c.weapon
  c.cool = w.every
  c.fire_t = 0
  local dx, dy = c.dir, 0
  if c.aim == "up" then dx, dy = 0, -1 elseif c.aim == "down" then dx, dy = 0, 1 elseif c.aim == "diag" then dx, dy = c.dir * 0.7071, -0.7071 end
  local mx, my = muzzle(c)
  local angle = (c.aim ~= "fwd") and math.floor(math.deg(math.atan(dy, dx)) + 0.5) or nil
  Shots.fire(w, mx, my, dx, dy, {angle = angle})
  if c.up_shots > 0 then
    c.up_shots = c.up_shots - 1
    if c.up_shots == 0 then c.weapon = c.base end
  end
end

local function stab(c, f)
  c.stab_t = 14
  c.cool = 14
  Sound.play("stab", 0.5)
  Foes.hit_at(f.x, f.y - 40, 30, 4, nil)
  Fx.add("hit", f.x, f.y - 44)
end

function Chef.update(c, cam, vehicle_now)
  c.t = c.t + 1
  if c.god then c.inv = 99 end
  if c.inv > 0 then c.inv = c.inv - 1 end
  c.cool = c.cool - 1
  c.fire_t = c.fire_t + 1
  if c.stab_t > 0 then c.stab_t = c.stab_t - 1 end
  if c.land_t > 0 then c.land_t = c.land_t - 1 end
  if c.state == "dead" then
    c.dead_t = c.dead_t + 1
    c.vy = math.min(c.vy + C.GRAVITY, C.MAX_FALL)
    c.x, c.y = c.x + c.vx, math.min(C.FLOOR, c.y + c.vy)
    if c.y >= C.FLOOR then c.vx = c.vx * 0.8 end
    return
  end
  if c.state == "win" then c.win_t = c.win_t + 1 return end
  if c.vehicle then
    c.aim = In.btn("up") and "up" or "fwd"
    c.x = c.vehicle.x
    return
  end
  local l, r, u, d = In.btn("left"), In.btn("right"), In.btn("up"), In.btn("down")
  local dx = (r and 1 or 0) - (l and 1 or 0)
  c.crouch = d and c.ground
  if dx ~= 0 then c.dir = dx end
  local sp = c.crouch and C.CRAWL or C.WALK
  local want = c.crouch and dx * sp or dx * sp
  if c.stab_t > 0 or (c.throw_t > 0 and c.ground) then want = want * 0.3 end
  c.vx = want
  c.moving = dx ~= 0
  c.aim = (u and not c.crouch) and (dx ~= 0 and "diag" or "up") or ((d and not c.ground) and "down" or "fwd")
  -- jump
  if In.btnp("b") and c.ground and not c.crouch then
    c.vy, c.ground = C.JUMP, false
    Sound.play("jump")
  end
  if not In.btn("b") and c.vy < -4.5 then c.vy = -4.5 end
  c.vy = math.min(c.vy + C.GRAVITY, C.MAX_FALL)
  c.x = math.max(cam + 26, math.min(Chef.max_x or 1e9, c.x + c.vx))
  c.y = c.y + c.vy
  if c.y >= C.FLOOR then
    if not c.ground and c.vy > 4 then c.land_t = 5 Fx.add("smoke", c.x, c.y - 6) end
    c.y, c.vy, c.ground = C.FLOOR, 0, true
  end
  -- shooting, stabbing, grenades
  if In.btn("a") and c.cool <= 0 and c.stab_t == 0 then
    local f = (c.aim == "fwd" and not c.crouch) and Foes.in_reach(c.x, c.y, c.dir, 62) or nil
    if f then stab(c, f) else fire(c) end
  end
  if In.btnp("c") and c.grenades > 0 and c.throw_t == 0 then
    c.throw_t, c.throw_done = 16, false
  end
  if c.throw_t > 0 then
    c.throw_t = c.throw_t - 1
    if not c.throw_done and c.throw_t <= 9 then
      c.throw_done = true
      c.grenades = c.grenades - 1
      local hx, hy = S.point("chef_" .. c.id .. "_torso", "grenade_hand", "throw_1", c.x, c.y - 56, c.dir < 0)
      Shots.pot(hx, hy, c.dir * 4.4 + c.vx * 0.5, -6.5)
      Sound.play("throw", 0.5)
    end
  end
end

-- ------------------------------------------------------------------ the picture

local function legs_frame(c)
  if not c.ground then
    if c.vy < -3 then return "jump_0" elseif c.vy < 0 then return "jump_1" elseif c.vy < 4 then return "jump_2" end
    return "jump_2"
  end
  if c.land_t > 0 then return "jump_3" end
  if c.crouch then
    if c.moving then return "crawl_" .. (c.t // 5) % 6 end
    return "crouch"
  end
  if c.moving then return "run_" .. (c.t // 3) % 8 end
  return "idle"
end

local function torso_frame(c)
  local k = (c.fire_t // 2) % 3
  if c.throw_t > 0 then return "throw_" .. math.min(3, (16 - c.throw_t) // 4) end
  if c.stab_t > 0 then return "stab_" .. math.min(3, (14 - c.stab_t) // 4) end
  local firing = c.fire_t < 10
  if c.crouch then return firing and ("crouch_fire_" .. k) or ("crouch_" .. (c.t // 14) % 2) end
  if c.aim == "up" or c.aim == "diag" then return firing and ("fire_up_" .. k) or "aim_up" end
  if c.aim == "down" then return firing and ("fire_down_" .. k) or "aim_down" end
  if firing then return "fire_fwd_" .. k end
  if not c.ground then return "jump_" .. ((c.vy < 0) and 0 or 1) end
  if c.moving then return "run_" .. (c.t // 3) % 8 end
  return "idle_" .. (c.t // 10) % 4
end

function Chef.draw(c, cam)
  local sx = c.x - cam
  if c.state == "dead" then
    S.draw("chef_" .. c.id .. "_full", "die_" .. math.min(7, c.dead_t // 5), sx, c.y, {flip = c.dir < 0})
    return
  end
  if c.state == "win" then
    S.draw("chef_" .. c.id .. "_full", "win_" .. (c.win_t // 6) % 6, sx, c.y, {})
    return
  end
  if c.inv > 0 and (c.inv // 4) % 2 == 0 then return end
  local flip = c.dir < 0
  local id = "chef_" .. c.id
  if c.vehicle then
    local sh = c.vehicle.seat_pos(cam)
    c.torso_frame = c.aim == "up" and "aim_up" or "aim_fwd"
    S.draw(id .. "_torso", c.torso_frame, sh[1], sh[2], {flip = false})
    return
  end
  c.torso_frame = torso_frame(c)
  -- drawn in the order of painting: the legs, then the torso over them
  S.draw(id .. "_legs", legs_frame(c), sx, c.y - 56, {flip = flip})
  S.draw(id .. "_torso", c.torso_frame, sx, c.y - 56, {flip = flip})
  if c.shield > 0 then S.draw("items", "shield_" .. (c.t // 6) % 4, sx, c.y - 30, {alpha = 0.7}) end
end

return Chef
