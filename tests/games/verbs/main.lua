-- The everyday verbs (tests/verbs.script): buttons, input actions, timers and scripts, chained tweens, named
-- animations, a following camera, a stack of scenes, text with marks.
juice = require("juice")
input = require("input")
anim = require("anim")
cam = require("cam")
scene = require("scene")
rich = require("rich")

log_ = {}
LABEL = {color = 0xFFFFFF, outline = 0x000000}
function note(s) log_[#log_ + 1] = s end
function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

input.map({jump = {"b"}, fire = {"a", "c"}})
reps, buffered = 0, 0
hero = {x = 100, y = 100, vx = 0}
c = cam.new({bounds = {0, 0, 2000, 320}, deadzone = {80, 60}, lerp = 0.5})
c:follow(hero)
a = anim.new({idle = {frames = {0}}, run = {frames = {1, 2, 3, 4}, fps = 10},
              shoot = {frames = {5, 6}, ms = {50, 100}, loop = false, next = "idle", events = {[2] = "fire"}},
              bob = {frames = {7, 8, 9}, fps = 30, mode = "pingpong"}, once = {frames = {1, 2}, fps = 30, loop = false}})
fired = 0
a:on("fire", function() fired = fired + 1 end)

-- scenes
entered = {}
title = {}
function title.enter(args) note("title enter " .. tostring(args and args.n)) end
function title.leave() note("title leave") end
function title.pause() note("title pause") end
function title.resume(r) note("title resume " .. tostring(r)) end
function title.update() title.ticks = (title.ticks or 0) + 1 end
function title.draw() cls(0x203040) text("TITLE", 10, 10) end
pause = {overlay = true}
function pause.enter() note("pause enter") end
function pause.update() pause.ticks = (pause.ticks or 0) + 1 end
function pause.draw() shade(100, 100, 280, 120) text("PAUSA", 200, 150) end
level = {}
function level.enter(args) note("level enter " .. tostring(args and args.n)) end
function level.update() end
function level.draw() cls(0x402020) end

function _init() show(0) scene.go(title, {n = 1}) end

function _update()
  juice.update()
  if btnp("down", 10, 4) then reps = reps + 1 end
  held_max = math.max(held_max or 0, btnt("down"))
  if input.buffered("jump", 6) then buffered = buffered + 1 end
  a:update()
  c:update()
  scene.update()
  if shown_text then shown_text:update() end
end

function _draw()
  scene.draw()
  if shown_text then shown_text:draw(20, 200) end
  if rich_label then rich.draw(rich_label, 20, 60, LABEL) end
end
