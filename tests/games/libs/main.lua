-- The libraries built into pinyol (lib/*.lua), each used as a game would (tests/libs.script checks them).
juice = require("juice")
particles = require("particles")
physics = require("physics")
keyboard = require("keyboard")
voice = require("voice")
rich = require("rich")
sound("BEEP", "blip")
abuela = voice.new({sound = "BEEP", pitch = 0.8, every = 2})

door = {y = 0}
fx = particles.new()
world = physics.world({gravity = 0.3})
ball = world:circle(100, 20, 10, {bounce = 0.5})
box = world:box(160, 0, 30, 30)
floor = world:box(0, 300, 480, 20, {static = true})
anchor = world:circle(300, 40, 4, {static = true})
bob = world:circle(380, 40, 6)
world:rope(anchor, bob, 60)
kb = keyboard.new({title = "Nombre", max = 6})
writing = false
result = nil
hits = 0

function _init() show(0) end

function _update()
  if juice.update() then return end
  fx:update()
  world:step()
  hits = hits + #world:hits()
  if writing then result = kb:update() or result end
end

function _draw()
  rect(0, 0, SCREEN_W, SCREEN_H, 0x203040)
  camera(juice.offset())
  rect(40, door.y, 60, 20, 0xF2B233)
  circ(ball.x, ball.y, ball.r, 0xFFFFFF)
  rect(box.x, box.y, box.w, box.h, 0xE8443A)
  rect(floor.x, floor.y, floor.w, floor.h, 0x506070)
  line(anchor.x, anchor.y, bob.x, bob.y, 0xFFFFFF)
  circ(bob.x, bob.y, bob.r, 0x7CE0FF)
  fx:draw()
  camera()
  if writing then kb:draw() end
  juice.draw()
end
