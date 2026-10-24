-- play: a stage. It sets everything up for a hero, runs a tick of the world (the camera that only goes forward and stops where a wave must be beaten, the foes that come in from the
-- sides, the props, the pickups, the boss at the end of the last stage) and draws the frame in painting order: the street (three painted chunks, each a whole scene), then everything that stands on it from the
-- back of the street floor to the front (sorted by depth), then the pillars in front of the seams and the effects.
local C = require("core.const")
local U = require("core.util")
local S = require("core.spr")
local L = require("core.level")
local Run = require("core.run")
local Hero = require("core.hero")
local Foes = require("core.foes")
local Props = require("core.props")
local Items = require("core.items")
local Boss = require("core.boss")
local Fx = require("core.fx")
local Sound = require("core.sound")
local Music = require("core.music")
local Hook = require("core.juice_hook")
local Play = {}

Play.hero = nil
Play.cam = 0
Play.state = "play"      -- play, boss, clear, over
Play.ev_i = 1
Play.lock = nil          -- the camera may not go past this while a wave lives
Play.queue = {}
Play.banner_t = 0
Play.go_t = 0
Play.t = 0
Play.clear_t = 0

local function drop(f)
  local h = Play.hero
  if Run.kills % 5 == 0 or math.random() < 0.08 then Items.add_part(f.x, f.y) end
  if h.hp < h.max_hp * 0.5 and math.random() < 0.3 then Items.add("oil", f.x + 20, f.y) end
  if math.random() < 0.08 then Items.add("watch", f.x - 20, f.y) end
end

local function broke(p)
  local r = math.random()
  if r < 0.30 then Items.add_part(p.x, p.y) elseif r < 0.55 then Items.add("oil", p.x, p.y) elseif r < 0.75 then Items.add("watch", p.x, p.y) end
end

function Play.stage() return L.STAGES[Run.stage] end

function Play.start_stage(n, keep_hero)
  Run.stage = n
  Foes.clear() Props.clear() Items.clear() Fx.clear() Boss.reset()
  Foes.on_die, Props.on_break = drop, broke
  Play.cam, Play.state, Play.ev_i, Play.lock, Play.queue, Play.t, Play.clear_t = 0, "play", 1, nil, {}, 0, 0
  Play.banner_t, Play.go_t = 170, 0
  local h = Play.hero
  h.x, h.y, h.z, h.st, h.t, h.inv, h.held, h.win_t = 110, 272, 0, "idle", 0, C.INVULN, nil, 0
  Music.play(Play.stage().music, 300)
end

function Play.enter(hero_id)
  Run.reset(hero_id)
  Play.hero = Hero.new(hero_id, 110, 272)
  Play.start_stage(1)
end

local function spawn_event(e)
  if e.wave then for _, w in ipairs(e.wave) do Play.queue[#Play.queue + 1] = {kind = w[1], side = w[2], t = w[3]} end end
  if e.props then for _, p in ipairs(e.props) do Props.add(p[1], p[2]) end end
end

local function respawn(h)
  h.hp, h.st, h.t, h.z, h.vz, h.vx = h.max_hp, "idle", 0, 0, 0, 0
  h.x, h.y = Play.cam + 130, 272
  h.inv = C.INVULN
  h.part = nil
  h.meter = 0
end

Play.respawn = respawn

-- the continue: a new set of lives, the same place
function Play.continue()
  local h = Play.hero
  h.lives = C.LIVES
  respawn(h)
  Play.state = Boss.active and "boss" or "play"
  Music.play(Boss.active and "jefe" or Play.stage().music, 200)
end

function Play.update(t)
  local h = Play.hero
  Play.t = Play.t + 1
  Run.t = Run.t + 1
  h:update(Play.cam)
  -- the camera goes forward only, and stops where a wave is
  if Play.state == "play" and h.st ~= "dead" then
    local limit = Play.lock or L.END_CAM
    Play.cam = U.clamp(math.max(Play.cam, h.x - 210), Play.cam, limit)
    local st = Play.stage()
    while st.events[Play.ev_i] and Play.cam >= st.events[Play.ev_i].at do
      local e = st.events[Play.ev_i]
      spawn_event(e)
      if e.lock then Play.lock = Play.cam end
      Play.ev_i = Play.ev_i + 1
    end
  end
  for i = #Play.queue, 1, -1 do
    local q = Play.queue[i]
    q.t = q.t - 1
    if q.t <= 0 then
      Foes.spawn_at(q.kind, q.side, Play.cam)
      table.remove(Play.queue, i)
    end
  end
  if Play.lock and #Play.queue == 0 and Foes.count() == 0 then Play.lock = nil Play.go_t = 1 end
  if Play.go_t > 0 then Play.go_t = Play.go_t + 1 if Play.go_t > 240 then Play.go_t = 0 end end
  Foes.update(h, Play.cam)
  Boss.update(h, Play.cam)
  Props.update(Play.cam)
  Items.update(h, Play.cam)
  Fx.update()
  if Play.banner_t > 0 then Play.banner_t = Play.banner_t - 1 end
  -- the end of the stage: the last foe at the end of the street, then the boss (stage 3) or the tally
  if Play.state == "play" and not Play.lock and Play.cam >= L.END_CAM - 1 and Foes.count() == 0 and #Play.queue == 0 and h.st ~= "dead" then
    if Run.stage >= #L.STAGES then
      Play.state = "boss"
      Boss.enter(Play.cam)
      Play.banner_t = 160
    else
      Play.state, h.st, h.win_t, Play.clear_t = "clear", "win", 0, 0
      Music.jingle("victoria", 5, false)
    end
  end
  if Play.state == "boss" and Boss.done then
    Play.state, h.st, h.win_t, Play.clear_t = "clear", "win", 0, 0
    Run.boss_dead = true
    Music.jingle("victoria", 6, false)
  end
  if Play.state == "clear" then Play.clear_t = Play.clear_t + 1 end
  -- the hero fell for good, or gets up again
  if h.st == "dead" and h.t > 110 then
    if h.lives > 0 then respawn(h) else Play.state = "over" end
  end
end

-- ------------------------------------------------------------------ drawing

local function street(cam, st)
  for i, name in ipairs(st.near) do
    local x = (i - 1) * C.CHUNK - cam
    if x < C.W and x + C.CHUNK > 0 then S.back(name, x, 0) end
  end
end

local scene, fxl = {}, {}

function Play.draw_world()
  local ox, oy = Hook.offset()
  local cam = math.floor(Play.cam) - math.floor(ox)
  local st = Play.stage()
  S.count = 0
  camera(0, math.floor(oy))
  street(cam, st)
  for i = #scene, 1, -1 do scene[i] = nil end
  Props.collect(scene, cam)
  Items.collect(scene, cam)
  Foes.collect(scene, cam)
  Boss.collect(scene, cam)
  table.sort(scene, function(a, b) return a.y < b.y end)
  -- the hero is painted by depth among the props and the pickups, but ALWAYS over the automatons and the boss: an enemy never hides a hero
  local hero = {}
  Play.hero:collect(hero, cam)
  local at, last_foe = #scene + 1, 0
  for i, e in ipairs(scene) do
    if e.foe then last_foe = i end
    if e.y > Play.hero.y and at > #scene then at = i end
  end
  at = math.max(at, last_foe + 1)
  table.insert(scene, math.min(at, #scene + 1), hero[1])
  for _, e in ipairs(scene) do e.draw() end
  for i = #fxl, 1, -1 do fxl[i] = nil end
  Fx.collect(fxl, cam) -- the hit sparks, steam and dust over everyone
  for _, e in ipairs(fxl) do e.draw() end
  -- the pillars in front of the seams: they hide where two chunks of street join and put the hero behind them as a CPS2 stage did
  for k = 1, 2 do
    local x = k * C.CHUNK - cam
    if x > -80 and x < C.W + 80 then S.draw("pillars", st.pillar, x, 319, {}) end
  end
  camera()
end

return Play
