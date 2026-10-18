-- scene: a game as scenes (the title, a level, the pause menu, a shop) on a stack, as hump.gamestate and Phaser do.
-- The one on top gets the ticks; those under an overlay are still drawn. Changes wait for the end of the tick, so a
-- scene that changes the scene from its own update finishes it first.
--
--   local scene = require("scene")
--   local title = {}
--   function title.enter(args) ... end      -- also leave(), pause() (something pushed on it), resume(), update(), draw()
--   function title.update() if btnp("a") then scene.go(level, {n = 1}, {fade = 0.4}) end end
--   function title.draw() ... end
--   local pause = {overlay = true}          -- drawn over the scene under it, which stays as it was
--   scene.go(title)                         -- in _init
--   function _update() scene.update() end   function _draw() scene.draw() end
--
-- scene.go(s, args, {fade, transition}) empties the stack for s (the sprites of the scenes leaving are taken away: spr_clear,
-- and juice's tweens, timers and scripts stop: a cutscene of the level does not go on in the title);
-- scene.push(s, args) puts s on top; scene.pop(result) goes back, the scene under it gets resume(result).
-- scene.top() is the scene on top, scene.depth() how many there are.
local ok_juice, juice = pcall(require, "juice")
local M = {}
local stack, pending, fading = {}, nil, nil

local function call(s, name, ...) if s and s[name] then return s[name](...) end end

local function apply(p)
  if p.kind == "go" then
    while #stack > 0 do call(table.remove(stack), "leave") end
    if spr_clear then spr_clear() end
    if ok_juice then juice.reset() end
    stack[1] = p.scene
    call(p.scene, "enter", p.args)
  elseif p.kind == "push" then
    call(stack[#stack], "pause")
    stack[#stack + 1] = p.scene
    call(p.scene, "enter", p.args)
  elseif p.kind == "pop" then
    call(table.remove(stack), "leave")
    call(stack[#stack], "resume", p.args)
  end
end

function M.go(s, args, opts)
  assert(type(s) == "table", "scene.go: a scene is a table")
  local p = {kind = "go", scene = s, args = args}
  local secs = opts and opts.fade or 0
  if secs > 0 then fading = {p = p, len = math.max(1, math.floor(secs * 30 + 0.5)), t = 0, opts = opts} -- out, then in
  else pending = p end
end
function M.push(s, args) assert(type(s) == "table", "scene.push: a scene is a table") pending = {kind = "push", scene = s, args = args} end
function M.pop(result) pending = {kind = "pop", args = result} end
function M.top() return stack[#stack] end
function M.depth() return #stack end

function M.update()
  if fading then -- dark, then the change, then light again
    fading.t = fading.t + 1
    if fading.t == fading.len then apply(fading.p) end
    if fading.t >= 2 * fading.len then fading = nil end
    if fading and fading.t <= fading.len then return end -- (no ticks while it goes dark)
  end
  call(stack[#stack], "update")
  if pending then
    local p = pending
    pending = nil
    apply(p)
  end
end

function M.draw()
  local first = #stack
  while first > 1 and stack[first].overlay do first = first - 1 end
  for i = math.max(1, first), #stack do call(stack[i], "draw") end
  if fading then -- the screen darkened in five steps, as old consoles faded
    local k = fading.t <= fading.len and fading.t / fading.len or 2 - fading.t / fading.len
    camera()
    clip()
    if fading.opts.transition then -- one of transition's kinds, with its options (color, dir, cx, cy...) from the same table
      require("transition").draw_kind(fading.opts.transition, k, fading.opts)
      return
    end
    local steps = math.floor(k * 5 + 0.5)
    if steps >= 5 then rect(0, 0, SCREEN_W, SCREEN_H, 0x000000)
    else for _ = 1, steps do shade(0, 0, SCREEN_W, SCREEN_H) end end
  end
end

function M.reset() stack, pending, fading = {}, nil, nil end

return M
