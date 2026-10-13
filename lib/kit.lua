-- kit: the game model behind np2d's editor (editor/): a map of tiles, objects that move by themselves, events. A game
-- made in the editor is its data (data.lua: pictures, map, objects, sounds, made by the editor) and the code of its
-- blocks, which calls kit. A hand-written game can use it too.
--
--   local kit = require("kit")
--   kit.setup(require("data"))
--   kit.on("press", "a", function() kit.sound("salto") end)
--   kit.on("touch", "heroe", "moneda", function(este, otro) kit.destroy(otro) puntos = puntos + 1 end)
--   function _init() kit.init() end  function _update() kit.update() end  function _draw() kit.draw() end
--
-- Coordinates are the world's pixels (240x160 on screen at a time, each shown 2x2). The map is a grid of tiles of
-- `tile` pixels; tiles named in data.solid are walls and floors. Objects are of a kind (data.kinds) that says their
-- picture and how they move: "platformer" (the player: arrows and A to jump), "topdown" (the player: four ways),
-- "patrol" (walks and turns at walls and edges), "chase" (goes after the player), "shot" (flies straight, gone at a
-- wall), "still". Events: "start", "tick", "press" and "hold" (a button), "touch" (two kinds meet), "tile" (a kind
-- on a tile), "every" (seconds), "tap" (a finger, where in the world).
local juice = require("juice")
local particles = require("particles")

local M = {}
local D = {}                         -- the game's data
local T = 16                          -- tile size
local objs, nextid = {}, 1
local handlers
local contacts = {}                   -- pairs touching last tick: "touch" fires when they start
local on_tile = {}
local labels, message, message_t = {}, nil, 0
local cam = {x = 0, y = 0}
local fx
local ended                           -- {text, won} once the game is won or lost
local timer = 0
local cells                           -- the map's tile names, row by row

local BUTTONS = {a = true, b = true, c = true, up = true, down = true, left = true, right = true, start = true}

local function reset_handlers()
  handlers = {start = {}, tick = {}, press = {}, hold = {}, touch = {}, tile = {}, every = {}, tap = {}}
end
reset_handlers()

function M.setup(data)
  D = data or {}
  T = D.tile or 16
  D.kinds, D.sprites, D.solid, D.sounds = D.kinds or {}, D.sprites or {}, D.solid or {}, D.sounds or {}
end

-- ------------------------------------------------------------------ events

-- on("start" | "tick", fn); on("press" | "hold", button, fn); on("touch", kind, kind, fn(this, other));
-- on("tile", kind, tile, fn(this, tx, ty)); on("every", seconds, fn); on("tap", fn(x, y))
function M.on(what, a, b, c)
  local list = handlers[what]
  assert(list, "kit.on: no event called " .. tostring(what))
  if what == "start" or what == "tick" then list[#list + 1] = a
  elseif what == "press" or what == "hold" then
    assert(BUTTONS[a], "kit.on: no button called " .. tostring(a))
    list[#list + 1] = {button = a, fn = b}
  elseif what == "touch" or what == "tile" then list[#list + 1] = {a = a, b = b, fn = c}
  elseif what == "every" then list[#list + 1] = {ticks = math.max(1, math.floor((tonumber(a) or 1) * 60 + 0.5)), fn = b}
  elseif what == "tap" then list[#list + 1] = a end
end

-- ------------------------------------------------------------------ the map

local function tile_index(tx, ty)
  if not D.map or tx < 0 or ty < 0 or tx >= D.map.w or ty >= D.map.h then return nil end
  return ty * D.map.w + tx + 1
end

function M.tile(x, y) -- the name of the tile at a world point, or nil
  local i = tile_index(math.floor(x / T), math.floor(y / T))
  return i and cells[i] or nil
end

local function solid_at(tx, ty)
  if not D.map then return false end
  if tx < 0 or tx >= D.map.w then return true end -- the map's sides are walls; above and below are open
  local i = tile_index(tx, ty)
  local name = i and cells[i]
  return name ~= nil and D.solid[name] == true
end

local function paint_tile(tx, ty)
  local name = cells[tile_index(tx, ty)]
  target("KIT_MAP")
  rect(tx * T, ty * T, T, T, CLEAR)
  if name and D.sprites[name] then img("SPR_" .. name, tx * T, ty * T, 0) end
  target()
end

function M.set_tile(x, y, name) -- a tile changed while playing: a door opens, a block breaks
  local tx, ty = math.floor(x / T), math.floor(y / T)
  local i = tile_index(tx, ty)
  if not i then return end
  cells[i] = (name ~= "" and name) or nil
  paint_tile(tx, ty)
end

-- ------------------------------------------------------------------ objects

function M.spawn(kind, x, y)
  local k = D.kinds[kind]
  if not k then return nil end
  local s = D.sprites[k.sprite or kind] or {w = T, h = T, frames = 1}
  local o = {id = nextid, kind = kind, sprite = k.sprite or kind, x = x or 0, y = y or 0, w = s.w, h = s.h, vx = 0,
             vy = 0, flip = false, frame = 0, anim = 0, ground = false, alive = true, dir = 1}
  nextid = nextid + 1
  if k.behaviour == "patrol" then o.vx = k.speed or 1 end
  objs[#objs + 1] = o
  return o
end

function M.destroy(o) if o then o.alive = false end end

function M.all(kind)
  local list = {}
  for _, o in ipairs(objs) do if o.alive and (not kind or o.kind == kind) then list[#list + 1] = o end end
  return list
end

function M.first(kind)
  for _, o in ipairs(objs) do if o.alive and o.kind == kind then return o end end
end

function M.count(kind) return #M.all(kind) end

function M.player() -- whom the camera follows, or the first player-like object
  if D.camera then
    local o = M.first(D.camera)
    if o then return o end
  end
  for _, o in ipairs(objs) do
    local b = o.alive and D.kinds[o.kind] and D.kinds[o.kind].behaviour
    if b == "platformer" or b == "topdown" then return o end
  end
end

function M.set_sprite(o, name) if o and D.sprites[name] then o.sprite = name end end

-- what the blocks read and change: an object that is not there (nil, or gone) is quietly left alone
local PROPS = {x = true, y = true, vx = true, vy = true}
function M.get(o, prop) return o and PROPS[prop] and o[prop] or 0 end
function M.set(o, prop, v) if o and o.alive and PROPS[prop] then o[prop] = tonumber(v) or 0 end end
function M.change(o, prop, dv) if o and o.alive and PROPS[prop] then o[prop] = o[prop] + (tonumber(dv) or 0) end end
function M.spawn_at(kind, o) -- a new one where another is (a shot from the player, a coin where an enemy was)
  if not o then return nil end
  local n = M.spawn(kind, o.x, o.y)
  if n then n.x, n.y = o.x + (o.w - n.w) / 2, o.y + (o.h - n.h) / 2 end
  if n and o.flip then n.flip = true end
  return n
end

-- moving with the map's walls in the way: one axis then the other, stopped at the tile's edge
local function hits_wall(x, y, w, h) -- the box [x, x + w) x [y, y + h): positions have fractions
  for ty = math.floor(y / T), math.floor((y + h - 0.001) / T) do
    for tx = math.floor(x / T), math.floor((x + w - 0.001) / T) do
      if solid_at(tx, ty) then return true end
    end
  end
  return false
end

local function move(o, solid)
  o.ground = false
  if not solid then o.x, o.y = o.x + o.vx, o.y + o.vy return end
  local hit = false
  local nx = o.x + o.vx
  if hits_wall(nx, o.y, o.w, o.h) then
    nx = o.vx > 0 and math.floor((nx + o.w) / T) * T - o.w or (math.floor(nx / T) + 1) * T
    if hits_wall(nx, o.y, o.w, o.h) then nx = o.x end
    o.vx, hit = 0, true
  end
  o.x = nx
  local ny = o.y + o.vy
  if hits_wall(o.x, ny, o.w, o.h) then
    if o.vy > 0 then
      ny = math.floor((ny + o.h) / T) * T - o.h
      o.ground = true
    else
      ny = (math.floor(ny / T) + 1) * T
    end
    if hits_wall(o.x, ny, o.w, o.h) then ny = o.y end
    o.vy, hit = 0, true
  end
  o.y = ny
  return hit
end

local function behave(o)
  local k = D.kinds[o.kind] or {}
  local b, speed = k.behaviour or "still", k.speed or 1.5
  local gravity = k.gravity
  if gravity == nil then gravity = b == "platformer" or b == "patrol" end
  if b == "platformer" then
    local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
    o.vx = dx * speed
    if dx ~= 0 then o.flip = dx < 0 end
    if btnp("a") and o.ground then o.vy = -(k.jump or 4.5) end
  elseif b == "topdown" then
    local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
    local dy = (btn("down") and 1 or 0) - (btn("up") and 1 or 0)
    o.vx, o.vy = dx * speed, dy * speed
    if dx ~= 0 then o.flip = dx < 0 end
  elseif b == "patrol" then
    if o.vx == 0 then o.dir = -o.dir end
    if gravity and o.ground then -- turns at the edge of what it walks on
      local ahead = o.dir > 0 and o.x + o.w + 1 or o.x - 1
      if not solid_at(math.floor(ahead / T), math.floor((o.y + o.h + 1) / T)) then o.dir = -o.dir end
    end
    o.vx = o.dir * speed
    o.flip = o.dir < 0
  elseif b == "chase" then
    local p = M.player()
    if p and p ~= o then
      local dx, dy = p.x - o.x, p.y - o.y
      local d = math.sqrt(dx * dx + dy * dy)
      if d > 1 then
        o.vx = dx / d * speed
        if not gravity then o.vy = dy / d * speed end
        o.flip = dx < 0
      end
    end
  end
  if gravity then o.vy = math.min(o.vy + (k.weight or 0.25), 6) end
  local wall = move(o, k.solid ~= false and b ~= "shot")
  if b == "shot" and (wall or (D.map and hits_wall(o.x, o.y, o.w, o.h))) then o.alive = false end
  if (k.animate or 0) > 0 then -- frames go round while it moves (or always, for things that are not players)
    local moving = o.vx ~= 0 or o.vy ~= 0 or (b ~= "platformer" and b ~= "topdown")
    o.anim = moving and o.anim + 1 or 0
    local s = D.sprites[o.sprite]
    o.frame = s and s.frames > 1 and (o.anim // k.animate) % s.frames or 0
  end
end

local function overlap(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- ------------------------------------------------------------------ what the blocks do besides

function M.label(key, text, where) -- a text on the screen from now on (where: "top_left", "top", "top_right", "bottom")
  if text == nil then labels[key] = nil return end
  labels[key] = {text = tostring(text), where = where or "top_left"}
end

function M.message(text, seconds) message, message_t = tostring(text), math.floor((seconds or 2) * 60) end

function M.sound(name) if D.sounds[name] then sfx("SND_" .. name) end end

function M.shake(px) juice.shake(px or 4) end

function M.burst(x, y, colour, n)
  fx:burst(x, y, n or 16, {speed = 2, colours = {colour or 0xFFE070, 0xFFFFFF}, gravity = 0.06, life = 30, size = 2})
end
function M.burst_at(o, colour) if o then M.burst(o.x + o.w / 2, o.y + o.h / 2, colour) end end

function M.win(text) ended = {text = text or "¡Has ganado!", won = true} M.sound("ganar") end
function M.lose(text) ended = {text = text or "Has perdido", won = false} M.sound("perder") end

-- ------------------------------------------------------------------ the loop

local function start_over()
  objs, contacts, on_tile, labels, message, ended, timer = {}, {}, {}, {}, nil, nil, 0
  cells = {}
  if D.map then
    for i = 1, D.map.w * D.map.h do
      local t = D.map.cells[i] or 0
      cells[i] = t > 0 and D.map.tiles[t] or nil
    end
    canvas("KIT_MAP", D.map.w * T, D.map.h * T)
    for ty = 0, D.map.h - 1 do for tx = 0, D.map.w - 1 do if cells[tile_index(tx, ty)] then paint_tile(tx, ty) end end end
    bg(0, {image = "KIT_MAP", wrap = false})
  end
  for _, p in ipairs(D.objects or {}) do M.spawn(p.kind, p.x, p.y) end
  fx = particles.new()
  juice.reset()
  for _, f in ipairs(handlers.start) do f() end
end

function M.init()
  backdrop(D.background or 0x6CB4E0)
  show(D.map and BG0 or 0)
  for name, p in pairs(D.sounds) do -- {recipe = "coin", seed = 3} or the numbers themselves
    if p.recipe then sound("SND_" .. name, p.recipe, p.seed or 1) else sound("SND_" .. name, p) end
  end
  if not D.sounds.ganar then D.sounds.ganar = sound("SND_ganar", "powerup", 4) end
  if not D.sounds.perder then D.sounds.perder = sound("SND_perder", "hit", 9) end
  start_over()
end

function M.restart() start_over() end

local function pair_key(a, b) return a.id * 65536 + b.id end

function M.update()
  if ended then
    if btnp("a") or select(4, touch()) then start_over() end
    return
  end
  if juice.update() then return end
  timer = timer + 1
  for _, h in ipairs(handlers.press) do if btnp(h.button) then h.fn() end end
  for _, h in ipairs(handlers.hold) do if btn(h.button) then h.fn() end end
  local tx, ty, _, tapped = touch()
  if tapped then for _, f in ipairs(handlers.tap) do f(tx + cam.x, ty + cam.y) end end
  for _, o in ipairs(objs) do if o.alive then behave(o) end end
  local now = {}
  for _, h in ipairs(handlers.touch) do -- each pair once, when it starts touching
    for _, a in ipairs(objs) do
      if a.alive and a.kind == h.a then
        for _, b in ipairs(objs) do
          if b.alive and b ~= a and b.kind == h.b and overlap(a, b) then
            local k = pair_key(a, b)
            now[k] = true
            if not contacts[k] then h.fn(a, b) end
          end
        end
      end
    end
  end
  contacts = now
  local tiles_now = {}
  for _, h in ipairs(handlers.tile) do
    for _, o in ipairs(objs) do
      if o.alive and o.kind == h.a then
        for cy = math.floor(o.y / T), math.floor((o.y + o.h - 0.001) / T) do
          for cx = math.floor(o.x / T), math.floor((o.x + o.w - 0.001) / T) do
            local i = tile_index(cx, cy)
            if i and cells[i] == h.b then
              local k = o.id * 100000 + i
              tiles_now[k] = true
              if not on_tile[k] then h.fn(o, cx * T, cy * T) end
            end
          end
        end
      end
    end
  end
  on_tile = tiles_now
  for _, h in ipairs(handlers.every) do if timer % h.ticks == 0 then h.fn() end end
  for _, f in ipairs(handlers.tick) do f() end
  for i = #objs, 1, -1 do if not objs[i].alive then table.remove(objs, i) end end
  fx:update()
  if message_t > 0 then message_t = message_t - 1 end
  local p = M.player() -- the camera: on the player, within the map
  if p then
    local mw, mh = D.map and D.map.w * T or 240, D.map and D.map.h * T or 160
    cam.x = math.max(0, math.min(mw - 240, math.floor(p.x + p.w / 2 - 120)))
    cam.y = math.max(0, math.min(mh - 160, math.floor(p.y + p.h / 2 - 80)))
  end
end

local PLACES = {top_left = {12, 8, "left"}, top = {240, 8, "center"}, top_right = {468, 8, "right"},
                bottom = {240, 290, "center"}, bottom_left = {12, 290, "left"}, bottom_right = {468, 290, "right"}}

function M.draw()
  local sx, sy = juice.offset()
  if D.map then scroll(0, cam.x - sx // 2, cam.y - sy // 2) end
  for _, o in ipairs(objs) do
    if o.alive then
      local x, y = (o.x - cam.x) * 2 + sx, (o.y - cam.y) * 2 + sy
      if x > -64 and x < SCREEN_W + 64 and y > -64 and y < SCREEN_H + 64 then
        if o.flip then img("SPR_" .. o.sprite, x, y, {frame = o.frame, scale = 2, flip_x = true})
        else img("SPR_" .. o.sprite, x, y, o.frame, 2) end
      end
    end
  end
  camera((cam.x * 2 - sx), (cam.y * 2 - sy))
  local g = fx -- the particles are in world pixels: drawn 2x by hand
  for _, p in ipairs(g.list) do
    local age = 1 - p.left / p.life
    circ(p.x * 2, p.y * 2, math.max(1, p.size * 2 * (1 - age)), p.colours[math.min(#p.colours, 1 + math.floor(age * #p.colours))])
  end
  camera()
  for _, l in pairs(labels) do
    local at = PLACES[l.where] or PLACES.top_left
    text(l.text, at[1], at[2], {font = "bold", color = 0xFFFFFF, outline = 0x202020, align = at[3]})
  end
  if message and message_t > 0 then
    text(message, SCREEN_W // 2, 140, {font = "large_bold", color = 0xFFFFFF, outline = 0x202020, align = "center",
                                       width = 440})
  end
  if ended then
    shade(0, 0, SCREEN_W, SCREEN_H)
    text(ended.text, SCREEN_W // 2, 120, {font = "large_bold", color = ended.won and 0xFFE070 or 0xFF7060,
                                          outline = 0x202020, align = "center", width = 440})
    text("A: otra vez", SCREEN_W // 2, 180, {font = "bold", color = 0xFFFFFF, outline = 0x202020, align = "center"})
  end
  juice.draw()
end

-- for tests and the editor's preview
function M.objects() return objs end
function M.camera_at() return cam.x, cam.y end
function M.reset_events() reset_handlers() end

return M
