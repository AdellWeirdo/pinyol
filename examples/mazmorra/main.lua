-- Mazmorra: a beat-em-up, the way a CPS2 one looks (art.py): every character in 15 colours and see-through and never
-- zoomed (the hardware had no zoom: everyone keeps the size they were drawn at), a dungeon that goes on (its wall
-- mirrored every other time), torches whose flames move, and pillars nearer than everyone that pass in front of them.
-- Alba (from examples/torneo) against goblins and skeletons that come in groups; the camera stops at each group.
-- A: a slash. B: a kick. Arrows: walk, also up and down the corridor: who is lower on the screen is in front.
local juice = require("juice")
local particles = require("particles")

local WALL_W, LEVEL_W = 720, 720 * 6
local TOP, BOTTOM = 236, 314                  -- the walkable band: where feet can be
local PILLAR_GAP, PILLAR_K = 560, 1.25        -- the pillars in front: how far apart, how much faster than the camera
local TORCH_GAP, TORCH_Y = 360, 112
local GROUPS = {{300, {"goblin", "goblin"}}, {960, {"skeleton", "goblin", "goblin"}}, {1680, {"skeleton", "skeleton"}},
                {2400, {"goblin", "goblin", "goblin", "skeleton"}}, {3300, {"skeleton", "skeleton", "goblin", "goblin"}}}
local MOVES = {
  slash = {frames = {10, 10, 11, 11, 12, 12, 12, 13, 13, 14, 14, 14}, active = 5, reach = 116, depth = 18, damage = 1},
  kick = {frames = {15, 15, 16, 16, 17, 17, 17, 18, 18, 18, 19, 19, 19, 19}, active = 6, reach = 132, depth = 22,
          damage = 2},
}
local IDLE = {0, 1, 2, 3, 4, 3, 2, 1}
local KINDS = {                               -- hit points, walking speed, how near they stop to strike
  goblin = {id = "SPR_GOBLIN", hp = 2, speed = 1.6, near = 70, score = 100},
  skeleton = {id = "SPR_SKELETON", hp = 4, speed = 1.0, near = 90, score = 250},
}

local fx = particles.new()
alba, foes, cam = {}, {}, 0 -- (global: tests/mazmorra.script reads and moves them)
state, score, group = "title", 0, 1
local stop, timer = nil, 0
local look = {}

local function reset()
  alba = {x = 120, y = 290, dir = 1, frame = 0, t = 0, act = "idle", hp = 100, hurt = 0}
  foes, cam, group, stop, score = {}, 0, 1, nil, 0
  fx:clear()
  state, timer = "play", 0
end

function _init()
  show(0) -- no 240x160 world: every pixel at the screen's resolution
  sound("SND_HIT", "hit", 7)
  sound("SND_HEAVY", "hit", 11)
  sound("SND_SWING", {wave = "noise", freq = 900, slide = -4000, sustain = 0.03, decay = 0.08, volume = 0.25})
  sound("SND_DOWN", "explosion", 5)
end

-- ------------------------------------------------------------------ fighting

local function spawn(kinds)
  for i, kind in ipairs(kinds) do
    local left = i % 3 == 0
    local k = KINDS[kind]
    foes[#foes + 1] = {kind = k, x = left and cam - 60 - i * 40 or cam + 540 + i * 50,
                       y = TOP + (i * 31) % (BOTTOM - TOP), dir = left and 1 or -1, hp = k.hp, act = "walk",
                       t = math.random(30), frame = 0, flash = 0, cool = 60 + math.random(90)}
  end
end

local function blow(from, to, push, heavy)
  to.act, to.t, to.flash, to.vx = "hurt", 0, 6, push
  sfx(heavy and "SND_HEAVY" or "SND_HIT")
  fx:burst(to.x - from.dir * 20, to.y - 90, 14, {speed = 3, life = 14, size = 2, colours = {0xFFF0A0, 0xFF6030}})
  juice.freeze(heavy and 6 or 4)
  juice.shake(heavy and 4 or 3)
end

local function update_alba()
  local a = alba
  a.t = a.t + 1
  if a.hurt > 0 then a.hurt = a.hurt - 1 end
  if a.act == "attack" then
    local fr = a.move.frames
    a.frame = fr[math.min(a.t, #fr)]
    if a.t == a.move.active then -- everyone in front, near enough, at about the same depth
      for _, f in ipairs(foes) do
        local d = (f.x - a.x) * a.dir
        if f.act ~= "down" and d > 0 and d < a.move.reach and math.abs(f.y - a.y) < a.move.depth then
          f.hp = f.hp - a.move.damage
          blow(a, f, a.dir * 3, a.move == MOVES.kick)
          if f.hp <= 0 then f.act, f.t = "down", 0 score = score + f.kind.score sfx("SND_DOWN", 0.6) end
        end
      end
    end
    if a.t >= #fr then a.act, a.t = "idle", 0 end
    return
  end
  if a.act == "hurt" then
    a.x = a.x + (a.vx or 0)
    a.frame = a.t < 7 and 20 or 21
    if a.t >= 14 then a.act, a.t = "idle", 0 end
    return
  end
  if a.act == "down" then a.frame = a.t < 24 and 23 or 24 return end
  local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
  local dy = (btn("down") and 1 or 0) - (btn("up") and 1 or 0)
  if dx ~= 0 then a.dir = dx end
  local right = stop and stop + 460 or LEVEL_W - 40
  a.x = math.max(cam + 40, math.min(right, a.x + dx * 2.4))
  a.y = math.max(TOP, math.min(BOTTOM, a.y + dy * 1.6))
  if dx ~= 0 or dy ~= 0 then a.act, a.frame = "walk", 5 + (a.t // 6) % 5
  else a.act, a.frame = "idle", IDLE[(a.t // 8) % #IDLE + 1] end
  if btnp("a") then a.act, a.move, a.t = "attack", MOVES.slash, 0 sfx("SND_SWING", 0.6)
  elseif btnp("b") then a.act, a.move, a.t = "attack", MOVES.kick, 0 sfx("SND_SWING", 0.7) end
end

local function update_foes()
  for i = #foes, 1, -1 do
    local f = foes[i]
    f.t = f.t + 1
    if f.flash > 0 then f.flash = f.flash - 1 end
    if f.act == "down" then
      f.frame, f.x = 9, f.x + (f.vx or 0) * 0.5
      if f.t > 50 then table.remove(foes, i) end
    elseif f.act == "hurt" then
      f.frame, f.x = 8, f.x + (f.vx or 0)
      if f.t >= 16 then f.act, f.t = "walk", 0 end
    elseif f.act == "strike" then
      f.frame = f.t < 8 and 5 or (f.t < 14 and 6 or 7)
      if f.t == 8 and math.abs(alba.x - (f.x + f.dir * f.kind.near * 0.7)) < 50 and math.abs(alba.y - f.y) < 18
         and alba.hurt == 0 and alba.act ~= "down" then
        alba.hp, alba.hurt, alba.act, alba.t, alba.vx = alba.hp - 8, 30, "hurt", 0, f.dir * 2
        blow(f, alba, f.dir * 2)
        if alba.hp <= 0 then alba.act, alba.t, state, timer = "down", 0, "over", 0 end
      end
      if f.t >= 22 then f.act, f.t = "walk", 0 end
    else -- walk to a spot in front of Alba, at her depth, and wait for the moment to strike
      f.dir = alba.x < f.x and -1 or 1
      local gx, gy = alba.x - f.dir * f.kind.near, alba.y
      local dx, dy = gx - f.x, gy - f.y
      local moving = math.abs(dx) > 6 or math.abs(dy) > 4
      if math.abs(dx) > 6 then f.x = f.x + (dx > 0 and f.kind.speed or -f.kind.speed) end
      if math.abs(dy) > 4 then f.y = f.y + (dy > 0 and 1 or -1) end
      f.frame = moving and (f.t // 7) % 5 or 0
      f.cool = f.cool - 1
      if not moving and f.cool <= 0 then f.act, f.t, f.cool = "strike", 0, 70 + math.random(80) end
    end
  end
end

-- ------------------------------------------------------------------ the loop

function _update()
  local frozen = juice.update()
  fx:update()
  timer = timer + 1
  if state == "title" then
    if btnp("a") or btnp("start") then reset() end
    return
  end
  if frozen then return end
  if state ~= "play" then
    if state == "over" then alba.t = alba.t + 1 alba.frame = alba.t < 24 and 23 or 24 end
    if timer > 90 and btnp("a") then state = "title" end
    return
  end
  update_alba()
  update_foes()
  if not stop and GROUPS[group] and cam >= GROUPS[group][1] then -- the camera stops; the group comes
    stop = GROUPS[group][1]
    spawn(GROUPS[group][2])
    group = group + 1
  end
  if stop and #foes == 0 then stop = nil end
  if not stop then cam = math.max(cam, math.min(LEVEL_W - 480, alba.x - 200)) end
  if not stop and not GROUPS[group] and #foes == 0 and cam >= LEVEL_W - 480 - 40 then state, timer = "clear", 0 end
end

-- ------------------------------------------------------------------ drawing

local MIRROR = {flip_x = true}
local cast = {}

local function torches(c) -- flames that move: a flicker of three tongues and sparks going up
  for x = (c // TORCH_GAP) * TORCH_GAP + TORCH_GAP // 2, c + 480 + TORCH_GAP, TORCH_GAP do
    local sx, n = x - c, noise(x, timer / 9)
    rect(sx - 3, TORCH_Y, 6, 22, 0x3A2418)
    circ(sx, TORCH_Y - 4, 7 + math.floor(n * 2), 0xC03010)
    circ(sx + math.floor(n * 3), TORCH_Y - 8, 5, 0xFF8020)
    circ(sx, TORCH_Y - 6, 3, 0xFFE070)
    if timer % 6 == 0 then
      fx:burst(sx, TORCH_Y - 12, 1, {speed = 0.8, angle = -90, spread = 40, life = 24, size = 1,
                                     colours = {0xFFE070, 0xFF8020, 0x601810}})
    end
  end
end

local function draw_one(c, id, frame, back, w, feet, faces_right)
  local flip = faces_right == (c.dir < 0)
  look.frame, look.flip_x = frame, flip
  look.tint = c.flash and c.flash > 0 and c.flash % 4 < 2 and 0xFFFFFF or (c.act == "down" and c.t % 6 < 3 and 0x401030) or nil
  shade(c.x - cam - 34, c.y - 4, 68, 8) -- a shadow on the flagstones
  img(id, c.x - cam - (flip and w - 1 - back or back), c.y - feet, look)
end

function _draw()
  if state == "title" then
    img("BG_DUNGEON", 0, 0)
    torches(0)
    look.frame, look.flip_x, look.tint = IDLE[(timer // 8) % #IDLE + 1], false, nil
    img("SPR_ALBA", 60, 300 - 172, look)
    look.frame, look.flip_x = (timer // 7) % 5, false
    img("SPR_SKELETON", 250, 300 - 156, look)
    img("SPR_GOBLIN", 330, 306 - 156, look)
    fx:draw()
    text("MAZMORRA", 240, 20, {font = "arcade", scale = 3, align = "center", color = 0xFFF0A0, gradient = 0xC06010,
                               outline = 0x100808, shadow = 0x000000})
    if (timer // 30) % 2 == 0 then
      text("PULSA A", 240, 76, {font = "arcade", align = "center", color = 0xFFFFFF, outline = 0x100808})
    end
    return
  end
  local ox, oy = juice.offset()
  camera(ox, oy)
  local first = cam // WALL_W
  for w = first, first + 1 do
    if w % 2 == 1 then img("BG_DUNGEON", w * WALL_W - cam, 0, MIRROR) else img("BG_DUNGEON", w * WALL_W - cam, 0) end
  end
  torches(cam)
  local n = 1 -- everyone, the farthest (highest on the screen) first
  cast[1] = alba
  for _, f in ipairs(foes) do n = n + 1 cast[n] = f end
  for i = n + 1, #cast do cast[i] = nil end
  table.sort(cast, function(a, b) return a.y < b.y end)
  for _, c in ipairs(cast) do
    if c == alba then
      if alba.hurt % 6 < 4 or alba.act == "down" then draw_one(c, "SPR_ALBA", c.frame, 76, 208, 172, true) end
    else draw_one(c, c.kind.id, c.frame, 110, 176, 156, false) end
  end
  fx:draw()
  local off = math.floor(cam * PILLAR_K) % PILLAR_GAP -- the pillars, nearer than everyone
  for x = -off + 200, 480, PILLAR_GAP do img("BG_PILLAR", x, 0) end
  camera()
  rect(14, 12, 204, 16, 0x100808)
  rect(16, 14, math.max(0, math.floor(2 * alba.hp)), 12, 0x30C040)
  text("ALBA", 16, 32, {font = "arcade", color = 0xFFFFFF, outline = 0x100808})
  text(string.format("%06d", score), 464, 12, {font = "arcade", scale = 2, align = "right", color = 0xFFF0A0,
                                               outline = 0x100808})
  if not stop and state == "play" and timer % 60 < 40 and cam > 0 then
    text("ADELANTE >", 464, 150, {font = "arcade", align = "right", color = 0xFFE070, outline = 0x100808})
  end
  if state == "over" then
    text("FIN", 240, 120, {font = "arcade", scale = 4, align = "center", color = 0xFFFFFF, gradient = 0xC02020,
                           outline = 0x100808})
  elseif state == "clear" then
    text("MAZMORRA", 240, 100, {font = "arcade", scale = 3, align = "center", color = 0xFFF0A0, outline = 0x100808})
    text("SUPERADA", 240, 140, {font = "arcade", scale = 3, align = "center", color = 0xFFF0A0, outline = 0x100808})
  end
  juice.draw()
end
