-- play: the castle. The hero walks it in castle pixels (hero.lua); the room it is in is the one drawn: its map on BG1 (imported from Tiled),
-- the far wall on BG3 at half the speed, the camera inside the room. Walking off a room's edge is walking on: the next room's map is put on
-- BG1 in the same tick, and the picture comes up from dark in a few frames. A jump, B the sword, C the gust (when found), START the map.
local scene = require("scene")
local W = require("world")
local H = require("hero")
local ui = require("ui")

local P = {}
local T = W.T
local HURT_TICKS, SLASH_TICKS, FADE_IN = 50, 10, 8
local BOSS_HP = 10

local hero_sh, things_sh, boss_sh
local enemies, slash, room, cam_x, cam_y, fade_t, t

-- game: everything that is kept, global so the tests and the map read it
game = nil

local function new_game()
  local r, s = W.thing("start")
  local sx, sy = W.world_tile(r, s.tx, s.ty)
  return {hero = H.new(sx * T, sy * T), abilities = {}, hearts = 3, max_hearts = 3, visited = {}, taken = {}, statue = {sx * T, sy * T},
          boss_dead = false, deaths = 0, room_changes = 0}
end

local function save()
  local broken = {}
  for id, cells in pairs(W.broken) do
    broken[id] = {}
    for i in pairs(cells) do broken[id][#broken[id] + 1] = i end
  end
  store("save", {abilities = game.abilities, max_hearts = game.max_hearts, visited = game.visited, taken = game.taken, statue = game.statue,
                 broken = broken})
end

function P.load_saved(s)
  game = new_game()
  game.abilities, game.max_hearts, game.hearts = s.abilities or {}, s.max_hearts or 3, s.max_hearts or 3
  game.visited, game.taken, game.statue = s.visited or {}, s.taken or {}, s.statue or game.statue
  W.broken = {}
  for id, cells in pairs(s.broken or {}) do
    W.broken[id] = {}
    for _, i in ipairs(cells) do W.broken[id][i] = true end
  end
  game.hero = H.new(game.statue[1], game.statue[2])
end

-- ------------------------------------------------------------------ rooms
local function key_of(r, th) return r.id .. ":" .. th.tx .. ":" .. th.ty end

local function clear_broken(r) -- the walls already broken, gone from the picture too (4 map entries a tile)
  for i in pairs(W.broken[r.id] or {}) do
    local tx, ty = (i - 1) % r.w, (i - 1) // r.w
    for dy = 0, 1 do for dx = 0, 1 do mset(1, tx * 2 + dx, ty * 2 + dy, 0) end end
  end
end

local function show_room(r)
  room = r
  game.room = r.id
  game.visited[r.id] = true
  bg(1, {map = r.asset, prio = 1, wrap = false})
  clear_broken(r)
  enemies = {}
  for _, th in ipairs(r.things) do
    local wx, wy = W.world_tile(r, th.tx, th.ty)
    if th.kind == "bat" or th.kind == "slime" then
      enemies[#enemies + 1] = {kind = th.kind, x = wx * T, y = wy * T, home_y = wy * T, hp = 2, dir = -1, hit = 0, t = math.random(0, 60)}
    elseif th.kind == "boss" and not game.boss_dead then
      enemies[#enemies + 1] = {kind = "boss", x = wx * T - 16, y = wy * T - 32, hp = BOSS_HP, hit = 0, t = 0, vy = 0, dir = -1, phase = 1}
    end
  end
  fade_t = 0
end

local function room_px() return room.mx * W.SW * T, room.my * W.SH * T end

local function place_camera()
  local ox, oy = room_px()
  local h = game.hero
  cam_x = math.max(0, math.min(room.w * T - 240, math.floor(h.x - ox - 112)))
  cam_y = math.max(0, math.min(room.h * T - 160, math.floor(h.y - oy - 72)))
end

-- ------------------------------------------------------------------ the hero's troubles
local function overlap(ax, ay, aw, ah, bx, by, bw, bh) return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah end

local function respawn()
  game.deaths = game.deaths + 1
  game.hero = H.new(game.statue[1], game.statue[2])
  game.hearts = game.max_hearts
  game.hurt = 0
  show_room(H.room(game.hero))
  place_camera()
  sfx("DEATH")
end

local function hurt(from_x)
  if (game.hurt or 0) > 0 then return end
  game.hearts = game.hearts - 1
  game.hurt = HURT_TICKS
  local h = game.hero
  h.vx, h.vy, h.dash = (h.x < from_x) and -2.5 or 2.5, -3, 0
  sfx("HURT")
  if game.hearts <= 0 then respawn() end
end

-- ------------------------------------------------------------------ things
local function take(th)
  local k = key_of(room, th)
  if th.kind == "statue" then
    local wx, wy = W.world_tile(room, th.tx, th.ty)
    if game.statue[1] ~= wx * T or game.statue[2] ~= wy * T or game.hearts < game.max_hearts then
      game.statue, game.hearts = {wx * T, wy * T}, game.max_hearts
      save()
      sfx("SAVE")
      game.saved_at = t
    end
    return
  end
  if game.taken[k] then return end
  game.taken[k] = true
  if th.kind == "wings" then game.abilities.wings = true
  elseif th.kind == "gust" then game.abilities.gust = true
  elseif th.kind == "heart" then game.max_hearts, game.hearts = game.max_hearts + 1, game.max_hearts + 1 end
  game.found = {kind = th.kind, t = 0}
  sfx("ITEM")
end

local function things_touch()
  local h = game.hero
  for _, th in ipairs(room.things) do
    if th.kind == "wings" or th.kind == "gust" or th.kind == "heart" or th.kind == "statue" then
      local wx, wy = W.world_tile(room, th.tx, th.ty)
      if overlap(h.x + H.BOX_X0, h.y + H.BOX_Y0, 10, 14, wx * T + 2, wy * T + 2, 12, 14) then take(th) end
    end
  end
end

-- ------------------------------------------------------------------ enemies
local function enemy_box(e)
  if e.kind == "boss" then return e.x + 6, e.y + 6, 36, 40 end
  return e.x + 2, e.y + 3, 12, 12
end

local function move_enemy(e)
  e.t = e.t + 1
  if e.hit > 0 then e.hit = e.hit - 1 end
  if e.kind == "bat" then
    e.x = e.x + e.dir * 0.8
    e.y = e.home_y + math.sin(e.t / 14) * 18
    local ox = room.mx * W.SW * T
    if e.x < ox + 8 or e.x > ox + room.w * T - 24 then e.dir = -e.dir end
  elseif e.kind == "slime" then
    if e.t % 2 == 0 then
      local nx = e.x + e.dir
      local ahead = e.dir > 0 and nx + 14 or nx + 1
      local wall = W.wcell(ahead // T, (e.y + 8) // T)
      local floor = W.wcell(ahead // T, (e.y + 16) // T)
      if wall == W.WALL or wall == W.CRACKED or floor == W.EMPTY then e.dir = -e.dir else e.x = nx end
    end
  elseif e.kind == "boss" then
    local h = game.hero
    e.phase = e.hp <= BOSS_HP // 2 and 2 or 1
    if e.phase == 1 then -- hops toward the hero
      e.vy = math.min(e.vy + 0.25, 5)
      e.y = e.y + e.vy
      local floor_y = (room.my * W.SH + room.h - 1) * T - 48
      if e.y >= floor_y then e.y, e.vy = floor_y, 0 end
      if e.vy == 0 and e.t % 70 == 0 then e.vy, e.dir = -5.5, h.x < e.x + 16 and -1 or 1 end
      if e.vy ~= 0 then e.x = e.x + e.dir * 1.4 end
    else -- flies over the hero, and drops on it
      e.y = (room.my * W.SH + 2) * T + math.sin(e.t / 20) * 16 + (e.t % 120 > 90 and (e.t % 120 - 90) * 2.2 or 0)
      e.x = e.x + (h.x - 16 > e.x and 1.1 or -1.1)
    end
    local ox = room.mx * W.SW * T
    e.x = math.max(ox + T, math.min(ox + room.w * T - T - 48, e.x))
  end
end

local function fight()
  local h = game.hero
  for i = #enemies, 1, -1 do
    local e = enemies[i]
    move_enemy(e)
    local ex, ey, ew, eh = enemy_box(e)
    if slash and slash.t > 0 and e.hit == 0 and overlap(slash.x, slash.y, 16, 14, ex, ey, ew, eh) then
      e.hp, e.hit = e.hp - 1, 14
      sfx("HIT")
      if e.hp <= 0 then
        table.remove(enemies, i)
        if e.kind == "boss" then game.boss_dead = true game.won_at = t sfx("WIN") end
      end
    elseif overlap(h.x + H.BOX_X0, h.y + H.BOX_Y0, 10, 14, ex, ey, ew, eh) and h.dash == 0 then
      hurt(ex + ew / 2)
    end
  end
end

-- ------------------------------------------------------------------ scene
function P.enter(args)
  scene.clean()
  palette("WORLD")
  palette("OBJ", true)
  hero_sh, things_sh, boss_sh = sheet("HERO"), sheet("THINGS"), sheet("BOSS")
  bg(0)
  bg(2)
  bg(3, {map = "FAR", prio = 3})
  backdrop(rgb(12, 10, 22))
  if not args or not args.keep then
    if args and args.saved then P.load_saved(args.saved) else game, W.broken = new_game(), {} end
  end
  t, slash, game.hurt = 0, nil, 0
  show_room(H.room(game.hero))
  place_camera()
end

function P.resume() P.enter({keep = true}) end -- (back from the map)

-- the buttons as hero.lua takes them; the tests give their own (game.input)
function P.input()
  if game.input then return game.input(t) end
  return {left = btn("left"), right = btn("right"), jump = btnp("a"), hold = btn("a"), dash = btnp("c"), attack = btnp("b"), map = btnp("start")}
end

function P.update()
  t = t + 1
  fade_t = fade_t + 1
  if game.won_at then
    if t - game.won_at > 120 then scene.go(require("ending"), nil, {clean = true, fade = 0.6}) end
    return
  end
  local inp = P.input()
  if inp.map then scene.push(require("map")) return end
  local h = game.hero
  if (game.hurt or 0) > 0 then game.hurt = game.hurt - 1 end
  if inp.attack and not slash then slash = {t = SLASH_TICKS} sfx("SWING") end
  local ev = H.step(h, inp, game.abilities)
  if ev.jumped then sfx(ev.double and "JUMP2" or "JUMP") end
  if ev.dashed then sfx("DASH") end
  if ev.broke then
    sfx("BREAK")
    clear_broken(room)
  end
  if slash then
    slash.t = slash.t - 1
    slash.x, slash.y = h.face > 0 and h.x + 12 or h.x - 12, h.y + 1
    if slash.t <= -6 then slash = nil end
  end
  local r = H.room(h)
  if not r then -- out of the castle (it should not happen: the tests check every edge): back to the statue
    respawn()
    return
  end
  if r ~= room then
    game.room_changes = game.room_changes + 1
    show_room(r)
  end
  things_touch()
  fight()
  place_camera()
  if game.found then game.found.t = game.found.t + 1 if game.found.t > 150 then game.found = nil end end
end

-- ------------------------------------------------------------------ drawing
local FRAMES = {bat = 0, slime = 2, wings = 4, gust = 6, heart = 8, statue = 10, slash = 12}

local function draw_world()
  scroll(1, cam_x, cam_y)
  local ox, oy = room_px()
  scroll(3, (ox + cam_x) // 2, (oy + cam_y) // 2)
  local n = 0
  local function put(sh, frame, wx, wy, flags)
    local x, y = math.floor(wx - ox - cam_x), math.floor(wy - oy - cam_y)
    if x > -48 and x < 240 and y > -48 and y < 160 then spr(n, sh, frame, x, y, flags or prio(1)) n = n + 1 end
  end
  local h = game.hero
  local blink = (game.hurt or 0) > 0 and (game.hurt // 3) % 2 == 0
  if not blink then
    local frame = h.dash > 0 and 5 or slash and slash.t > 0 and 4 or not h.ground and 3 or math.abs(h.vx) > 0.3 and 1 + (t // 8) % 2 or 0
    put(hero_sh, frame, h.x, h.y, prio(1) | (h.face < 0 and FLIP_X or 0))
  end
  if slash and slash.t > 0 then put(things_sh, FRAMES.slash + (slash.t < 5 and 1 or 0), slash.x, slash.y, prio(1) | (h.face < 0 and FLIP_X or 0)) end
  for _, e in ipairs(enemies) do
    local flags = prio(1) | (e.dir > 0 and FLIP_X or 0) | (e.hit > 0 and MOSAIC or 0)
    if e.kind == "boss" then put(boss_sh, (t // 12) % 2, e.x, e.y, flags)
    else put(things_sh, FRAMES[e.kind] + (t // 10) % 2, e.x, e.y, flags) end
  end
  for _, th in ipairs(room.things) do
    if FRAMES[th.kind] and th.kind ~= "bat" and th.kind ~= "slime" and not game.taken[key_of(room, th)] then
      local wx, wy = W.world_tile(room, th.tx, th.ty)
      local lit = th.kind == "statue" and game.statue[1] == wx * T and game.statue[2] == wy * T
      local bob = th.kind ~= "statue" and math.floor(math.sin(t / 12) * 2) or 0
      put(things_sh, FRAMES[th.kind] + ((th.kind == "statue" and lit or th.kind ~= "statue" and (t // 16) % 2 == 1) and 1 or 0), wx * T, wy * T + bob)
    end
  end
  mosaic(1, 1, 3, 3)
  for i = n, 40 do spr_off(i) end
end

local NAMES = {wings = "LAS ALAS: A en el aire, otro salto", gust = "LA RÁFAGA: C, y la pared agrietada cede", heart = "UN CORAZÓN MÁS"}

function P.draw()
  draw_world()
  if fade_t < FADE_IN then fade("dark", ALL, math.floor(16 * (1 - fade_t / FADE_IN))) elseif fade_t == FADE_IN then fx_off() end
  for i = 1, game.max_hearts do
    local full = i <= game.hearts
    rect(8 + (i - 1) * 20, 8, 14, 12, full and 0xE04050 or 0x40202A)
    box(8 + (i - 1) * 20, 8, 14, 12, 0xF0E0E0)
  end
  local x = 400
  if game.abilities.wings then text("ALAS", x, 8, {font = "main", color = 0xD0E8FF}) x = x - 52 end
  if game.abilities.gust then text("RÁFAGA", x - 8, 8, {font = "main", color = 0x90E8FF}) end
  if game.found and NAMES[game.found.kind] then
    ui.box(40, 250, 400, 40)
    text(NAMES[game.found.kind], 240, 262, {font = "bold", align = "center", color = ui.SEL})
  end
  if game.saved_at and t - game.saved_at < 90 then text("GUARDADO", 240, 40, {font = "bold", align = "center", color = ui.SEL}) end
  for _, e in ipairs(enemies) do
    if e.kind == "boss" then
      rect(120, 296, 240, 10, 0x201418)
      rect(120, 296, math.floor(240 * e.hp / BOSS_HP), 10, 0xE06040)
      box(120, 296, 240, 10, 0xF0E0E0)
    end
  end
end

P.room = function() return room end
P.enemies = function() return enemies end

return P
