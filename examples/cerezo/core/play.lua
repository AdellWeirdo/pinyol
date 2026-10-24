-- play: the game while the hero walks the world: the screens, the slide between them, what lives on each.
local C = require("core.const")
local U = require("core.util")
local W = require("core.world")
local E = require("core.ents")
local Music = require("core.music")
local S = require("core.spr")
local Hero = require("core.hero")
local Things = require("core.things")
require("core.dungeon")
require("core.boss")
local FX = require("core.fx")
local Pal = require("core.pal")
local Game = require("core.game")

local P = {}

P.t = 0
P.slide = nil
P.fading = nil   -- a change of area in progress: {phase = "out" or "in", t, to = {area, cx, cy, face}}

local SLIDE_TICKS = 26

-- puts the hero in an area at a cell and spawns what lives on that screen
function P.enter(aid, cx, cy, face)
  E.clear()
  FX.clear()
  W.load(aid, 0, 0)
  local sx, sy = math.floor(cx / C.SW), math.floor(cy / C.SH)
  W.set_screen(sx, sy)
  Game.seen[aid .. ":" .. sx .. "," .. sy] = true
  Hero.new(cx * C.T, cy * C.T - 4, face)
  P.spawn_screen(sx, sy)
  P.slide = nil
  if not P.quiet then Music.play(Music.for_screen(W.area, sx, sy)) end
end

-- goes to another area through a fade (the console's way: four steps of palette to the darkest and back)
local FADE_STEP = 5
function P.go(aid, cx, cy, face, opts)
  if P.fading then return end
  P.fading = {phase = "out", t = 0, to = {aid, cx, cy, face}, opts = opts or {}}
  local h = E.hero
  if h then require("core.hero").set(h, "talk") end
end

local function update_fade()
  local f = P.fading
  f.t = f.t + 1
  local step = f.t // FADE_STEP
  if f.phase == "out" then
    Pal.fade("dark", math.min(3, step))
    if step >= 4 then
      P.enter(f.to[1], f.to[2], f.to[3], f.to[4])
      f.phase, f.t = "in", 0
      Pal.fade("dark", 3)
    end
  else
    Pal.fade("dark", math.max(0, 3 - step))
    if step >= 4 then
      Pal.fade("dark", 0)
      P.fading = nil
      local h = E.hero
      if h then require("core.hero").set(h, "walk") end
    end
  end
end

-- what lives on a screen is made when the hero comes to it; the doors that count the pests last, after the pests
local LAST = {gate = true, keydrop = true}
function P.spawn_screen(sx, sy)
  for pass = 1, 2 do
    for _, def in ipairs(W.area.things) do
      if (LAST[def.kind] and 2 or 1) == pass and math.floor(def.cx / C.SW) == sx and math.floor(def.cy / C.SH) == sy then
        local e = Things.spawn(def)
        if e then e.scr = sx .. "," .. sy end
      end
    end
  end
end

function P.despawn_screen(sx, sy)
  local key = sx .. "," .. sy
  for _, e in ipairs(E.list) do
    if e.scr == key then e.dead = true end
  end
end

-- the screen the hero's body is in
local function edge(h)
  local cx, cy = h.x + 8, h.y + 11
  if cx < W.cam_x then return -1, 0 end
  if cx >= W.cam_x + C.PW then return 1, 0 end
  if cy < W.cam_y then return 0, -1 end
  if cy >= W.cam_y + C.PH then return 0, 1 end
  return 0, 0
end

-- every screen of the island seen: an achievement
function P.check_map()
  local n = 0
  for k in pairs(Game.seen) do if k:sub(1, 10) == "overworld:" then n = n + 1 end end
  if n >= 9 then achieve("cartografo") end
end

function P.begin_slide(dx, dy)
  local h = E.hero
  P.slide = {t = 0, dx = dx, dy = dy, from_x = W.cam_x, from_y = W.cam_y, to_x = W.cam_x + dx * C.PW, to_y = W.cam_y + dy * C.PH,
             old = {W.sx, W.sy}, new = {W.sx + dx, W.sy + dy}, hx = h.x, hy = h.y}
  P.spawn_screen(W.sx + dx, W.sy + dy)
  W.sync_anim(W.sx + dx, W.sy + dy)
  h.moving = true
end

function P.update_slide()
  local s = P.slide
  s.t = s.t + 1
  local k = s.t / SLIDE_TICKS
  W.cam_x = math.floor(s.from_x + (s.to_x - s.from_x) * k)
  W.cam_y = math.floor(s.from_y + (s.to_y - s.from_y) * k)
  local h = E.hero
  h.x = s.hx + s.dx * 18 * k
  h.y = s.hy + s.dy * 18 * k
  h.anim = h.anim + 1
  if s.t >= SLIDE_TICKS then
    W.set_screen(s.new[1], s.new[2])
    Game.seen[W.aid .. ":" .. s.new[1] .. "," .. s.new[2]] = true
    P.check_map()
    Music.play(Music.for_screen(W.area, s.new[1], s.new[2]))
    P.despawn_screen(s.old[1], s.old[2])
    h.x, h.y = math.floor(h.x), math.floor(h.y)
    -- the 18 px push may leave him inside a wall: put him on the nearest free spot
    local Hero = require("core.hero")
    if not Hero.free(h, h.x, h.y) then
      local fx, fy
      for r = 1, 40 do
        for dy = -r, r do
          for dx = -r, r do
            if not fx and (math.abs(dx) == r or math.abs(dy) == r) and Hero.free(h, h.x + dx, h.y + dy) then fx, fy = h.x + dx, h.y + dy end
          end
        end
        if fx then break end
      end
      if fx then h.x, h.y = fx, fy end
    end
    P.slide = nil
  end
end

function P.update()
  P.t = P.t + 1
  if P.fading then
    update_fade()
    return
  end
  if P.slide then
    local s = P.slide
    P.update_slide()
    W.update(P.t, {s.new})
    return
  end
  FX.update()
  if FX.freeze_t > 0 then FX.freeze_t = FX.freeze_t - 1 return end -- a hit stops the world a moment
  E.update()
  local h = E.hero
  local dx, dy = edge(h)
  if dx ~= 0 or dy ~= 0 then
    if W.exists(W.sx + dx, W.sy + dy) then P.begin_slide(dx, dy) end
  end
  W.update(P.t)
end

function P.draw()
  if not W.area or not E.hero then return end -- (the opening's words come before any place)
  W.scroll()
  S.begin()
  E.draw()
  require("core.scenefx").apply(P.t)
end

return P
