-- cine: cutscenes written as a script that waits: `Cine.run(function() Cine.say("intro_1") Cine.wait(30) ... end)`.
-- A script is a coroutine; each wait gives the frame back and the next tick goes on from there. While one runs, the hero
-- does not take the buttons (START skips what has `skippable`).
local E = require("core.ents")
local Dialog = require("core.dialog")
local Pal = require("core.pal")
local U = require("core.util")
local Cine = {}

local co
Cine.on_skip = nil
Cine.draw_fn = nil -- a function that draws over the game while a scene runs (a plain screen with words)

function Cine.running() return co ~= nil end

function Cine.run(fn, on_skip)
  co = coroutine.create(fn)
  Cine.on_skip = on_skip
end

function Cine.update()
  if not co then return false end
  if Cine.on_skip and btnp("start") and not Dialog.active then
    local f = Cine.on_skip
    co, Cine.on_skip = nil, nil
    f()
    return false
  end
  local ok, err = coroutine.resume(co)
  if not ok then error(err) end
  if coroutine.status(co) == "dead" then co, Cine.on_skip = nil, nil return false end
  return true
end

function Cine.wait(n)
  for _ = 1, n do coroutine.yield() end
end

function Cine.wait_until(fn)
  while not fn() do coroutine.yield() end
end

-- a conversation: this returns when it is over
function Cine.say(knot, opts)
  Dialog.start(knot, opts)
  while Dialog.active do coroutine.yield() end
end

-- a fade of the palette to the darkest (or to white), `kind` "dark" or "light", in four steps of `step` ticks
function Cine.fade_out(kind, step)
  step = step or 5
  for lv = 1, 3 do Pal.fade(kind or "dark", lv) Cine.wait(step) end
  Pal.fade(kind or "dark", 3)
  Cine.wait(step)
end

function Cine.fade_in(kind, step)
  step = step or 5
  for lv = 2, 0, -1 do Pal.fade(kind or "dark", lv) Cine.wait(step) end
end

-- walks an entity to a pixel (the sprite's top-left), `speed` pixels a tick, ignoring the map; it faces the way it goes
function Cine.walk(e, tx, ty, speed)
  speed = speed or 0.8
  e.walking = true
  while math.abs(e.x - tx) > speed or math.abs(e.y - ty) > speed do
    local dx, dy = tx - e.x, ty - e.y
    e.face = U.dir_of(dx, dy)
    local len = math.sqrt(dx * dx + dy * dy)
    e.x, e.y = e.x + dx / len * speed, e.y + dy / len * speed
    e.anim = (e.anim or 0) + 1
    coroutine.yield()
  end
  e.x, e.y, e.walking = tx, ty, false
  e.anim = 0
end

return Cine
