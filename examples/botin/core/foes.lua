-- foes: the enemies and what they throw. Most walk to and fro and turn at ledges; a hit (a ram, a smash, a jump on top) stuns them, a stunned one can be
-- picked up and thrown, and a thrown one breaks brown blocks and takes other enemies with it. A few have a trick of their own (the monkey's coconuts, the
-- snake's strike, the bat's swoop, the fogata's fire, the pufferfish, the little golem's slam).
local C = require("core.const")
local U = require("core.util")
local W = require("core.world")
local P = require("core.phys")
local S = require("core.spr")
local Fx = require("core.fx")
local Sound = require("core.sound")
local Hero = require("core.hero")
local F = {}

F.list = {}
F.coin_drop = nil -- set by the scene: F.coin_drop(x, y, size)

-- sheet, box (w, h), ai, speed, frame prefixes
local DEF = {
  pelusa     = {sheet = "ENEMY16", w = 12, h = 12, ai = "walk", speed = 0.45, walk = "pelusa_walk", n = 4, drop = 1},
  gusanito   = {sheet = "ENEMY16", w = 12, h = 10, ai = "walk", speed = 0.3, walk = "gusanito_walk", n = 4, drop = 1},
  bichito    = {sheet = "ENEMY16", w = 12, h = 12, ai = "roll", speed = 0.4, walk = "bichito_walk", n = 4, drop = 2},
  fogata     = {sheet = "ENEMY16", w = 12, h = 14, ai = "fire", idle = "fogata_idle", n = 4, nostun = true},
  serpiente  = {sheet = "ENEMY32", w = 20, h = 26, ai = "strike", idle = "serpiente_idle", n = 4, drop = 2},
  mono       = {sheet = "ENEMY32", w = 20, h = 26, ai = "throw", idle = "mono_idle", n = 4, drop = 2},
  murcielago = {sheet = "ENEMY32", w = 20, h = 14, ai = "bat", walk = "murcielago_fly", n = 6, drop = 2},
  escarabajo = {sheet = "ENEMY32", w = 22, h = 18, ai = "walk", speed = 0.35, walk = "escarabajo_walk", n = 4, drop = 2},
  pez_globo  = {sheet = "ENEMY32", w = 20, h = 18, ai = "fish", speed = 0.5, walk = "pez_globo_swim", n = 4, drop = 2},
  cangrejo   = {sheet = "ENEMY32", w = 22, h = 16, ai = "walk", speed = 0.5, walk = "cangrejo_walk", n = 4, drop = 2},
  medusa     = {sheet = "ENEMY32", w = 18, h = 20, ai = "float", walk = "medusa_pulse", n = 6, drop = 2},
  golem_chico = {sheet = "ENEMY32", w = 22, h = 28, ai = "golem", speed = 0.3, walk = "golem_chico_walk", n = 4, drop = 3},
}
F.DEF = DEF

local PROJ = {
  coconut = {sheet = "ENEMY16", w = 8, h = 8, n = 4},
  rock = {sheet = "ENEMY16", w = 10, h = 10, n = 4},
  bomb = {sheet = "ENEMY16", w = 10, h = 10, n = 4},
}

function F.clear() for i = #F.list, 1, -1 do F.list[i] = nil end end

function F.spawn(t)
  local d = DEF[t.type]
  assert(d, "no enemy " .. tostring(t.type))
  local e = {
    kind = t.type, d = d, w = d.w, h = d.h, x = t.x * 16 + 8 - d.w / 2, y = (t.y + 1) * 16 - d.h, vx = 0, vy = 0, dir = t.dir or -1, state = "walk", st = 0, t = 0,
    home_x = t.x * 16 + 8, range = (t.range or 3) * 16, carryable = not d.nostun and d.ai ~= "bat_hang", timer = 0, hanging = d.ai == "bat",
    home_y = (t.y + 1) * 16 - d.h,
  }
  if d.ai == "bat" then e.y = t.y * 16 - d.h / 2 e.home_y = e.y end
  if d.ai == "fish" or d.ai == "float" then e.y = t.y * 16 e.home_y = e.y end
  F.list[#F.list + 1] = e
  return e
end

function F.projectile(kind, x, y, vx, vy)
  local p = PROJ[kind]
  local e = {kind = kind, proj = p, w = p.w, h = p.h, x = x - p.w / 2, y = y - p.h / 2, vx = vx, vy = vy, state = "proj", st = 0, t = 0, d = {sheet = p.sheet}}
  F.list[#F.list + 1] = e
  return e
end

-- something the boss (or a level) puts down that can be picked up and thrown back: {sheet, prefix, n, w, h}
function F.egg(x, y, vx, vy, spec)
  local e = {kind = "egg", w = spec.w, h = spec.h, x = x - spec.w / 2, y = y - spec.h / 2, vx = vx, vy = vy, state = "egg", st = 0, t = 0, carryable = true, d = spec, egg = true}
  F.list[#F.list + 1] = e
  return e
end

local function kill(e)
  if e.state == "dead" then return end
  e.state, e.st = "dead", 0
  e.vy = -2.2
  Sound.play("hit")
  Fx.add("poof", e.x + e.w / 2, e.y + e.h / 2)
  if F.coin_drop and e.d and e.d.drop then F.coin_drop(e.x + e.w / 2, e.y, e.d.drop) end
  if F.on_kill then F.on_kill(e) end
end
F.kill = kill

local function stun(e, from_x)
  if e.d.nostun or e.state == "dead" or e.proj then return end
  if e.state == "stun" then return end
  e.state, e.st = "stun", 0
  e.vy = -2.2
  e.vx = (e.x + e.w / 2 < from_x and -1 or 1) * 1.2
  e.hanging = false
  Sound.play("stun")
  Fx.add("hit", e.x + e.w / 2, e.y + e.h / 2)
end
F.stun = stun

function F.stun_near(x, y, r)
  for _, e in ipairs(F.list) do
    if (e.state == "walk" or e.state == "strike") and not e.d.nostun and not e.proj and math.abs(e.x + e.w / 2 - x) < r and math.abs(e.y + e.h - y) < 24 then
      stun(e, x)
    end
  end
end

function F.nearest_carryable(h)
  local best, bd
  for _, e in ipairs(F.list) do
    if e.carryable and (e.state == "stun" or e.state == "egg") and P.overlap(h.x - 4, h.y - 2, h.w + 8, h.h + 4, e.x, e.y, e.w, e.h) then
      local d = math.abs(e.x - h.x)
      if not bd or d < bd then best, bd = e, d end
    end
  end
  return best
end

-- ------------------------------------------------------------------ one tick of each kind of mind

local function ground_ahead(e)
  local ax = e.dir > 0 and e.x + e.w + 2 or e.x - 2
  local fy = e.y + e.h + 4
  return W.solid_px(ax, fy) or W.cell(ax // 16, fy // 16) == "="
end

local function walk(e, hero)
  e.vx = e.dir * e.d.speed
  if e.d.ai == "roll" and math.abs(hero.x - e.x) < 80 and math.abs(hero.y - e.y) < 24 then
    e.rolling = true
    e.vx = e.dir * 1.6
  else
    e.rolling = false
  end
  e.vy = math.min(e.vy + C.GRAVITY, C.MAX_FALL)
  local wall = P.move_x(e, e.vx)
  P.move_y(e, e.vy)
  local g = P.grounded(e, 1)
  if g then e.vy = 0 end
  if wall or (g and not ground_ahead(e)) or (e.range and math.abs(e.x + e.w / 2 - e.home_x) > e.range and U.sign(e.x - e.home_x) == e.dir) then e.dir = -e.dir end
  if e.d.ai == "golem" and math.abs(hero.x - e.x) < 40 and math.abs(hero.y - e.y) < 30 and e.timer <= 0 and g then
    e.state, e.st, e.timer = "attack", 0, 120
  end
  e.timer = e.timer - 1
end

local AI = {}

function AI.walk(e, hero) walk(e, hero) end
AI.roll = AI.walk
AI.golem = AI.walk

function AI.fire(e, hero)
  e.angry = math.abs(hero.x - e.x) < 56 and math.abs(hero.y - e.y) < 40
  if e.t % 14 == 0 then Fx.add("ember", e.x + e.w / 2 + (e.t % 7 - 3), e.y + 2, {vy = -0.5}) end
end

function AI.strike(e, hero)
  local ahead = (hero.x > e.x) == (e.dir > 0) or true
  e.dir = hero.x > e.x and 1 or -1
  if e.state == "walk" and math.abs(hero.x - e.x) < 70 and math.abs(hero.y - e.y) < 30 and e.timer <= 0 then
    e.state, e.st, e.timer = "attack", 0, 110
    Sound.play("hit", 0.5)
  end
  e.timer = e.timer - 1
  e.vy = math.min(e.vy + C.GRAVITY, C.MAX_FALL)
  P.move_y(e, e.vy)
  if P.grounded(e, 1) then e.vy = 0 end
end

function AI.throw(e, hero)
  e.dir = hero.x > e.x and 1 or -1
  e.timer = e.timer - 1
  if e.timer <= 0 and math.abs(hero.x - e.x) < 150 and math.abs(hero.y - e.y) < 90 then
    e.state, e.st, e.timer = "attack", 0, 130
  end
  e.vy = math.min(e.vy + C.GRAVITY, C.MAX_FALL)
  P.move_y(e, e.vy)
  if P.grounded(e, 1) then e.vy = 0 end
end

function AI.bat(e, hero)
  if e.hanging then
    if math.abs(hero.x - e.x) < 70 and hero.y > e.y - 20 and hero.y < e.y + 110 then e.hanging, e.swoop_t = false, 0 end
    return
  end
  e.swoop_t = (e.swoop_t or 0) + 1
  local tx, ty = hero.x + hero.w / 2, hero.y + 4
  e.dir = tx > e.x and 1 or -1
  e.x = e.x + e.dir * 0.9 + math.sin(e.swoop_t / 9) * 0.3
  e.y = e.y + U.clamp((ty - e.y) * 0.03, -0.9, 0.9) + math.sin(e.swoop_t / 7) * 0.4
  if e.swoop_t > 420 or math.abs(e.x - hero.x) > 220 then e.hanging, e.x, e.y = true, e.home_x - e.w / 2, e.home_y end
end

function AI.fish(e, hero)
  e.x = e.x + e.dir * (e.puff and 0.2 or e.d.speed)
  e.y = e.home_y + math.sin(e.t / 25) * 10
  if math.abs(e.x + e.w / 2 - e.home_x) > e.range or W.solid_px(e.x + (e.dir > 0 and e.w + 2 or -2), e.y + e.h / 2) then e.dir = -e.dir end
  e.puff = math.abs(hero.x - e.x) < 44 and math.abs(hero.y - e.y) < 34
end

function AI.float(e, hero)
  e.y = e.home_y + math.sin(e.t / 30) * 16
  e.x = e.x + math.sin(e.t / 50) * 0.3
end

local function frame_of(e)
  local d, t = e.d, e.t
  local k = e.kind
  if e.state == "dead" then return k .. "_hurt" end
  if e.state == "held" then return k .. "_held_" .. ((t // 8) % 2) end
  if e.state == "thrown" then return k .. "_stun_" .. ((t // 4) % 2) end
  if e.state == "stun" then return k .. "_stun_" .. ((t // 10) % 2) end
  if e.state == "attack" then
    if d.ai == "strike" then return "serpiente_strike_" .. math.min(2, e.st // 8) end
    if d.ai == "throw" then return "mono_throw_" .. math.min(3, e.st // 8) end
    if d.ai == "golem" then return "golem_chico_smash_" .. math.min(3, e.st // 8) end
  end
  if d.ai == "fire" then return e.angry and ("fogata_angry_" .. ((t // 6) % 3)) or ("fogata_idle_" .. ((t // 8) % 4)) end
  if d.ai == "roll" and e.rolling then return "bichito_ball_" .. ((t // 3) % 4) end
  if d.ai == "bat" and e.hanging then return "murcielago_hang_" .. ((t // 20) % 2) end
  if d.ai == "bat" and e.swoop_t and e.swoop_t < 20 then return "murcielago_swoop_" .. math.min(2, e.swoop_t // 7) end
  if d.ai == "fish" and e.puff then return "pez_globo_puff_" .. ((t // 6) % 4) end
  if d.ai == "walk" and k == "cangrejo" and false then return "cangrejo_claw_0" end
  if d.walk then return d.walk .. "_" .. ((t // (d.ai == "bat" and 4 or 8)) % d.n) end
  return d.idle .. "_" .. ((t // 10) % d.n)
end

-- ------------------------------------------------------------------ the update of all of them

function F.update(hero)
  local cam = W.cam_x
  for i = #F.list, 1, -1 do
    local e = F.list[i]
    e.t = e.t + 1
    e.st = e.st + 1
    local near = e.x > cam - 120 and e.x < cam + 360
    if e.state == "dead" then
      e.vy = e.vy + 0.18
      e.y = e.y + e.vy
      if e.st > 28 then table.remove(F.list, i) end
    elseif e.state == "held" then
      -- placed by the hero
      if hero.carry == e then
        e.x = Hero.cx(hero) - e.w / 2
        e.y = hero.y - e.h + 2
      else
        e.state = "stun"
      end
    elseif e.state == "thrown" or e.state == "egg" or e.state == "proj" then
      if near or e.state ~= "egg" then F.ballistic(e, hero, i) end
    elseif near then
      if e.state == "stun" then
        e.vy = math.min(e.vy + C.GRAVITY, C.MAX_FALL)
        local wall = P.move_x(e, e.vx)
        if wall then e.vx = -e.vx * 0.5 end
        P.move_y(e, e.vy)
        if P.grounded(e, 1) then e.vy, e.vx = 0, e.vx * 0.8 end
        if e.t % 16 == 0 then Fx.add("stars", e.x + e.w / 2, e.y - 5) end
        if e.st > C.STUN_TICKS then
          e.state = "walk"
          if e.d.ai == "bat" then e.hanging = false end
        end
      elseif e.state == "attack" then
        F.attack(e, hero)
      else
        local ai = AI[e.d.ai]
        if ai then ai(e, hero) end
      end
    end
  end
end

-- strikes, coconuts and slams: the moment of the move is in the middle of its frames
function F.attack(e, hero)
  local d = e.d
  if d.ai == "strike" then
    e.vy = math.min(e.vy + C.GRAVITY, C.MAX_FALL)
    if e.st > 12 and e.st < 26 then e.strike_box = true else e.strike_box = false end
    if e.st > 40 then e.state, e.strike_box = "walk", false end
  elseif d.ai == "throw" then
    if e.st == 18 then
      local tx = hero.x + hero.w / 2
      F.projectile("coconut", e.x + e.w / 2 + e.dir * 8, e.y + 4, U.clamp((tx - e.x) / 55, -2.2, 2.2), -3.4)
      Sound.play("throw", 0.5)
    end
    if e.st > 40 then e.state = "walk" end
  elseif d.ai == "golem" then
    if e.st == 18 then
      W.shake(2, 10)
      Sound.play("smash", 0.6)
      Fx.add("smash", e.x + e.w / 2 + e.dir * 14, e.y + e.h - 6)
      e.strike_box = true
    end
    if e.st > 40 then e.state, e.strike_box = "walk", false end
  end
end

function F.ballistic(e, hero, i)
  e.vy = math.min(e.vy + (e.proj and 0.16 or C.GRAVITY), C.MAX_FALL)
  local wx, wy, wc = P.move_x(e, e.vx)
  if wx then
    if e.state == "thrown" and wc == "b" then Hero.break_cell(wx, wy, "thrown") elseif e.state == "thrown" and W.BREAKABLE[wc] and wc ~= "B" then Hero.break_cell(wx, wy, "thrown") end
    if e.state == "thrown" then kill(e) return end
    if e.state == "proj" then table.remove(F.list, i) Fx.add("poof", e.x, e.y) return end
    e.vx = -e.vx * 0.6
  end
  local gx, gy, gc = P.move_y(e, e.vy)
  if gx then
    if e.state == "thrown" then
      if e.vy < 0 and W.BREAKABLE[gc] and gc ~= "B" then Hero.break_cell(gx, gy, "thrown") end
      if e.vy > 0 then kill(e) return end
      e.vy = 0
    elseif e.state == "proj" then
      table.remove(F.list, i)
      Fx.add("poof", e.x, e.y)
      return
    else
      e.vy = e.vy > 1 and -e.vy * 0.4 or 0
      e.vx = e.vx * 0.7
    end
  end
  if e.y > W.px_h + 40 then table.remove(F.list, i) return end
  if e.state == "thrown" then
    for _, o in ipairs(F.list) do
      if o ~= e and o.state ~= "dead" and o.state ~= "held" and not o.proj and not o.egg and P.overlap(e.x, e.y, e.w, e.h, o.x, o.y, o.w, o.h) then
        kill(o)
        kill(e)
        return
      end
    end
    if F.thrown_hit and F.thrown_hit(e) then kill(e) end
  end
end

-- ------------------------------------------------------------------ against the hero

function F.touch_hero(hero)
  for _, e in ipairs(F.list) do
    local hx, hy, hw, hh = hero.x + 1, hero.y + 2, hero.w - 2, hero.h - 3
    if e.state == "dead" or e.state == "held" or e.state == "thrown" or e.state == "egg" then
      -- nothing to the hero
    elseif e.state == "proj" then
      if P.overlap(hx, hy, hw, hh, e.x, e.y, e.w, e.h) then
        Hero.hurt(hero, e.x)
        e.state = "dead"
        e.st = 99
      end
    elseif e.state == "stun" then
      if Hero.attacking(hero) and P.overlap(hx - 6, hy, hw + 12, hh, e.x, e.y, e.w, e.h) then
        -- a ram kicks the stunned one away: it flies and kills what it meets
        e.state, e.vx, e.vy = "thrown", hero.face * 4, -1.5
      end
    else
      local box_x, box_w = e.x, e.w
      if e.strike_box then box_w = box_w + 22 if e.dir < 0 then box_x = box_x - 22 end end
      if P.overlap(hx, hy, hw, hh, box_x, e.y, box_w, e.h) then
        local d = e.d
        if d.ai == "fire" then
          if hero.inv == 0 then Hero.ignite(hero) end
        elseif d.ai == "fish" and e.puff then
          Hero.hurt(hero, e.x)
        elseif Hero.attacking(hero) and hero.burn <= 0 then
          stun(e, Hero.cx(hero))
          if hero.state == "ram" then hero.vx = hero.vx * 0.6 end
          Fx.add("hit", e.x + e.w / 2, e.y + e.h / 2)
        elseif hero.burn > 0 then
          kill(e)
        elseif hero.vy > 0.6 and hero.y + hero.h - 4 < e.y + e.h * 0.55 and not (d.ai == "fish") then
          stun(e, Hero.cx(hero))
          hero.vy = -3.6
        else
          Hero.hurt(hero, e.x + e.w / 2)
        end
      end
    end
  end
end

local BIOME_BANK = {selva = "enemigo_a", cristal = "enemigo_b", galeon = "enemigo_c", fragua = "enemigo_d"}

function F.draw(cx, cy)
  local bank = BIOME_BANK[W.lv.biome]
  for _, e in ipairs(F.list) do
    if e.proj then
      S.draw(e.proj.sheet, e.kind .. "_" .. ((e.t // 4) % 4), e.x + e.w / 2 - 8 - cx, e.y + e.h / 2 - 8 - cy, {})
    elseif e.egg then
      S.draw(e.d.sheet, e.d.prefix .. "_" .. ((e.t // 8) % e.d.n), e.x + e.w / 2 - e.d.sw / 2 - cx, e.y + e.h - e.d.sh - cy, {})
    else
      local f = frame_of(e)
      local sw, sh = S.size(e.d.sheet)
      S.draw(e.d.sheet, f, e.x + e.w / 2 - sw / 2 - cx, e.y + e.h - sh - cy, {flip = e.dir < 0 and e.d.ai ~= "fire", bank = e.kind == "murcielago" and W.lv.biome == "fragua" and "enemigo_d" or (e.kind ~= "fogata" and sh == 32 or e.kind == "pelusa" or e.kind == "gusanito") and bank or nil})
    end
  end
end

return F
