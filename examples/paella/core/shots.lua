-- shots: everything that flies: the chef's shots (each chef's own), grenades (a pressure cooker that bounces and blows), the gulls' pellets, bombs and rockets, and the
-- tractor's shells. `Shots.ctx` is set by the scene to {foes, boss, pows, props, chef} so a shot can hit what it meets.
local C = require("core.const")
local S = require("core.spr")
local Fx = require("core.fx")
local Sound = require("core.sound")
local Shots = {}

Shots.mine, Shots.theirs, Shots.pots = {}, {}, {}
Shots.ctx = {}

function Shots.clear()
  for _, l in ipairs({Shots.mine, Shots.theirs, Shots.pots}) do for i = #l, 1, -1 do l[i] = nil end end
end

-- a chef's shot: w is the weapon (weapons.lua), (dx, dy) the unit direction, `scale` for the tractor's shell
function Shots.fire(w, x, y, dx, dy, o)
  local n = w.pellets or 1
  for i = 1, n do
    local a = math.atan(dy, dx)
    if n > 1 then a = a + ((i - 1) / (n - 1) - 0.5) * 2 * (w.spread or 0.15) end
    if w.jitter then a = a + (math.random() - 0.5) * 2 * w.jitter end
    local sp = w.speed * (1 + (math.random() - 0.5) * 0.06)
    Shots.mine[#Shots.mine + 1] = {x = x, y = y, vx = math.cos(a) * sp, vy = math.sin(a) * sp, w = w, t = 0, hit = {}, left = w.pierce or 0, sheet = o and o.sheet or "shots",
                                   prefix = o and o.prefix or w.name, n = o and o.n or S.n("shots", w.name), angle = (o and o.angle) or nil, r = w.r, dmg = w.dmg}
  end
  Sound.play(w.sfx or "knife", 0.5)
end

function Shots.hostile(kind, x, y, vx, vy, o)
  Shots.theirs[#Shots.theirs + 1] = {kind = kind, x = x, y = y, vx = vx, vy = vy, t = 0, r = (kind == "beam" and 16) or (kind == "rocket" and 11) or (kind == "bomb" and 12) or (kind == "shock" and 12) or 7, dmg = 1, blast = o and o.blast, grav = o and o.grav}
end

function Shots.pot(x, y, vx, vy)
  Shots.pots[#Shots.pots + 1] = {x = x, y = y, vx = vx, vy = vy, t = 0, bounces = 0}
end

-- a blast: hurts foes (from the chef) or the chef (from a gull) within r
function Shots.blast(x, y, r, dmg, kind, mine)
  Fx.add(kind or "boom_m", x, y - 10)
  Sound.play(kind == "boom_grenade" and "big" or "boom", 0.7)
  local c = Shots.ctx
  if mine then
    if c.foes then c.foes.blast(x, y, r, dmg) end
    if c.boss and c.boss.blast then c.boss.blast(x, y, r, dmg) end
    if c.props then c.props.blast(x, y, r) end
    if c.pows then c.pows.hit(x, y - 20, r) end
  elseif c.chef and c.chef.hurt_at then
    c.chef.hurt_at(x, y - 20, r)
  end
end

function Shots.update()
  local c = Shots.ctx
  local cam = c.cam or 0
  for i = #Shots.mine, 1, -1 do
    local s = Shots.mine[i]
    s.t = s.t + 1
    s.vy = s.vy + (s.w.gravity or 0)
    s.x, s.y = s.x + s.vx, s.y + s.vy
    local dead = s.t > s.w.life or s.x < cam - 60 or s.x > cam + C.W + 60 or s.y > C.FLOOR + 6 or s.y < -40
    if not dead and c.foes then
      local hit, killed = c.foes.hit_at(s.x, s.y, s.r, s.dmg, s.hit)
      if hit then Fx.add("hit", s.x, s.y) if s.left > 0 then s.left = s.left - 1 else dead = true end end
    end
    if not dead and c.boss and c.boss.hit_at and c.boss.hit_at(s.x, s.y, s.r, s.dmg) then
      Fx.add("hit", s.x, s.y)
      dead = true
    end
    if not dead and c.props and c.props.hit(s.x, s.y, s.r) then dead = true end
    if not dead and c.pows and c.pows.hit(s.x, s.y, s.r) then dead = true end
    if dead and s.w.splash then Shots.blast(s.x, math.min(s.y, C.FLOOR), s.w.splash, 2, "boom_s", true) end
    if dead then table.remove(Shots.mine, i) end
  end
  for i = #Shots.theirs, 1, -1 do
    local s = Shots.theirs[i]
    s.t = s.t + 1
    if s.kind == "bomb" or s.grav then s.vy = s.vy + 0.18 end
    s.x, s.y = s.x + s.vx, s.y + s.vy
    if s.kind == "shock" and s.t % 4 == 0 then Fx.add("smoke", s.x, C.FLOOR - 14) end
    local dead = s.x < cam - 80 or s.x > cam + C.W + 80 or s.t > 400
    local ch = c.chef
    if not dead and ch and ch.state == "play" and ch.inv <= 0 then
      local bx, by, bw, bh = ch.hit_box()
      if s.x + s.r > bx and s.x - s.r < bx + bw and s.y + s.r > by and s.y - s.r < by + bh then
        if ch.blocks and ch.blocks(s) then
          Fx.add("hit", s.x, s.y)
          Sound.play("clank", 0.5)
          dead = true
        else
          ch.hurt()
          dead = true
        end
      end
    end
    if not dead and (s.kind == "bomb" or s.kind == "shell" or s.kind == "rocket" or s.kind == "beam") and s.y >= C.FLOOR - 6 then
      Shots.blast(s.x, C.FLOOR, s.kind == "rocket" and 46 or 40, 1, "boom_m", false)
      dead = true
    end
    if dead then table.remove(Shots.theirs, i) end
  end
  for i = #Shots.pots, 1, -1 do
    local p = Shots.pots[i]
    p.t = p.t + 1
    p.vy = p.vy + 0.42
    p.x, p.y = p.x + p.vx, p.y + p.vy
    local boom = p.t > 90
    if p.y >= C.FLOOR - 8 then
      p.y = C.FLOOR - 8
      if p.bounces < 1 then p.vy, p.vx, p.bounces = -p.vy * 0.4, p.vx * 0.6, p.bounces + 1 else boom = true end
    end
    if not boom and c.foes and c.foes.touching(p.x, p.y, 20) then boom = true end
    if not boom and c.boss and c.boss.touching and c.boss.touching(p.x, p.y, 20) then boom = true end
    if boom then
      Shots.blast(p.x, p.y + 8, 78, 8, "boom_grenade", true)
      require("core.juice_hook").shake(5)
      table.remove(Shots.pots, i)
    end
  end
end

function Shots.draw(cam)
  for _, s in ipairs(Shots.mine) do
    local f = s.prefix .. "_" .. ((s.t // 3) % math.max(1, s.n))
    local flip = s.vx < 0 and not s.angle
    S.draw(s.sheet, f, s.x - cam, s.y, {flip = flip, angle = s.angle and math.floor(math.deg(math.atan(s.vy, s.vx)) + 0.5) or nil})
  end
  for _, s in ipairs(Shots.theirs) do
    if s.kind == "beam" then
      S.draw("boss_fx", "beam_" .. ((s.t // 2) % 4), s.x - cam, s.y, {})
    elseif s.kind ~= "shock" then
      S.draw("shots", S.seq("shots", s.kind == "shell" and "bomb" or s.kind, s.t // 4), s.x - cam, s.y, {flip = s.vx > 0 and s.kind ~= "bomb"})
    end
  end
  for _, p in ipairs(Shots.pots) do
    S.draw("shots", S.seq("shots", "pot", p.t // 3), p.x - cam, p.y, {})
  end
end

return Shots
