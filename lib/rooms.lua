-- rooms: a game as places you walk between, each a room with its backdrop, walls, doors, people and things, that
-- remembers what you did in it. A game of forty rooms is forty tables and the code of what happens in them; this does
-- the rest: the curtain that closes on the door, the loading of what the next room needs behind it, the camera, the
-- walls, the doors, what is near enough to talk to, and what a room was like when you left (a bottle taken stays taken).
--
--   local rooms = require("rooms")
--   rooms.define({
--     id = "bar", district = "bar", w = 640, h = 320,           -- the room's size: wider than the screen scrolls
--     layers = {{pic = "BG_BAR_FAR", parallax = 0.5}, {pic = "BG_BAR"}},   -- behind everyone, in order
--     front = {{pic = "FG_STOOLS"}},                            -- in front of everyone (a pillar they pass behind)
--     occluders = require("bg_bar_depth"),                      -- pieces of the backdrop at their own depth (tools/depthcut.py):
--                                                               -- the counter hides the player behind it, not in front of it
--     solids = {{x = 0, y = 290, w = 640, h = 30}},             -- boxes nobody walks into
--     spawns = {door = {x = 40, y = 230}, default = {x = 300, y = 230}},
--     exits = {{x = 0, y = 150, w = 12, h = 140, to = "street", spawn = "from_bar"}},   -- a door: walking into it
--     things = {{id = "morris", x = 380, y = 200, w = 30, h = 90, pic = "SPR_MORRIS", talk = "morris"},
--               {id = "llave", x = 520, y = 260, w = 16, h = 16, pic = "ICO_LLAVE", take = "llave",
--                when = function() return rooms.flag("bar", "abierto") end}},
--     variant = function() return miseria > 70 and "crisis" or nil end,   -- which look it has now (nil: the plain one)
--     variants = {crisis = {layers = {{pic = "BG_BAR_RED"}}}},  -- what changes in that look: any field, replaced whole
--     assets = {images = {"BG_BAR", "SPR_MORRIS"}, sounds = {"SFX_GLASS"}},   -- read behind the curtain, not on the way
--     enter = function(room, spawn) end, leave = function(room) end, update = function(room) end,
--   })
--   rooms.player = {x = 100, y = 200, w = 20, h = 50}           -- what the camera follows and the walls stop
--   rooms.go("bar", "door")                                     -- in _init; the curtain closes, the room opens
--   function _update() rooms.update()                           -- (the curtain and the room's update)
--     if not rooms.busy() then                                  -- not while the curtain moves
--       rooms.move(rooms.player, dx, dy)                        -- a step, stopped by walls and the room's edge
--       local e = rooms.exit_at(rooms.player) if e then rooms.take(e) end
--       local t = rooms.thing_near(rooms.player, 24) if t and btnp("a") then ... t.talk, t.take ... end
--     end
--   end
--   function _draw() rooms.draw(function() draw_the_player() end, player.y + player.h) end   -- drawn among the things, by z
--
-- A thing is {id, x, y, w, h, pic, frame, flip, talk, take, use, when, draw, z}: `pic` is drawn at x, y (or `draw =
-- function(thing, x, y)`), `when` hides it while it returns false, `z` orders them (default y + h: lower is further).
-- What a thing does when used is the game's: rooms only finds it (`thing_near`) and remembers it gone (`remove`).
--
-- Remembering: rooms.flag(room, key [, value]) reads or sets a fact about a room; rooms.remove(id) takes a thing for
-- good; rooms.visits(room) counts how many times you came in. store("rooms", rooms.save()) and rooms.load(stored("rooms")).
local ok_cam, cam = pcall(require, "cam")
local M = {}

local defs, S = {}, {} -- the rooms as defined; what each remembers: S[id] = {visits, gone = {thing = true}, flags = {}}
local cur, nxt, phase, t = nil, nil, "idle", 0 -- the room now; the one going to; "out", "in" (the curtain), "idle"
M.player, M.cam = nil, nil
M.curtain = {time = 18, kind = "blinds", bars = 10, color = 0x000000} -- ticks each way; "blinds" or "cut"

local function state(id)
  S[id] = S[id] or {visits = 0, gone = {}, flags = {}}
  return S[id]
end

function M.define(def)
  assert(def and def.id, "rooms.define: a room needs an id")
  def.w, def.h = def.w or SCREEN_W, def.h or SCREEN_H
  defs[def.id] = def
  return def
end

-- the room as it is now: its own fields, with those of the variant it has laid over them
local function build(id)
  local d = assert(defs[id], "rooms: no room \"" .. tostring(id) .. "\"")
  local r = setmetatable({}, {__index = d})
  local v = d.variant and d.variant(d)
  r.look = v
  if v and d.variants and d.variants[v] then
    for k, val in pairs(d.variants[v]) do r[k] = val end
  end
  return r
end

function M.preload(id) -- a room's pictures and sounds, read now (a neighbour you are about to enter)
  local d = defs[id]
  if d and d.assets then preload(d.assets) end
end

-- ------------------------------------------------------------------ going between rooms
local function arrive(id, spawn)
  cur = build(id)
  local st = state(id)
  st.visits = st.visits + 1
  local at = cur.spawns and (cur.spawns[spawn or "default"] or cur.spawns.default)
  if M.player and at then M.player.x, M.player.y = at.x, at.y end
  if ok_cam then
    M.cam = cam.new({bounds = {0, 0, cur.w, cur.h}, deadzone = {60, 40}, lerp = 0.18})
    if M.player then M.cam:follow(M.player, (M.player.w or 0) / 2, (M.player.h or 0) / 2):snap() end
  end
  if cur.enter then cur.enter(cur, spawn) end
end

-- Goes to a room: the curtain closes, the old room is left, the new one read and set up, the curtain opens. `spawn` is
-- where the player appears (a name in the room's spawns); {kind = "cut"} skips the curtain.
function M.go(id, spawn, o)
  assert(defs[id], "rooms.go: no room \"" .. tostring(id) .. "\"")
  o = o or {}
  if phase == "out" then return end -- one curtain at a time
  nxt = {id = id, spawn = spawn}
  if (o.kind or M.curtain.kind) == "cut" or not cur then
    if cur and cur.leave then cur.leave(cur) end
    M.preload(id)
    arrive(id, spawn)
    nxt, phase = nil, "idle"
  else
    phase, t = "out", 0
  end
end

function M.busy() return phase ~= "idle" end
function M.current() return cur end
function M.id() return cur and cur.id end

function M.take(exit) -- an exit's door
  M.go(exit.to, exit.spawn)
end

-- ------------------------------------------------------------------ walking
local function overlap(a, b) return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h end

local function blocked(e)
  if not cur then return false end
  if e.x < 0 or e.y < 0 or e.x + e.w > cur.w or e.y + e.h > cur.h then return true end
  for _, s in ipairs(cur.solids or {}) do
    if not s.when or s.when(cur) then
      if overlap(e, s) then return true end
    end
  end
  return false
end

-- A step of dx, dy (pixels): one axis at a time, so a wall slides you along it. Returns true for each axis that was stopped.
function M.move(e, dx, dy)
  local hit_x, hit_y = false, false
  local step = dx > 0 and 1 or -1
  for _ = 1, math.floor(math.abs(dx) + 0.5) do
    e.x = e.x + step
    if blocked(e) then e.x = e.x - step hit_x = true break end
  end
  step = dy > 0 and 1 or -1
  for _ = 1, math.floor(math.abs(dy) + 0.5) do
    e.y = e.y + step
    if blocked(e) then e.y = e.y - step hit_y = true break end
  end
  return hit_x, hit_y
end

function M.solid_at(x, y, w, h) return blocked({x = x, y = y, w = w or 1, h = h or 1}) end

function M.exit_at(e)
  if not cur then return nil end
  for _, x in ipairs(cur.exits or {}) do
    if (not x.when or x.when(cur)) and overlap(e, x) then return x end
  end
  return nil
end

-- ------------------------------------------------------------------ things
local function visible(th)
  local st = state(cur.id)
  if th.id and st.gone[th.id] then return false end
  return not th.when or th.when(cur)
end

function M.things()
  local out = {}
  if cur then
    for _, th in ipairs(cur.things or {}) do
      if visible(th) then out[#out + 1] = th end
    end
  end
  return out
end

function M.thing(id)
  for _, th in ipairs(M.things()) do if th.id == id then return th end end
  return nil
end

-- the nearest thing the player could use: horizontally within `reach` pixels of it and overlapping it up and down
function M.thing_near(e, reach)
  local best, bd = nil, 1e9
  reach = reach or 24
  for _, th in ipairs(M.things()) do
    if th.talk or th.take or th.use then
      local ex, ey = e.x - reach, e.y
      if ex < th.x + (th.w or 0) and th.x < e.x + e.w + reach and ey < th.y + (th.h or 0) and th.y < e.y + e.h then
        local d = math.abs((th.x + (th.w or 0) / 2) - (e.x + e.w / 2))
        if d < bd then best, bd = th, d end
      end
    end
  end
  return best
end

function M.remove(id, room) state(room or (cur and cur.id)).gone[id] = true end

function M.flag(room, key, value)
  local f = state(room).flags
  if value ~= nil then f[key] = value end
  return f[key]
end

function M.visits(room) return state(room).visits end

-- the room's look is worked out again (a miseria that crossed a line while you are in it): what changes is laid over
function M.refresh()
  if cur then
    cur = build(cur.id)
  end
end

function M.save() return {rooms = S, at = cur and cur.id} end

function M.load(data)
  if type(data) ~= "table" then return end
  S = data.rooms or {}
  for _, st in pairs(S) do st.gone, st.flags = st.gone or {}, st.flags or {} end
end

-- ------------------------------------------------------------------ the curtain, the tick, the drawing
-- What is drawn between the back layers and the front ones, nearest the horizon first: the things, the pieces of the
-- backdrop that stand in front of what is behind them (occluders: {pic, x, y, z}) and, if there is one, the player.
local function drawing_order(between, z)
  local list = M.things()
  for _, o in ipairs(cur.occluders or {}) do
    if not o.when or o.when(cur) then list[#list + 1] = o end
  end
  if between then list[#list + 1] = {z = z or 1e9, draw = between, player = true} end
  table.sort(list, function(a, b) return (a.z or a.y + (a.h or 0)) < (b.z or b.y + (b.h or 0)) end)
  return list
end

function M.order(between, z) -- who is drawn in what order: their ids ("player" for the one between), for tests and tools
  local out = {}
  if cur then
    for _, th in ipairs(drawing_order(between, z)) do out[#out + 1] = th.player and "player" or th.id or th.pic end
  end
  return out
end

function M.update()
  if phase == "out" then
    t = t + 1
    if t >= M.curtain.time then
      if cur and cur.leave then cur.leave(cur) end
      M.preload(nxt.id) -- behind the closed curtain
      arrive(nxt.id, nxt.spawn)
      nxt, phase, t = nil, "in", 0
    end
  elseif phase == "in" then
    t = t + 1
    if t >= M.curtain.time then phase, t = "idle", 0 end
  end
  if cur then
    if cur.update then cur.update(cur) end
    if M.cam and not (phase == "out") then M.cam:update() end
  end
end

local function layer_draw(list)
  for _, l in ipairs(list or {}) do
    local p = l.parallax or 1
    -- a layer with parallax 1 sits on the room; less moves slower than the camera (it sits further back)
    local cx, cy = M.cam and M.cam.x or 0, M.cam and M.cam.y or 0
    img(l.pic, (l.x or 0) + math.floor(cx * (1 - p)), (l.y or 0) + math.floor(cy * (1 - p)), {frame = l.frame or 0})
  end
end

local function curtain_draw()
  if phase == "idle" then return end
  local k = phase == "out" and t / M.curtain.time or 1 - t / M.curtain.time
  if k <= 0 then return end
  camera()
  local n = M.curtain.bars
  local bw = SCREEN_W / n
  for i = 0, n - 1 do
    local w = math.ceil(bw * math.min(1, k))
    rect(math.floor(i * bw), 0, w, SCREEN_H, M.curtain.color)
  end
end

-- draws the room: the back layers, the things, the front layers, the curtain. `between` draws the player (or anyone
-- who is not a thing) among the things, at depth `z` (a thing's z is its feet by default: y + h; the player's feet too, so
-- he is behind what is nearer the bottom of the screen); without z, in front of all of them.
function M.draw(between, z)
  if not cur then return end
  if M.cam then M.cam:apply() end
  layer_draw(cur.layers)
  if cur.draw_back then cur.draw_back(cur) end
  for _, th in ipairs(drawing_order(between, z)) do
    if th.draw then th.draw(th, th.x, th.y)
    elseif th.pic then img(th.pic, th.x, th.y, {frame = th.frame or 0, flip_x = th.flip}) end
  end
  layer_draw(cur.front)
  if cur.draw_front then cur.draw_front(cur) end
  camera()
  curtain_draw()
end

return M
