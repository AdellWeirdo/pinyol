-- hero: Zurrón. Walks, jumps (higher the longer A is held), rams with B (breaks brown blocks, stuns what it hits), smashes down in the air (breaks blue
-- ones), crawls, picks up what he has stunned and throws it, swims, burns. The sprite is 32x32 drawn round a 12x22 body.
local C = require("core.const")
local U = require("core.util")
local W = require("core.world")
local P = require("core.phys")
local S = require("core.spr")
local Fx = require("core.fx")
local Sound = require("core.sound")
local In = require("core.input")
local Run = require("core.run")
local H = {}

local SOLID, HURT = W.SOLID, W.HURT

function H.new(x, y)
  return {
    x = x - C.HW / 2, y = y - C.HH, w = C.HW, h = C.HH, vx = 0, vy = 0, face = 1, state = "move", st = 0, ground = false, coyote = 0, t = 0,
    hearts = C.HEARTS, inv = 0, carry = nil, burn = 0, drop = 0, land_t = 0, throw_t = 0, throw_up = false, lift_t = 0, crouch = false,
    safe_x = x, safe_y = y, safe_t = 0, in_water = false, dead_t = 0, ram_air = false, enter_t = 0, win_t = 0, mud = false, cut_jump = false,
    last_ground_y = y, swim_dir = 0, swim_ram = 0,
  }
end

function H.attacking(h) return h.state == "ram" or h.state == "smash" or h.burn > 0 or h.swim_ram > 0 end
function H.cx(h) return h.x + h.w / 2 end
function H.cy(h) return h.y + h.h / 2 end

local function set_size(h, nh)
  if nh == h.h then return end
  h.y = h.y + h.h - nh -- feet stay where they are
  h.h = nh
end

local function can_stand(h)
  return not P.hits_solid(h.x, h.y + h.h - C.HH, h.w, C.HH - 0.5)
end

-- breaks the cell, with its consequences (W.on_break is set by the level scene: coins out of a box, a jewel...)
local function break_cell(cx, cy, how)
  local c = W.cell(cx, cy)
  W.clear(cx, cy)
  Fx.burst("debris", cx * 16 + 8, cy * 16 + 8, 4, 1.6)
  Fx.add("poof", cx * 16 + 8, cy * 16 + 8)
  Sound.play("brk")
  if W.on_break then W.on_break(cx, cy, c, how) end
end
H.break_cell = break_cell

local function hurt(h, from_x, dmg)
  if h.inv > 0 or h.state == "dead" or h.state == "win" then return false end
  h.hearts = h.hearts - (dmg or 1)
  Run.hits = Run.hits + 1
  Sound.play("hurt")
  Fx.add("hit", H.cx(h), H.cy(h))
  if h.carry then h.carry.state = "stun" h.carry.st = 120 h.carry = nil end
  if h.hearts <= 0 then
    h.state, h.st, h.vx, h.vy = "dead", 0, 0, -4.5
    Sound.play("die")
    return true
  end
  h.state, h.st, h.inv = "hurt", 0, C.HURT_TICKS
  h.vx = (H.cx(h) < from_x and -1 or 1) * 1.8
  h.vy = -3.2
  h.burn = 0
  W.shake(1, 8)
  return true
end
H.hurt = hurt

function H.ignite(h)
  if h.burn <= 0 then Sound.play("fire") end
  h.burn = 260
  if h.carry then h.carry.state = "stun" h.carry.st = 120 h.carry = nil end
end

local function pick_up(h, foes)
  local e = foes.nearest_carryable(h)
  if not e then return false end
  h.carry, e.state, h.lift_t = e, "held", 14
  e.vx, e.vy = 0, 0
  Sound.play("grab")
  return true
end

local function throw(h, up)
  local e = h.carry
  if not e then return end
  e.state, e.owner_t = "thrown", 0
  if up then e.vx, e.vy = h.vx * 0.4, -5.4 else e.vx, e.vy = h.face * 3.8 + h.vx * 0.3, -1.0 end
  e.x, e.y = H.cx(h) - e.w / 2 + (up and 0 or h.face * 6), h.y - (up and e.h or e.h * 0.4)
  h.carry, h.throw_t, h.throw_up = nil, 14, up
  Sound.play("throw")
end

-- ------------------------------------------------------------------ the states

local function horizontal(h, l, r)
  local dir = (r and 1 or 0) - (l and 1 or 0)
  local top = C.WALK
  if h.carry then top = C.CARRY end
  if h.crouch then top = C.CRAWL end
  if h.mud then top = top * 0.5 end
  if dir ~= 0 then
    h.face = dir
    local acc = h.ground and C.WALK_ACCEL or C.AIR_ACCEL
    if math.abs(h.vx) > top and U.sign(h.vx) == dir then
      h.vx = U.approach(h.vx, dir * top, 0.03) -- momentum from a ram or a spring fades slowly
    else
      h.vx = U.approach(h.vx, dir * top, acc)
    end
  elseif h.ground then
    h.vx = U.approach(h.vx, 0, C.FRICTION)
  else
    h.vx = U.approach(h.vx, 0, 0.03)
  end
end

local function try_jump(h)
  if In.btnb("a", C.BUFFER) and (h.coyote > 0) then
    h.vy = h.mud and C.JUMP * 0.72 or C.JUMP
    h.ground, h.coyote, h.cut_jump = false, 0, false
    Sound.play("jump")
    Fx.add("dust", H.cx(h), h.y + h.h - 3)
    return true
  end
  return false
end

local function move_body(h)
  -- across
  local steps = 0
  while steps < 3 do
    steps = steps + 1
    local cx, cy, c = P.move_x(h, steps == 1 and h.vx or 0)
    if not cx then break end
    local breaks = W.BREAKABLE[c] and (h.state == "ram" or h.swim_ram > 0 or (h.burn > 0 and (c == "F" or c == "b")))
    if breaks and c ~= "B" then
      break_cell(cx, cy, "ram")
      -- the body is two cells tall: the other cell it touches goes too
      local ox, oy, oc = P.hits_solid(h.x + h.vx, h.y, h.w, h.h)
      if ox and W.BREAKABLE[oc] and oc ~= "B" then break_cell(ox, oy, "ram") end
      h.x = h.x + h.vx
      W.shake(1, 5)
      break
    end
    if h.state == "ram" then
      Sound.play("land")
      Fx.add("impact", H.cx(h) + h.face * 8, H.cy(h))
      W.shake(1, 6)
      h.state, h.st = "move", 0
    end
    h.vx = 0
    break
  end
  -- up and down
  h.ground = false
  local cx, cy, c = P.move_y(h, h.vy)
  if cx then
    if h.vy < 0 then
      if c == "b" or c == "K" or c == "J" then break_cell(cx, cy, "head") end
      h.vy = 0.2
    else
      if h.state == "smash" and W.BREAKABLE[c] then
        break_cell(cx, cy, "smash")
        local ox, oy, oc = P.hits_solid(h.x, h.y + h.h, h.w, 1)
        if ox and W.BREAKABLE[oc] then break_cell(ox, oy, "smash") end
        h.vy = C.SMASH
      else
        h.ground = true
        if c == "s" then
          h.vy, h.ground = C.SPRING, false
          Sound.play("spring")
          Fx.add("sparkle", H.cx(h), h.y + h.h)
        else
          if h.vy > 3 then h.land_t = 8 Sound.play("land") Fx.add("dust", H.cx(h) - 5, h.y + h.h - 2) Fx.add("dust", H.cx(h) + 5, h.y + h.h - 2) end
          h.vy = 0
        end
        h.mud = c == "m"
      end
    end
  end
end

local function hazards(h)
  if h.state == "dead" then return end
  if P.touches(h.x + 2, h.y + 2, h.w - 4, h.h - 3, {S = true}) then
    h.vy = math.max(h.vy - 0.55, -3.6)
    if h.t % 6 == 0 then Fx.add("smoke", H.cx(h), h.y + h.h) end
  end
  local cx, cy, c = P.touches(h.x + 2, h.y + 2, h.w - 4, h.h - 3, HURT)
  if cx and h.inv == 0 then
    -- spikes and lava cost a heart and put him back on the last safe ground (a pit with spikes is never a trap)
    if c == "L" then H.ignite(h) end
    if hurt(h, cx * 16 + 8) and h.state ~= "dead" then
      h.x, h.y, h.vx, h.vy = h.safe_x - h.w / 2, h.safe_y - h.h, 0, 0
      h.state, h.st = "hurt", 0
    end
  end
  if h.y > W.px_h + 24 then
    -- fell out of the level: back to the last safe ground, one heart less
    if hurt(h, h.x + 1) and h.state ~= "dead" then
      h.x, h.y, h.vx, h.vy = h.safe_x - h.w / 2, h.safe_y - h.h, 0, 0
    end
  end
end

-- ------------------------------------------------------------------ swimming

local function swim(h, l, r, u, d)
  local dirx = (r and 1 or 0) - (l and 1 or 0)
  if dirx ~= 0 then h.face = dirx end
  h.vx = U.approach(h.vx, dirx * C.SWIM_SPEED, 0.07)
  if not (l or r) then h.vx = h.vx * 0.96 end
  if In.btnp("b") and h.swim_ram == 0 and not h.carry then -- a ram under water: it breaks the brown blocks that close the Galleon's sea
    h.swim_ram = C.RAM_TICKS
    Sound.play("ram")
    Fx.add("bubble", H.cx(h) - h.face * 6, H.cy(h))
  end
  if h.swim_ram > 0 then h.vx = h.face * C.SWIM_SPEED * 2.2 end
  if In.btnp("a") then
    h.vy = C.SWIM_KICK
    Sound.play("swim")
    Fx.add("bubble", H.cx(h) - h.face * 4, h.y + 3)
  end
  if d then h.vy = h.vy + 0.05 end
  h.vy = U.clamp(h.vy + C.SWIM_GRAV, -2.4, C.SWIM_MAX)
  -- the sea's currents push
  local _, _, cc = P.touches(h.x + 2, h.y + 2, h.w - 4, h.h - 4, {l = true, r = true, u = true})
  if cc == "l" then h.vx = h.vx - 0.07 elseif cc == "r" then h.vx = h.vx + 0.07 elseif cc == "u" then h.vy = h.vy - 0.08 end
  move_body(h)
  h.ground = P.grounded(h, 1)
  if math.random(40) == 1 then Fx.add("bubble", H.cx(h), h.y) end
end

-- ------------------------------------------------------------------ the update

function H.update(h, foes)
  h.t = h.t + 1
  h.st = h.st + 1
  if h.inv > 0 then h.inv = h.inv - 1 end
  if h.drop > 0 then h.drop = h.drop - 1 end
  if h.land_t > 0 then h.land_t = h.land_t - 1 end
  if h.throw_t > 0 then h.throw_t = h.throw_t - 1 end
  if h.lift_t > 0 then h.lift_t = h.lift_t - 1 end
  if h.swim_ram > 0 then h.swim_ram = h.swim_ram - 1 end
  local l, r, u, d = In.btn("left"), In.btn("right"), In.btn("up"), In.btn("down")

  if h.state == "dead" then
    h.dead_t = h.dead_t + 1
    h.vy = math.min(h.vy + C.GRAVITY, C.MAX_FALL)
    if h.dead_t > 10 then h.y = h.y + h.vy end
    return
  end
  if h.state == "win" then
    h.win_t = h.win_t + 1
    return
  end
  if h.state == "enter" then
    h.enter_t = h.enter_t + 1
    if h.enter_t > 40 then h.state, h.st = "move", 0 end
    return
  end

  local was_water = h.in_water
  h.in_water = W.in_water(h.y + h.h * 0.4)
  if h.in_water ~= was_water then
    Fx.add("splash", H.cx(h), W.water_y or h.y + h.h)
    Sound.play("splash")
    if h.in_water then h.burn = 0 end
  end

  if h.state == "hurt" then
    h.vy = math.min(h.vy + C.GRAVITY, C.MAX_FALL)
    move_body(h)
    if h.st > 18 and h.ground then h.state, h.st = "move", 0 end
    if h.st > 40 then h.state, h.st = "move", 0 end
    hazards(h)
    return
  end

  if h.in_water then
    h.state = "move"
    swim(h, l, r, u, d)
    hazards(h)
    return
  end

  h.coyote = h.ground and C.COYOTE or math.max(h.coyote - 1, 0)
  local _, below = P.grounded(h, 2)
  if h.ground and below ~= "m" then h.mud = false end

  -- crouching
  if h.state == "move" or h.state == "burn" then
    local want = d and h.ground and not h.carry
    if want and not h.crouch then set_size(h, C.CROUCH_H) h.crouch = true
    elseif not want and h.crouch and can_stand(h) then set_size(h, C.HH) h.crouch = false end
  end

  if h.burn > 0 then
    -- burning: runs on its own in the direction he faces, jumps, and cannot be steered
    h.burn = h.burn - 1
    h.vx = U.approach(h.vx, h.face * 2.3, 0.2)
    if In.btnp("left") then h.face = -1 elseif In.btnp("right") then h.face = 1 end
    if try_jump(h) then end
    if math.random(4) == 1 then Fx.add("ember", H.cx(h) - h.face * 4, h.y + 12, {vy = -0.3}) end
    if not In.btn("a") and h.vy < C.JUMP_CUT then h.vy = C.JUMP_CUT end
    h.vy = math.min(h.vy + C.GRAVITY, C.MAX_FALL)
    move_body(h)
    if h.burn == 0 then Fx.add("smoke", H.cx(h), h.y + 4) end
    hazards(h)
    return
  end

  if h.state == "ram" then
    h.vx = h.face * C.RAM
    if try_jump(h) then h.ram_air = true end
    if not In.btn("a") and h.vy < C.JUMP_CUT then h.vy = C.JUMP_CUT end
    h.vy = math.min(h.vy + C.GRAVITY, C.MAX_FALL)
    if h.st % 4 == 0 then Fx.add("speed", H.cx(h) - h.face * 12, H.cy(h), {flip = h.face < 0}) end
    move_body(h)
    if h.state == "ram" and h.st >= C.RAM_TICKS and h.ground then
      if In.btn("b") and (l or r) then h.st = C.RAM_TICKS - 8 else h.state, h.st = "move", 0 end
    end
    hazards(h)
    return
  end

  if h.state == "smash" then
    h.vx = 0
    h.vy = C.SMASH
    move_body(h)
    if h.ground then
      h.state, h.st = "smash_land", 0
      Sound.play("smash")
      W.shake(2, 14)
      Fx.add("smash", H.cx(h), h.y + h.h - 6)
      foes.stun_near(H.cx(h), h.y + h.h, 64)
      shock(H.cx(h) - W.cam_x, h.y + h.h - W.cam_y, 4, 10, 4)
    end
    hazards(h)
    return
  end
  if h.state == "smash_land" then
    h.vx = 0
    if h.st > 12 then h.state, h.st = "move", 0 end
    return
  end

  -- the normal state
  local dirx = (r and 1 or 0) - (l and 1 or 0)
  horizontal(h, l, r)
  if d and In.btnp("a") and h.ground and below == "=" and not h.carry then
    h.drop, h.y = 10, h.y + 1
    h.ground = false
  elseif not h.crouch then
    try_jump(h)
  end
  if not In.btn("a") and h.vy < C.JUMP_CUT and not h.ground and not h.cut_jump then h.vy, h.cut_jump = C.JUMP_CUT, true end
  h.vy = math.min(h.vy + C.GRAVITY, C.MAX_FALL)

  if In.btnp("b") then
    if h.carry then
      throw(h, u)
    elseif foes and pick_up(h, foes) then
      -- picked up
    elseif h.ground and not h.crouch then
      h.state, h.st, h.vx = "ram", 0, h.face * C.RAM
      Sound.play("ram")
      Fx.add("dust", H.cx(h) - h.face * 8, h.y + h.h - 3)
    end
  end
  if d and not h.ground and not h.carry and h.vy > -2 and In.btnp("down") then
    h.state, h.st = "smash", 0
    h.vx = 0
  end
  move_body(h)
  if h.ground and h.state == "move" and dirx ~= 0 and h.t % 10 == 0 and math.abs(h.vx) > 0.8 then
    Fx.add("dust", H.cx(h) - h.face * 5, h.y + h.h - 2)
  end
  -- remember a safe place to come back to after a fall
  if h.ground and not h.mud then
    h.safe_t = h.safe_t + 1
    if h.safe_t > 24 and not P.touches(h.x - 20, h.y, h.w + 40, h.h + 4, HURT) then h.safe_x, h.safe_y = H.cx(h), h.y + h.h end
  else
    h.safe_t = 0
  end
  hazards(h)
end

-- ------------------------------------------------------------------ the picture

function H.frame(h)
  local t = h.t
  local s = h.state
  if s == "dead" then return "die_" .. math.min(5, h.dead_t // 7) end
  if s == "win" then return "win_" .. ((h.win_t // 6) % 6) end
  if s == "hurt" then return "hurt_" .. ((h.st // 5) % 2) end
  if s == "enter" then return "fall_" .. ((t // 6) % 2) end
  if s == "smash" then return "smash_" .. math.min(2, h.st // 3) end
  if s == "smash_land" then return "land_1" end
  if h.burn > 0 then return "fire_run_" .. ((t // 4) % 6) end
  if s == "ram" then return "ram_" .. ((t // 4) % 4) end
  if h.in_water then
    if math.abs(h.vx) > 0.2 or h.vy < -0.2 then return "swim_" .. ((t // 4) % 8) end
    return "swim_idle_" .. ((t // 8) % 4)
  end
  if h.throw_t > 0 then
    local k = math.min(3, (14 - h.throw_t) // 4)
    if h.throw_up then return "throw_up_" .. math.min(2, k) end
    return "throw_" .. k
  end
  if h.lift_t > 0 then return "lift_" .. math.min(2, (14 - h.lift_t) // 5) end
  if h.carry then
    if h.ground and math.abs(h.vx) > 0.1 then return "grab_walk_" .. ((t // 4) % 6) end
    return "grab_idle_" .. ((t // 12) % 2)
  end
  if h.crouch then
    if math.abs(h.vx) > 0.1 then return "crawl_" .. ((t // 5) % 6) end
    return "crouch"
  end
  if not h.ground then
    if h.vy < -1 then return "jump_up" end
    if h.vy < 1 then return "jump_peak" end
    return "fall_" .. ((t // 6) % 2)
  end
  if h.land_t > 0 then return "land_" .. (h.land_t > 4 and 0 or 1) end
  if math.abs(h.vx) > 2 then return "run_" .. ((t // 3) % 6) end
  if math.abs(h.vx) > 0.1 then return "walk_" .. ((t // 4) % 8) end
  return "idle_" .. ((t // 10) % 6)
end

function H.draw(h, cx, cy)
  if h.inv > 0 and h.state ~= "dead" and (h.inv // 3) % 2 == 0 then return end
  local bank = h.burn > 0 and "zurron_fuego" or nil
  if h.state == "hurt" and h.st < 6 then bank = "zurron_golpe" end
  S.draw("HERO", H.frame(h), h.x + h.w / 2 - 16 - cx, h.y + h.h - 32 - cy, {flip = h.face < 0, bank = bank})
end

return H
