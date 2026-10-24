-- play: the mission. It sets everything up for a chef, runs a tick of the world (the camera moving only forward, waves of gulls put when the camera reaches them, the tractor, the people
-- to free, the boss at the end), and draws the frame in painting order: the far layer (wiped to the next when a zone changes), the street, props, people, items, gulls, the boss, the
-- tractor, the chef, shots, effects and the status line.
local C = require("core.const")
local U = require("core.util")
local S = require("core.spr")
local L = require("core.level")
local Run = require("core.run")
local Chef = require("core.chef")
local Foes = require("core.foes")
local Shots = require("core.shots")
local Fx = require("core.fx")
local Props = require("core.props")
local Pows = require("core.pows")
local Items = require("core.items")
local Tractor = require("core.tractor")
local Boss = require("core.boss")
local Sound = require("core.sound")
local Music = require("core.music")
local Hook = require("core.juice_hook")
local Play = {}

Play.chef = nil
Play.cam = 0
Play.zone = 1
Play.state = "play"      -- play, boss, clear, over
Play.banner_t = 0
Play.wipe = nil          -- {from = far name, t = ticks} while the far layer changes
Play.far = "far_puerto"
Play.go_t = 0
Play.ev_i = 1
Play.t = 0

function Play.enter(chef_id)
  Run.reset(chef_id)
  Foes.clear() Shots.clear() Fx.clear() Props.clear() Pows.clear() Items.clear() Tractor.clear() Boss.reset()
  Foes.items, Props.items, Pows.items = Items, Items, Items
  Play.chef = Chef.new(chef_id, 110)
  Play.cam, Play.zone, Play.state, Play.ev_i, Play.t = 0, 1, "play", 1, 0
  Play.far, Play.wipe = L.ZONES[1].far, nil
  Play.banner_t = 150
  Play.over_t = 0
  Chef.max_x = C.W - 24
  Tractor.max_x = nil
  Tractor.on_leave = function() if not Boss.active then Music.play(L.ZONES[Play.zone].music, 400) end end
  Music.play(L.ZONES[1].music)
  Play.ctx()
end

function Play.ctx()
  local c = Shots.ctx
  c.foes, c.boss, c.pows, c.props, c.chef, c.cam = Foes, Boss, Pows, Props, Play.chef, Play.cam
end

local function spawn_event(e)
  if e.wave then
    for _, w in ipairs(e.wave) do
      local where, off = w[2], w[3]
      if w[1] == "bazooka" and type(where) == "number" then Foes.spawn("bazooka", where, C.FLOOR)
      else Foes.spawn_at(w[1], where, off, Play.cam) end
    end
  end
  if e.pow then Pows.add(e.pow[1], e.pow[2], e.pow[3]) end
  if e.props then for _, p in ipairs(e.props) do Props.add(p[1], p[2]) end end
  if e.food then for _, f in ipairs(e.food) do Items.add("food", f[2], C.FLOOR - 40, {food = f[1], vy = 0, rest = true}) end end
  if e.tractor then Tractor.park(e.tractor) end
end

-- the chef comes back after a death, or the mission ends
local function respawn(c)
  c.state, c.dead_t = "play", 0
  c.x, c.y, c.vx, c.vy, c.ground = Play.cam + 120, C.FLOOR, 0, 0, true
  c.inv = C.INVULN
  c.weapon, c.up_shots = c.base, 0
  c.grenades = math.max(c.grenades, 6)
end

function Play.update(t)
  local c = Play.chef
  Play.t = Play.t + 1
  Run.t = Run.t + 1
  Props.items = Items
  Chef.max_x = Play.cam + C.W - 24
  Chef.update(c, Play.cam)
  -- the camera only goes forward, and stops at the arena
  if Play.state == "play" then
    if c.state == "play" then Play.cam = math.max(Play.cam, math.min(C.LEVEL_W, c.x - 210)) end
    while L.EVENTS[Play.ev_i] and Play.cam + C.W >= L.EVENTS[Play.ev_i].at do
      spawn_event(L.EVENTS[Play.ev_i])
      Play.ev_i = Play.ev_i + 1
    end
    local z = L.zone_at(Play.cam + C.W / 2)
    if z ~= Play.zone and Play.cam < C.LEVEL_W then
      Play.wipe = {from = Play.far, t = 0}
      Play.far = L.ZONES[z].far
      Play.zone = z
      Play.banner_t = 150
      Music.play(L.ZONES[z].music, 500)
    end
    if Play.cam >= C.LEVEL_W - 1 and Foes.count() == 0 and not Boss.active then
      Play.state = "boss"
      Boss.enter(C.LEVEL_W)
      Play.banner_t = 160
      Play.zone = 3
    end
  end
  if Play.state == "boss" then Chef.max_x = C.LEVEL_W + C.W - 24 end
  Play.ctx()
  Shots.ctx.cam = Play.cam
  Tractor.update(c, Play.cam)
  Foes.update(c, Play.cam)
  Boss.update(c, Play.cam)
  Shots.update()
  Props.update(c)
  Pows.cam, Items.cam = Play.cam, Play.cam
  Pows.update(c)
  Items.update(c)
  Fx.update()
  if Play.wipe then
    Play.wipe.t = Play.wipe.t + 1
    if Play.wipe.t > 100 then Play.wipe = nil end
  end
  if Play.banner_t > 0 then Play.banner_t = Play.banner_t - 1 end
  -- the chef died, or won
  if c.state == "dead" and c.dead_t > 80 then
    if c.lives > 0 then respawn(c) else Play.state, Play.over_t = "over", 0 end
  end
  if Play.state == "boss" and Boss.done and c.state ~= "win" then
    c.state, c.win_t = "win", 0
    Play.state, Play.clear_t = "clear", 0
    Music.jingle("victoria", 6, false)
    Run.boss_dead = true
  end
  if Play.state == "clear" then Play.clear_t = Play.clear_t + 1 end
  Play.go_t = (Play.state == "play" and Foes.count() == 0 and c.x > Play.cam + 280) and Play.go_t + 1 or 0
end

-- ------------------------------------------------------------------ drawing

local function far_layer(name, cam)
  local fw = S.back_size(name)
  local off = -((cam * 0.25) % (2 * fw))
  for k = 0, 2 do
    local x = off + k * 2 * fw
    if x < C.W and x + 2 * fw > 0 then
      S.back(name, math.floor(x), 0)
      S.back(name, math.floor(x + fw), 0, true)
    end
  end
end

local function street(cam)
  if cam + C.W > C.LEVEL_W then S.back("arena_playa", C.LEVEL_W - cam, 0) end
  local first = cam // C.CHUNK
  for ci = first, first + 1 do
    local x = ci * C.CHUNK
    if x < C.LEVEL_W then
      local z = math.min(C.ZONES, x // C.ZONE_W + 1)
      local k = (x % C.ZONE_W) // C.CHUNK + 1
      S.back(L.ZONES[z].near[k], x - cam, 0)
    end
  end
end

-- everything of the world, in painting order. Positions are world pixels minus the camera (the shake moves the camera a few pixels)
function Play.draw_world()
  local ox, oy = Hook.offset()
  local cam = math.max(0, math.floor(Play.cam) - math.floor(ox)) -- the shake at camera 0 must not go negative (street() indexes the zone by it)
  S.count = 0
  camera(0, math.floor(oy))
  far_layer(Play.far, cam)
  if Play.wipe then
    local p = Play.wipe.t / 100
    far_layer(Play.wipe.from, cam)
    clip(math.floor(C.W * (1 - p)), 0, C.W, C.H)
    far_layer(Play.far, cam)
    clip()
  end
  street(cam)
  Props.draw(cam)
  Pows.draw(cam)
  Items.draw(cam)
  Foes.draw(cam)
  Boss.draw(cam)
  Tractor.draw(cam)
  Chef.draw(Play.chef, cam)
  Shots.draw(cam)
  Fx.draw(cam)
  camera()
end

return Play
