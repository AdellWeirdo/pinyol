-- Technical prototype: one actor moves through a side shot, a fixed shot and a rear corridor.
-- Art is deliberately made of shapes; it tests camera continuity before Micromiserias art is spent.
views = require("views")
transition = require("transition")
actor = {x = 10, z = 0, height = 28, miseria = 12}
zone = "side"

local zones = {{id = "side", z0 = 0, z1 = 100}, {id = "fixed", z0 = 100, z1 = 200},
               {id = "rear", z0 = 200, z1 = 320}}
local shots = {
  side = {kind = "side", ox = 80, oy = 214, forward = 1.25, depth = 0.25},
  fixed = {kind = "fixed", ox = 240, oy = 205, cz = 150, basis = {0.65, 0.75, 0, 0.24}, scale = 1, grow = 0.002},
  rear = {kind = "rear", ox = 240, horizon = 88, eye = 114, focal = 80, offset = 40},
}
local labels = {side = "7-G / LATERAL", fixed = "MORRIS / FIJA", rear = "ESTADIO / DETRAS"}
local jump = 0

function _init() show(0) end

function _update()
  transition.update()
  if transition.active() then return end
  local dz = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
  local dx = (btn("down") and 1 or 0) - (btn("up") and 1 or 0)
  actor.z = math.max(0, math.min(319, actor.z + dz * 2.5))
  actor.x = math.max(-70, math.min(70, actor.x + dx * 2))
  if btnp("a") and jump == 0 then jump = 18 end
  if jump > 0 then jump = jump - 1 end
  local wanted = views.pick(zones, actor.x, actor.z, "rear")
  if wanted ~= zone then transition.go("wipe", 0.3, {on_mid = function() zone = wanted end}) end
end

local function hero(shot)
  local sx, sy, scale = views.project(shot, actor.x, actor.z, 0)
  if not sx then return end
  local h = math.floor(43 * scale)
  local w = math.max(8, math.floor(24 * scale))
  local y = math.floor(sy - h - math.sin(jump / 18 * math.pi) * 18)
  circ(math.floor(sx), math.floor(sy + 2), math.max(4, math.floor(w * 0.7)), 0x25182A, true)
  rect(math.floor(sx - w / 2), y + math.floor(h * 0.34), w, math.floor(h * 0.62), 0x466E57)
  circ(math.floor(sx), y + math.floor(h * 0.26), math.max(5, math.floor(w * 0.48)), 0x69A26F, true)
  rect(math.floor(sx - w * 0.25), y + math.floor(h * 0.2), math.max(2, math.floor(w * 0.12)), 2, 0x241D2B)
  rect(math.floor(sx + w * 0.15), y + math.floor(h * 0.2), math.max(2, math.floor(w * 0.12)), 2, 0x241D2B)
end

local function side()
  cls(0x472A3D)
  for i = 0, 5 do circ(i * 110 - 20, -4, 80, 0x783D57, true) end
  rect(0, 196, 480, 90, 0x8D4B53)
  for i = 0, 11 do rect(i * 44, 224, 22, 44, 0xAD6770) end
  rect(0, 264, 480, 56, 0x442437)
  if actor.x >= 25 then rect(116, 72, 28, 184, 0x6B4A60) end
  hero(shots.side)
  if actor.x < 25 then rect(116, 72, 28, 184, 0x6B4A60) end -- pipe hides Yuri only while his feet are behind it
end

local function fixed()
  cls(0x281E35)
  rect(0, 0, 480, 128, 0x654357)
  for i = 0, 5 do rect(24 + i * 88, 48, 50, 54, 0x2D152A) end
  rect(0, 124, 480, 196, 0x886774)
  for i = 0, 8 do line(i * 70 - 60, 320, 220 + (i - 4) * 12, 124, 0xA17983) end
  if actor.z > 150 then rect(42, 176, 396, 69, 0x4E2D38) end
  hero(shots.fixed)
  if actor.z <= 150 then rect(42, 176, 396, 69, 0x4E2D38) end -- the bar is in front at the back of the room
  rect(40, 176, 400, 10, 0xBD8A74)
end

local function rear()
  cls(0x30273E)
  rect(0, 0, 480, 96, 0x594059)
  local shot = shots.rear
  shot.cz = actor.z - 40 -- the camera follows at fixed distance; Yuri keeps his world position
  for y = 108, 319, 12 do
    local half = math.floor((y - 88) * 1.04)
    rect(240 - half, y, half * 2, 12, 0x794652)
  end
  line(229, 108, -1, 320, 0xC88577) line(251, 108, 481, 320, 0xC88577)
  for d = 5, 1, -1 do
    local z = actor.z + d * 52
    local sx, sy, scale = views.project(shot, d % 2 == 0 and -50 or 50, z, 0)
    if sx then rect(math.floor(sx - 9 * scale), math.floor(sy - 30 * scale),
                    math.max(3, math.floor(18 * scale)), math.max(4, math.floor(30 * scale)), 0xE2AD70) end
  end
  hero(shot)
end

function _draw()
  if zone == "side" then side() elseif zone == "fixed" then fixed() else rear() end
  camera()
  rect(0, 0, 480, 31, 0x1A1529)
  text(labels[zone], 10, 8, {font = "arcade", color = 0xEFE0C8})
  text("MISERIA " .. actor.miseria, 455, 8, {font = "arcade", align = "right", color = 0xF0B378})
  rect(0, 289, 480, 31, 0x1A1529)
  text("IZQ/DER: AVANZAR  ARR/ABA: LADO  A: SALTAR", 10, 298, {font = "silk", color = 0xE8D3BC})
  transition.draw()
end
