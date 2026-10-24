-- foes: the Gaviotas Mecánicas. The soldier walks up and pecks or shoots pellets, the bazooka kneels and fires rockets, the drone flies over and drops fish-bombs, the kamikaze
-- winds up and dives, the crab tank rolls in and lobs shells. A hit kills a soldier at once (they die in funny ways); the bigger ones take several.
local C = require("core.const")
local S = require("core.spr")
local Fx = require("core.fx")
local Sound = require("core.sound")
local Shots = require("core.shots")
local Run = require("core.run")
local Foes = {}

Foes.list = {}
Foes.items = nil    -- set by the scene: Foes.items.drop(x, y)

-- kind: sheet, hitbox (w, h; on the ground: x centre, y feet; flyers: centred), life, score
local DEF = {
  soldier = {sheet = "gull_soldier", w = 40, h = 80, hp = 1, score = 100, ground = true},
  bazooka = {sheet = "gull_bazooka", w = 46, h = 66, hp = 2, score = 200, ground = true},
  drone = {sheet = "gull_drone", w = 84, h = 52, hp = 2, score = 200, fly = true},
  kamikaze = {sheet = "gull_kamikaze", w = 62, h = 44, hp = 1, score = 150, fly = true},
  crab = {sheet = "crab_tank", w = 130, h = 74, hp = 14, score = 1000, ground = true},
}
Foes.DEF = DEF

function Foes.clear() for i = #Foes.list, 1, -1 do Foes.list[i] = nil end end

function Foes.spawn(kind, x, y, extra)
  local d = DEF[kind]
  local f = {kind = kind, d = d, x = x, y = y or C.FLOOR, vx = 0, vy = 0, dir = -1, hp = d.hp, state = "walk", st = 0, t = 0, cool = 50 + math.random(70), flash = 0,
             stop = 170 + math.random(140), hit = 0, die = math.random(2) == 1 and "die_a" or "die_b"}
  if extra then for k, v in pairs(extra) do f[k] = v end end
  if kind == "soldier" and math.random(100) <= 25 then f.coward = true end
  if kind == "bazooka" then f.state = "aim" elseif kind == "kamikaze" then f.state = "hover" elseif kind == "drone" then f.state = "fly" f.base_y = f.y end
  if kind == "crab" then f.state = "move" end
  Foes.list[#Foes.list + 1] = f
  return f
end

-- from a level event: ("soldier", "r", 40)
function Foes.spawn_at(kind, where, off, cam)
  local d = DEF[kind]
  if where == "r" then return Foes.spawn(kind, cam + C.W + 40 + off, C.FLOOR) end
  if where == "l" then return Foes.spawn(kind, cam - 40 - off, C.FLOOR, {dir = 1}) end
  if where == "air" then return Foes.spawn(kind, cam + C.W + 40 + off, 70 + math.random(0, 70)) end
  return Foes.spawn(kind, where, C.FLOOR)
end

local function box(f)
  local d = f.d
  if d.fly then return f.x - d.w / 2, f.y - d.h / 2, d.w, d.h end
  return f.x - d.w / 2, f.y - d.h, d.w, d.h
end
Foes.box = box

function Foes.die(f, by_tractor)
  if f.state == "dying" then return end
  f.state, f.st = "dying", 0
  Run.add(f.d.score)
  Run.kills = Run.kills + 1
  if by_tractor then Run.tractor_kills = Run.tractor_kills + 1 end
  local big = f.kind == "crab"
  Fx.add(big and "boom_l" or "feathers", f.x, f.y - (f.d.fly and 0 or 40))
  if f.d.fly or big or f.die == "die_a" then Fx.add("boom_s", f.x, f.y - (f.d.fly and 0 or 36)) end
  Sound.play(big and "big" or "hit", 0.6)
  if Foes.items then Foes.items.drop(f.x, f.y, f.kind) end
  if f.on_death then f.on_death(f) end
end

-- damage from a shot at (x, y) with radius r: returns hit, killed. `seen` is the shot's list of foes it already hit (a piercing shot hits each once)
function Foes.hit_at(x, y, r, dmg, seen)
  for _, f in ipairs(Foes.list) do
    if f.state ~= "dying" and not (seen and seen[f]) then
      local bx, by, bw, bh = box(f)
      if x + r > bx and x - r < bx + bw and y + r > by and y - r < by + bh then
        if seen then seen[f] = true end
        f.hp = f.hp - dmg
        f.flash = 3
        Sound.play("hit", 0.3)
        if f.hp <= 0 then Foes.die(f) return true, true end
        if f.d.ground and f.kind == "soldier" then f.hit = 8 end
        return true, false
      end
    end
  end
  return false, false
end

function Foes.blast(x, y, r, dmg)
  for _, f in ipairs(Foes.list) do
    if f.state ~= "dying" then
      local bx, by, bw, bh = box(f)
      local cx, cy = bx + bw / 2, by + bh / 2
      if math.abs(cx - x) < r + bw / 2 and math.abs(cy - y) < r + bh / 2 then
        f.hp = f.hp - dmg
        if f.hp <= 0 then Foes.die(f) end
      end
    end
  end
end

-- is something (a grenade) touching a foe?
function Foes.touching(x, y, r)
  for _, f in ipairs(Foes.list) do
    if f.state ~= "dying" then
      local bx, by, bw, bh = box(f)
      if x + r > bx and x - r < bx + bw and y + r > by and y - r < by + bh then return true end
    end
  end
  return false
end

-- is there a living soldier within `d` pixels in front of the chef? (the knife)
function Foes.in_reach(x, y, dir, d)
  for _, f in ipairs(Foes.list) do
    if f.state ~= "dying" and f.d.ground then
      local dx = (f.x - x) * dir
      if dx > -10 and dx < d and math.abs(f.y - y) < 20 then return f end
    end
  end
  return nil
end

function Foes.count()
  local n = 0
  for _, f in ipairs(Foes.list) do if f.state ~= "dying" then n = n + 1 end end
  return n
end

-- ------------------------------------------------------------------ the minds

local function face(f, chef) f.dir = chef.x < f.x and -1 or 1 end

local AI = {}

function AI.soldier(f, chef)
  if f.hit > 0 then f.hit = f.hit - 1 end
  local d = chef.x - f.x
  if f.state == "surrender" then
    -- a coward: the pea-shooter on the ground, wings up and a white sock on the key; left alone it leaves a dish and runs
    f.st = f.st + 1
    if f.st > 170 then
      if Foes.items then Foes.items.add("food", f.x, C.FLOOR - 40, {food = "sardine", vy = -3}) end
      Sound.play("food", 0.5)
      f.state, f.st = "flee", 0
    end
    return
  elseif f.state == "flee" then
    f.dir = chef.x < f.x and 1 or -1
    f.x = f.x + f.dir * 2.4
    return
  end
  if f.state == "walk" then
    face(f, chef)
    if f.coward and math.abs(d) < 220 and chef.state == "play" then f.state, f.st = "surrender", 0 return end
    if math.abs(d) > f.stop then f.x = f.x + f.dir * 1.4 end
    f.cool = f.cool - 1
    if math.abs(d) < 56 and chef.state == "play" then f.state, f.st = "peck", 0
    elseif f.cool <= 0 and math.abs(d) < 400 and f.x > (Foes.cam or 0) - 10 and f.x < (Foes.cam or 0) + C.W + 10 then f.state, f.st, f.cool = "shoot", 0, 90 + math.random(80) end
  elseif f.state == "shoot" then
    f.st = f.st + 1
    if f.st == 12 then
      Shots.hostile("pea", f.x + f.dir * 42, f.y - 52, f.dir * 4.6, 0)
      Sound.play("pea", 0.4)
    end
    if f.st > 24 then f.state = "walk" end
  elseif f.state == "peck" then
    f.st = f.st + 1
    if f.st == 10 and math.abs(chef.x - f.x) < 64 and chef.y - f.y > -40 then chef.hurt() end
    if f.st > 20 then f.state, f.cool = "walk", 30 end
  end
end

function AI.bazooka(f, chef)
  face(f, chef)
  f.st = f.st + 1
  if f.state == "aim" then
    if f.st > 52 then f.state, f.st = "fire", 0 end -- a longer wind-up: the first bazooka was half of all the deaths
  elseif f.state == "fire" then
    if f.st == 8 then
      Shots.hostile("rocket", f.x + f.dir * 44, f.y - 40, f.dir * 4.2, 0)
      Sound.play("rocket", 0.5)
    end
    if f.st > 28 then f.state, f.st = "reload", 0 end
  elseif f.state == "reload" then
    if f.st > 70 then f.state, f.st = "aim", 0 end
  end
end

function AI.drone(f, chef)
  face(f, chef)
  local tx = chef.x + math.sin(f.t / 40) * 140
  f.x = f.x + math.max(-1.7, math.min(1.7, (tx - f.x) * 0.02 + f.dir * 0.4))
  f.y = f.base_y + math.sin(f.t / 22) * 12
  f.cool = f.cool - 1
  if f.state == "fly" and f.cool <= 0 and math.abs(chef.x - f.x) < 60 then f.state, f.st, f.cool = "drop", 0, 100 + math.random(60) end
  if f.state == "drop" then
    f.st = f.st + 1
    if f.st == 8 then Shots.hostile("bomb", f.x, f.y + 20, f.vx * 0.5, 1) end
    if f.st > 16 then f.state = "fly" end
  end
end

function AI.kamikaze(f, chef)
  f.st = f.st + 1
  face(f, chef)
  if f.state == "hover" then
    f.y = f.y + math.sin(f.t / 12) * 0.5
    if f.st > 70 then f.state, f.st = "windup", 0 end
  elseif f.state == "windup" then
    if f.st > 36 then
      f.state, f.st = "dive", 0
      local dx, dy = chef.x - f.x, (chef.y - 40) - f.y
      local l = math.max(1, math.sqrt(dx * dx + dy * dy))
      f.vx, f.vy = dx / l * 6.2, dy / l * 6.2
    end
  elseif f.state == "dive" then
    f.x, f.y = f.x + f.vx, f.y + f.vy
    local hit = f.y >= C.FLOOR - 16
    if chef.state == "play" and math.abs(chef.x - f.x) < 34 and math.abs(chef.y - 40 - f.y) < 46 then hit = true chef.hurt() end
    if hit or f.st > 120 then
      f.hp = 0
      Fx.add("boom_m", f.x, f.y)
      Sound.play("boom", 0.6)
      Shots.blast(f.x, math.min(f.y, C.FLOOR), 44, 1, "boom_s", false)
      f.state, f.st = "gone", 0
    end
  end
end

function AI.crab(f, chef)
  face(f, chef)
  f.st = f.st + 1
  if f.state == "move" then
    if math.abs(chef.x - f.x) > 230 then f.x = f.x + f.dir * 0.8 end
    f.cool = f.cool - 1
    if f.cool <= 0 and math.abs(chef.x - f.x) < 460 then f.state, f.st, f.cool = "fire", 0, 130 end
  elseif f.state == "fire" then
    if f.st == 22 then
      local dx = chef.x - f.x
      Shots.hostile("shell", f.x + f.dir * 60, f.y - 60, dx / 62, -6.4, {grav = true})
      Sound.play("cannon", 0.5)
      require("core.juice_hook").shake(2)
    end
    if f.st > 36 then f.state = "move" end
  end
  if f.cool < 0 then f.cool = 0 end
  if math.abs(chef.x - f.x) < 80 and chef.state == "play" and chef.y > C.FLOOR - 30 then chef.hurt() end
end

local function frame_of(f)
  local k, t, st = f.kind, f.t, f.st
  local sh = f.d.sheet
  local function seq(prefix, i) return S.seq(sh, prefix, i) end
  local function upto(prefix, i) return prefix .. "_" .. math.max(0, math.min(S.n(sh, prefix) - 1, i)) end
  if f.state == "dying" then
    if k == "soldier" then return upto(f.die, st // 5) end
    if k == "kamikaze" then return nil end
    return upto("die", st // 5)
  end
  if k == "soldier" then
    if f.hit > 0 then return "hit_0" end
    if f.state == "shoot" then return upto("shoot", f.st // 8) end
    if f.state == "peck" then return upto("peck", f.st // 7) end
    if f.state == "surrender" then return seq("surrender", t // 8) end
    if f.state == "flee" or (f.state == "walk" and math.abs(f.chef_d or 999) > f.stop) then return seq("walk", t // 5) end
    return seq("idle", t // 10)
  elseif k == "bazooka" then
    if f.state == "aim" then return upto("aim", f.st // 12) end
    if f.state == "fire" then return upto("fire", f.st // 9) end
    return upto("reload", f.st // 35)
  elseif k == "drone" then
    if f.state == "drop" then return upto("drop", f.st // 6) end
    return seq("fly", t // 3)
  elseif k == "kamikaze" then
    if f.state == "dive" then return seq("dive", t // 3) end
    if f.state == "windup" then return seq("windup", t // 5) end
    return seq("idle", t // 8)
  elseif k == "crab" then
    if f.state == "fire" then return upto("fire", f.st // 9) end
    return (math.abs(f.chef_d or 999) > 230) and seq("move", t // 4) or seq("idle", t // 12)
  end
end

function Foes.update(chef, cam)
  Foes.cam = cam
  for i = #Foes.list, 1, -1 do
    local f = Foes.list[i]
    f.t = f.t + 1
    if f.flash > 0 then f.flash = f.flash - 1 end
    f.chef_d = chef.x - f.x
    if f.state == "dying" then
      f.st = f.st + 1
      if f.d.fly and f.kind == "drone" then f.y = f.y + 3 end
      if f.st > 34 then table.remove(Foes.list, i) end
    elseif f.state == "gone" then
      table.remove(Foes.list, i)
    else
      local ai = AI[f.kind]
      if ai then ai(f, chef) end
      if f.x < cam - 320 or f.x > cam + C.W + 520 then table.remove(Foes.list, i) end
    end
  end
end

function Foes.draw(cam)
  for _, f in ipairs(Foes.list) do
    local frame = frame_of(f)
    if frame then
      local flip = f.dir > 0
      S.draw(f.d.sheet, frame, f.x - cam, f.y, {flip = flip, tint = f.flash > 0 and 0xFFFFFF or nil})
    end
  end
end

return Foes
