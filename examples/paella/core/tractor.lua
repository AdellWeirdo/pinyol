-- tractor: el Tractor-Cañón. Land on it and you drive: it carries more weight than a chef (a bar of eight), fires a sardine cannon (A, up aims it high) and a vulcan (C), hops (B), and
-- flattens soldiers it rolls over. When its bar is empty it burns and blows, and the chef is thrown out.
local C = require("core.const")
local S = require("core.spr")
local Shots = require("core.shots")
local Foes = require("core.foes")
local Fx = require("core.fx")
local Sound = require("core.sound")
local Run = require("core.run")
local In = require("core.input")
local Hook = require("core.juice_hook")
local Music = require("core.music")
local T = {}

T.on_leave = nil     -- set by the scene: the zone's song comes back when the chef leaves or loses it
T.list = {}          -- parked tractors (one, in the main street)
T.active = nil       -- the one being driven

function T.clear() T.list = {} T.active = nil end

function T.park(x)
  local t = {x = x, y = C.FLOOR, vx = 0, vy = 0, hp = 8, state = "parked", st = 0, t = 0, dir = 1, cool = 0, vcool = 0, ground = true, chef = nil, aim_up = false}
  t.damage = function(n) T.damage(t, n) end
  t.seat_pos = function(cam)
    local sh = S.sheets.tractor
    local seat = (sh.seat_frames and t.frame and sh.seat_frames[t.frame]) or sh.seat or {90, 70}
    local px = seat[1] - sh.ax
    if t.dir < 0 then px = -px end
    return {t.x - cam + px, t.y + (seat[2] - sh.ay)}
  end
  T.list[#T.list + 1] = t
  return t
end

function T.board(chef, t)
  t.chef, t.state, t.st = chef, "enter", 0
  chef.vehicle = t
  chef.vx, chef.vy = 0, 0
  T.active = t
  Sound.play("horn", 0.6)
  Music.play("tractor", 400)
  Run.tractor_used = true
end

function T.damage(t, n)
  if t.state == "dying" or t.state == "boom" then return end
  t.hp = t.hp - n
  t.hit = 8
  Sound.play("clank", 0.6)
  Hook.shake(2)
  if t.hp <= 0 then T.explode(t) end
end

function T.explode(t)
  t.state, t.st = "boom", 0
  Fx.add("boom_l", t.x, t.y - 60)
  Sound.play("big", 0.8)
  Hook.shake(6)
  local ch = t.chef
  if ch then
    ch.vehicle = nil
    ch.x, ch.y, ch.vy, ch.vx, ch.ground = t.x, C.FLOOR - 30, -7, -2, false
    ch.inv = 120
    T.active = nil
  end
  t.chef = nil
  if T.on_leave then T.on_leave() end
end

function T.eject(t)
  local ch = t.chef
  t.state, t.st, t.nb = "exit", 0, 90
  if ch then
    ch.vehicle = nil
    ch.x = t.x - t.dir * 110
    ch.vy, ch.vx, ch.ground, ch.y = -7, ch.dir * 1.5, false, C.FLOOR - 40
    ch.inv = 30
  end
  t.chef = nil
  T.active = nil
  if T.on_leave then T.on_leave() end
end

-- where the cannon and the vulcan shoot from, in pixels from the tractor's anchor, facing right (the sheet's json may give its own)
local MUZ = {cannon = {112, -78}, cannon_up = {84, -128}, vulcan = {92, -74}}
local function muzzle(t, kind)
  local sh = S.sheets.tractor
  local fr = t.frame or "idle_0"
  if sh["muzzle_" .. kind] and sh["muzzle_" .. kind][fr] then return S.point("tractor", "muzzle_" .. kind, fr, t.x, t.y, t.dir < 0) end
  local m = MUZ[kind == "cannon" and t.aim_up and "cannon_up" or kind]
  return t.x + m[1] * t.dir, t.y + m[2]
end

function T.update(chef, cam)
  for i = #T.list, 1, -1 do
    local t = T.list[i]
    t.t = t.t + 1
    t.st = t.st + 1
    if t.fire_t then t.fire_t = t.fire_t + 1 end
    if t.hit and t.hit > 0 then t.hit = t.hit - 1 end
    if t.state == "parked" or t.state == "exit" then
      if t.state == "exit" and t.st > 14 then t.state, t.st = "parked", 0 end
      -- a chef landing on it from above takes the wheel
      if t.nb and t.nb > 0 then t.nb = t.nb - 1 end
      if chef.state == "play" and not chef.vehicle and (t.nb or 0) <= 0 and chef.vy > 0 and math.abs(chef.x - t.x) < 70 and chef.y > C.FLOOR - 96 and chef.y < C.FLOOR - 20 and t.hp > 0 then
        T.board(chef, t)
      end
    elseif t.state == "enter" then
      if t.st > 20 then t.state, t.st = "drive", 0 end
    elseif t.state == "drive" then
      local l, r, u, d = In.btn("left"), In.btn("right"), In.btn("up"), In.btn("down")
      local dx = (r and 1 or 0) - (l and 1 or 0)
      if dx ~= 0 then t.dir = dx end
      t.vx = dx * 3.4
      t.aim_up = u
      t.x = math.max(cam + 90, math.min(T.max_x or 1e9, t.x + t.vx))
      if In.btnp("b") and t.ground then
        if d then T.eject(t) else t.vy, t.ground = -9, false Sound.play("jump", 0.7) end
      end
      t.vy = math.min(t.vy + C.GRAVITY, C.MAX_FALL)
      t.y = t.y + t.vy
      if t.y >= C.FLOOR then t.y, t.vy, t.ground = C.FLOOR, 0, true end
      t.cool = t.cool - 1
      t.vcool = t.vcool - 1
      if In.btn("a") and t.cool <= 0 then
        t.cool, t.fire_t = 16, 0
        local mx, my = muzzle(t, "cannon")
        local dxn, dyn = t.dir, 0
        if t.aim_up then dxn, dyn = t.dir * 0.5, -0.87 end
        Shots.fire({name = "pot", speed = 12, dmg = 5, life = 60, gravity = 0.1, pierce = 1, pellets = 1, sfx = "cannon", r = 18, splash = 50}, mx, my, dxn, dyn,
                   {sheet = "shots", prefix = "pot", n = S.n("shots", "pot")})
        Hook.shake(2)
      end
      if In.btn("c") and t.vcool <= 0 then
        t.vcool, t.vfire = 4, 6
        local mx, my = muzzle(t, "vulcan")
        Shots.fire({name = "pea", speed = 14, dmg = 1, life = 36, gravity = 0, pierce = 0, pellets = 1, sfx = "vulcan", r = 8, jitter = 0.05}, mx, my, t.dir, 0)
      end
      if t.vfire and t.vfire > 0 then t.vfire = t.vfire - 1 end
      -- it flattens what it rolls over
      for _, f in ipairs(Foes.list) do
        if f.state ~= "dying" and f.d.ground and f.kind ~= "crab" and math.abs(f.x - t.x) < 80 and t.y >= C.FLOOR - 4 then
          f.die = "die_b"
          Foes.die(f, true)
        end
      end
      if t.hp <= 2 and t.t % 6 == 0 then Fx.add("smoke", t.x - 40 * t.dir, t.y - 70) end
    elseif t.state == "boom" then
      if t.st > 40 then table.remove(T.list, i) end
    end
  end
end

local function frame(t)
  local k = t.t
  local function seq(prefix, i) return S.seq("tractor", prefix, i) end
  local function upto(prefix, i) return prefix .. "_" .. math.max(0, math.min(S.n("tractor", prefix) - 1, i)) end
  if t.state == "boom" then return upto("explode", t.st // 5) end
  if t.state == "enter" or t.state == "exit" then return seq("idle", k // 6) end
  if t.hit and t.hit > 0 and S.has("tractor", "hit_0") then return "hit_0" end
  if t.state == "drive" then
    if t.hp <= 2 and S.n("tractor", "burning") > 0 then return seq("burning", k // 5) end
    if not t.ground then return upto("jump", t.vy < -2 and 0 or (t.vy < 2 and 1 or 2)) end
    if t.fire_t and t.fire_t < 10 then return t.aim_up and upto("cannon_up", t.fire_t // 4) or upto("fire", t.fire_t // 4) end
    if t.vfire and t.vfire > 0 then return upto("fire", (k // 2) % 2) end
    if math.abs(t.vx) > 0.1 then return seq("drive", k // 3) end
  end
  return seq("idle", k // 7)
end

function T.draw(cam)
  for _, t in ipairs(T.list) do
    t.frame = frame(t)
    S.draw("tractor", t.frame, t.x - cam, t.y, {flip = t.dir < 0})
  end
end

return T
