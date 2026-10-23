-- hero: Brote, the player. Movement is by whole pixels against the map and the solid things on it, with the corner
-- assist every top-down game has (a head that clips a corner is slid round it); the facing is the way of the last
-- arrow pressed. What he does is a state: walk, swing (the pala), dig, shoot, hurt, item (holding one up), dead, talk.
local C = require("core.const")
local U = require("core.util")
local W = require("core.world")
local S = require("core.spr")
local E = require("core.ents")
local Game = require("core.game")
local FX = require("core.fx")
local Sound = require("core.sound")

local H = {}
local Tools -- core.tools needs the hero too: it is required at the end

H.SPEED = 1.25
-- his feet: the part of the sprite that collides
local BX, BY, BW, BH = 3, 8, 10, 7

local WALK = {"_0", "_1", "_0", "_2"}

function H.new(x, y, face)
  local h = {kind = "hero", x = x, y = y, rx = 0, ry = 0, face = face or "down", pref = "v", anim = 0, moving = false,
             state = "walk", st = 0, inv = 0, hx = BX, hy = BY, hw = BW, hh = BH, sort = 15, team = "hero"}
  h.update, h.draw = H.update, H.draw
  E.hero = h
  return E.add(h)
end

-- may a hero whose sprite is at x, y stand there?
local function free(h, x, y)
  return not W.blocked(x + BX, y + BY, BW, BH) and not E.solid_at(x + BX, y + BY, BW, BH, h)
end
H.free = free

-- when a step is blocked only by a corner, which sideways pixel (dx, dy) gets round it? 0, 0 when none
local function slide(h, dx, dy)
  for k = 1, 4 do
    if dx ~= 0 then
      if free(h, h.x + dx, h.y - k) and free(h, h.x, h.y - 1) then return 0, -1 end
      if free(h, h.x + dx, h.y + k) and free(h, h.x, h.y + 1) then return 0, 1 end
    else
      if free(h, h.x - k, h.y + dy) and free(h, h.x - 1, h.y) then return -1, 0 end
      if free(h, h.x + k, h.y + dy) and free(h, h.x + 1, h.y) then return 1, 0 end
    end
  end
  return 0, 0
end

-- moves by (mx, my) pixels (fractions kept); returns true if he went all the way on both axes
function H.move(h, mx, my)
  local ok = true
  h.rx, h.ry = h.rx + mx, h.ry + my
  for axis = 1, 2 do
    local r = axis == 1 and h.rx or h.ry
    local n = r >= 0 and math.floor(r) or -math.floor(-r)
    if axis == 1 then h.rx = h.rx - n else h.ry = h.ry - n end
    local step = n > 0 and 1 or -1
    while n ~= 0 do
      local dx, dy = axis == 1 and step or 0, axis == 2 and step or 0
      if free(h, h.x + dx, h.y + dy) then
        h.x, h.y = h.x + dx, h.y + dy
      else
        local sx, sy = slide(h, dx, dy)
        if sx ~= 0 or sy ~= 0 then h.x, h.y = h.x + sx, h.y + sy else ok = false break end
      end
      n = n - step
    end
  end
  return ok
end

function H.set(h, state, a, b)
  h.state, h.st = state, 0
  local s = H.states[state]
  if s and s.enter then s.enter(h, a, b) end
end

local function read_dir()
  local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
  local dy = (btn("down") and 1 or 0) - (btn("up") and 1 or 0)
  return dx, dy
end

-- the pose's name in the sheets: down, up or side (the right-facing one; left is mirrored)
local function view(h) return (h.face == "left" or h.face == "right") and "side" or h.face end
H.view = view

H.states = {}

-- ------------------------------------------------------------------ walking
H.states.walk = {
  update = function(h)
    if btnp("left") or btnp("right") then h.pref = "h" end
    if btnp("up") or btnp("down") then h.pref = "v" end
    local dx, dy = read_dir()
    h.moving = dx ~= 0 or dy ~= 0
    if h.moving then
      if dx ~= 0 and dy ~= 0 then
        if h.pref == "h" then h.face = dx < 0 and "left" or "right" else h.face = dy < 0 and "up" or "down" end
      elseif dx ~= 0 then h.face = dx < 0 and "left" or "right"
      else h.face = dy < 0 and "up" or "down" end
      local sp = H.SPEED * ((dx ~= 0 and dy ~= 0) and 0.75 or 1)
      local f = W.cell_flags(math.floor((h.x + 8) / C.T), math.floor((h.y + 13) / C.T))
      if f and f.shallow then
        sp = sp * 0.7
        if h.anim % 9 == 0 then FX.splash(h.x + 8, h.y + 14) Sound.play("splash", 0.4) end
      end
      H.move(h, dx * sp, dy * sp)
      h.anim = h.anim + 1
    else
      h.anim = 0
    end
    if btnp("a") then Tools.press_a(h) end
    if btnp("b") then Tools.press_b(h) end
    if btnp("c") then Tools.cycle_b() end
    Tools.lantern_tick(h)
    local f = W.cell_flags(math.floor((h.x + 8) / C.T), math.floor((h.y + 12) / C.T))
    if f and f.spikes and h.inv == 0 then H.hurt(h, 1, h.x + 8, h.y + 16) end
  end,
  frame = function(h)
    if h.pushing then return "HERO", "push_" .. view(h) .. "_" .. ((h.anim // 9) % 2) end
    if h.anim == 0 then
      h.idle = (h.idle or 0) + 1
      if h.face == "down" and h.idle % 240 > 228 then return "HERO", "blink" end -- every four seconds, a blink
    else
      h.idle = 0
    end
    local f = h.anim > 0 and WALK[(h.anim // 7) % 4 + 1] or "_0"
    return "HERO", view(h) .. f
  end,
}

-- ------------------------------------------------------------------ the pala
H.states.swing = {
  enter = function(h) h.seen = {} Sound.play("swing") end,
  update = function(h)
    h.st = h.st + 1
    if h.st >= 3 and h.st <= 8 then Tools.pala_hit(h) end
    if h.st >= 9 and btnp("a") then h.buffered = true end
    if h.st >= 15 then
      if h.buffered then h.buffered = false H.set(h, "swing") else H.set(h, "walk") end
    end
  end,
  frame = function(h)
    local stage = h.st < 3 and 0 or (h.st < 9 and 1 or 2)
    return "HEROX", "swing_" .. view(h) .. "_" .. stage, -8, -8
  end,
}

H.states.dig = {
  enter = function(h, gx, gy) h.dig_cell = {gx, gy} end,
  update = function(h)
    h.st = h.st + 1
    if h.st == 10 then Tools.dig(h) end
    if h.st >= 26 then H.set(h, "walk") end
  end,
  frame = function(h) return "HEROX", h.st < 10 and "dig_0" or "dig_1", -8, -8 end,
}

H.states.shoot = {
  enter = function(h) end,
  update = function(h)
    h.st = h.st + 1
    if h.st == 5 then Tools.fire(h) end
    if h.st >= 14 then H.set(h, "walk") end
  end,
  frame = function(h) return "HEROX", "shoot_" .. view(h), -8, -8 end,
}

H.states.lantern = {
  update = function(h)
    h.st = h.st + 1
    if h.st >= 10 then H.set(h, "walk") end
  end,
  frame = function(h) return "HEROX", "lantern_" .. view(h), -8, -8 end,
}

-- ------------------------------------------------------------------ hurt, item, dead, talk
H.states.hurt = {
  enter = function(h, fx, fy)
    -- thrown away from where the blow came from
    local dx, dy = (h.x + 8) - fx, (h.y + 10) - fy
    local len = math.max(1, math.sqrt(dx * dx + dy * dy))
    h.kx, h.ky = dx / len * 2.2, dy / len * 2.2
  end,
  update = function(h)
    h.st = h.st + 1
    local k = 1 - h.st / 12
    if k > 0 then H.move(h, h.kx * k, h.ky * k) end
    if h.st >= 16 then H.set(h, "walk") end
  end,
  frame = function(h) return "HERO", "hurt_" .. view(h) end,
}

H.states.item = {
  enter = function(h, item) h.item = item end,
  update = function(h) h.st = h.st + 1 end,
  frame = function(h) return "HERO", "get_item" end,
}

-- falling into a pit: he shrinks, loses half a heart, and is put back where he last stood safe
H.states.fall = {
  update = function(h)
    h.st = h.st + 1
    if h.st >= 24 then
      Game.hurt(1)
      if Game.hp <= 0 then H.set(h, "dead") return end
      local to = h.fall_from or {h.x, h.y}
      h.x, h.y = to[1], to[2]
      h.inv = 60
      H.set(h, "walk")
    end
  end,
  frame = function(h) return "HERO", "fall" end,
}

H.states.dead = {
  update = function(h) h.st = h.st + 1 end,
  frame = function(h) return "HERO", "die_" .. math.min(3, h.st // 10) end,
}

H.states.talk = {
  update = function(h) h.anim = 0 end,
  frame = function(h)
    if h.sleeping then return "HERO", "sleep" end
    if h.sitting then return "HERO", "sit_0" end
    if h.walking then return "HERO", view(h) .. WALK[(h.anim // 7) % 4 + 1] end
    return "HERO", view(h) .. "_0"
  end,
}

-- ------------------------------------------------------------------ hurting the hero
function H.hurt(h, dmg, fx, fy)
  if h.inv > 0 or h.state == "dead" or h.state == "item" or h.state == "talk" then return false end
  Game.hurt(dmg)
  h.inv = 70
  FX.shake(2, 8)
  FX.freeze(4)
  Sound.play("hurt")
  if Game.hp <= 0 then
    Sound.play("hurt")
    H.set(h, "dead")
  else
    H.set(h, "hurt", fx, fy)
  end
  return true
end

function H.update(h)
  if h.inv > 0 then h.inv = h.inv - 1 end
  if h.pushing_t and h.pushing_t > 0 then h.pushing_t = h.pushing_t - 1 else h.pushing = false end
  local s = H.states[h.state]
  if s and s.update then s.update(h) end
  require("core.dungeon").update_hero_pit(h)
  -- the low-hearts beep: one heart or less, every two seconds
  if Game.hp > 0 and Game.hp <= 2 and h.state ~= "talk" and ticks() % 120 == 0 then Sound.play("low") end
end

function H.draw(h)
  if h.inv > 0 and (h.inv // 3) % 2 == 0 and h.state ~= "dead" then return end
  local s = H.states[h.state]
  local sheet, name, ox, oy = s.frame(h)
  local sx, sy = W.to_screen(h.x + (ox or 0), h.y + (oy or 0))
  S.draw(sheet, name, sx, sy, {flip = h.face == "left"})
  if h.state == "item" and h.item then S.draw("ITEMS16", h.item, W.to_screen(h.x, h.y - 14)) end
  if h.state == "swing" and h.st >= 3 and h.st < 9 then
    local fx = Tools.slash_frame(h)
    if fx then
      local d = U.DIRS[h.face]
      local fsx, fsy = W.to_screen(h.x + d[1] * 12, h.y + d[2] * 12 + 2)
      S.draw("TOOLFX", fx, fsx, fsy, {flip = h.face == "left"})
    end
  end
end

-- the point he is looking at, a few pixels in front of his feet (to talk to, to cut, to dig)
function H.front(h, reach)
  local d = U.DIRS[h.face]
  return h.x + 8 + d[1] * (reach or 10), h.y + 11 + d[2] * (reach or 10)
end

Tools = require("core.tools")
return H
