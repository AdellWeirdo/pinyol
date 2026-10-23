-- enemy: the base of every pest. A kind is a definition (core/enemies.lua): its sheet, hearts, speed, what it does each
-- tick, what it leaves behind. This file does what all of them share: being hit and thrown back, flashing, dying,
-- touching the hero, and moving against the map.
local C = require("core.const")
local U = require("core.util")
local W = require("core.world")
local S = require("core.spr")
local E = require("core.ents")
local Game = require("core.game")
local FX = require("core.fx")
local Sound = require("core.sound")
local Pick = require("core.pickups")
local Combat = require("core.combat")
local Hero = require("core.hero")
local Enemy = {}

Enemy.kinds = {}

-- may a body of mw x mh at (x + mx, y + my) stand here? flying ones only mind the area's edge
local function free(e, x, y)
  local bx, by, bw, bh = x + e.mx, y + e.my, e.mw, e.mh
  if e.flying then
    return bx >= 0 and by >= 0 and bx + bw <= W.area.gw * C.T and by + bh <= W.area.gh * C.T
  end
  return not W.blocked(bx, by, bw, bh) and not E.solid_at(bx, by, bw, bh, e)
end

-- moves (dx, dy) pixels, whole ones, an axis at a time; returns true if nothing stopped it
function Enemy.move(e, dx, dy)
  local ok = true
  e.rx, e.ry = (e.rx or 0) + dx, (e.ry or 0) + dy
  for axis = 1, 2 do
    local r = axis == 1 and e.rx or e.ry
    local n = r >= 0 and math.floor(r) or -math.floor(-r)
    if axis == 1 then e.rx = e.rx - n else e.ry = e.ry - n end
    local step = n > 0 and 1 or -1
    while n ~= 0 do
      local nx, ny = e.x + (axis == 1 and step or 0), e.y + (axis == 2 and step or 0)
      if free(e, nx, ny) then e.x, e.y = nx, ny else ok = false break end
      n = n - step
    end
  end
  return ok
end

function Enemy.spawn(def)
  local k = Enemy.kinds[def.id]
  if not k then error("no enemy " .. tostring(def.id)) end
  if def.flag and Game.flags[def.flag] then return nil end -- beaten for good
  local e = {kind = "enemy", team = "enemy", id = def.id, def = def, k = k, x = def.cx * C.T, y = def.cy * C.T - (k.lift or 0),
             hp = k.hp, t = 0, dir = def.face or "down", rx = 0, ry = 0, hurt_t = 0, flash = 0, sort = k.sort or 15,
             bx = k.bx or 2, by = k.by or 3, bw = k.bw or 12, bh = k.bh or 12,
             mx = k.mx or 3, my = k.my or 8, mw = k.mw or 10, mh = k.mh or 7, flying = k.flying}
  e.update, e.draw, e.hit = Enemy.update, Enemy.draw, Enemy.hit
  if k.init then k.init(e) end
  return E.add(e)
end

-- an enemy made by another (a segment of a caterpillar): not placed by a map, not counted for clearing a room
function Enemy.spawn_raw(o)
  local k = Enemy.kinds[o.id]
  local e = {kind = "enemy", team = "enemy", id = o.id, k = k, x = o.x, y = o.y, hp = k.hp, t = 0, dir = "down", rx = 0, ry = 0,
             hurt_t = 0, flash = 0, sort = k.sort or 15, bx = k.bx or 2, by = k.by or 3, bw = k.bw or 12, bh = k.bh or 12,
             mx = k.mx or 3, my = k.my or 8, mw = k.mw or 10, mh = k.mh or 7, flying = k.flying, def_ignore = o.def_ignore}
  e.update, e.draw, e.hit = Enemy.update, Enemy.draw, Enemy.hit
  if k.init then k.init(e) end
  return E.add(e)
end

function Enemy.update(e)
  e.t = e.t + 1
  if e.hurt_t > 0 then
    e.hurt_t = e.hurt_t - 1
    local f = e.hurt_t / 14
    Enemy.move(e, e.kx * f, e.ky * f)
    if e.flash > 0 then e.flash = e.flash - 1 end
    return
  end
  if e.k.update then e.k.update(e) end
  local h = E.hero
  if h and h.state ~= "dead" and (e.k.dmg or 1) ~= 0 and not e.hidden and Combat.touches_hero(e, h) then
    Hero.hurt(h, e.k.dmg or 1, e.x + 8, e.y + 8)
  end
end

-- a blow of `dmg` going in direction `dir`: the pest is flung that way; a shell (k.guard) turns blows from the front
function Enemy.hit(e, dmg, dir, source)
  if e.hidden then return false end
  if e.k.guard and e.k.guard(e, dir) then
    Sound.play("deny")
    FX.spark(e.x + 8, e.y + 8)
    e.hurt_t, e.kx, e.ky = 6, -U.DIRS[dir][1] * 0.8, -U.DIRS[dir][2] * 0.8
    return false
  end
  e.hp = e.hp - dmg
  local d = U.DIRS[dir]
  e.kx, e.ky = d[1] * 2.4, d[2] * 2.4
  e.hurt_t, e.flash = 14, 14
  FX.freeze(3)
  FX.spark(e.x + 8, e.y + 8)
  Sound.play("hit")
  if e.hp <= 0 then Enemy.die(e, source) end
  return true
end

function Enemy.die(e, source)
  e.dead = true
  FX.poof(e.x + 8, e.y + 8)
  Sound.play("kill")
  Game.stats.kills = Game.stats.kills + 1
  if e.def and e.def.flag then Game.flags[e.def.flag] = true end
  if source and source.kind == "shot" then achieve("buen_tiro") end
  -- the aphids of Bellota's quest are counted once he has asked
  if e.def and e.def.quest == "bellota" and Game.flags.bellota_quest and not Game.flags.bellota_done then
    Game.flags.bellota_kills = (Game.flags.bellota_kills or 0) + 1
  end
  if e.k.drops then Pick.roll(e.k.drops, e.x + 8, e.y + 10) end
  if e.k.on_die then e.k.on_die(e) end
end

function Enemy.draw(e)
  if e.flash > 0 and (e.flash // 2) % 2 == 0 then return end -- it blinks out and in when hit
  local name, flip = e.k.frame(e)
  local sx, sy = W.to_screen(e.x, e.y)
  if e.flying and not e.hidden then S.draw("UI8", "shadow", sx + 4, sy + 13, {prio = 2}) end
  S.draw(e.k.sheet or "MON", name, sx, sy, {flip = flip})
end

function Enemy.face_hero(e)
  local h = E.hero
  return U.dir_of(h.x - e.x, h.y - e.y)
end

things_enemy = nil
return Enemy
