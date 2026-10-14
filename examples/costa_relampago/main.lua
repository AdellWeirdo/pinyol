-- Ardilla Relámpago: Costa Esmeralda. Mundo 240x160, arte de 16 bits.
local WORLD_W = 1920
local ACCEL, BRAKE, FRICTION, TOP = 0.18, 0.42, 0.075, 6.8
local GRAVITY, JUMP, MAX_FALL = 0.28, -5.7, 7.5
local LOOP_X, LOOP_Y, LOOP_R = 960, 96, 32
local TAU = math.pi * 2
local hero_sh, enemy_sh, fruit_sh, spring_sh, goal_sh
fruits, enemies, springs = {}, {}, {} -- exposed for headless gameplay tests
P = {}
state, cam, score, collected, lives, clock = "title", 0, 0, 0, 3, 0
local frame, state_time, loop_done, best_time = 0, 0, false, nil

-- Art generator uses same slope endpoints. Feet follow surface pixel by pixel.
local slopes = {
  {280, 360, 128, 104}, {480, 560, 104, 128},
  {1080, 1160, 128, 112}, {1280, 1360, 112, 128},
  {1510, 1570, 128, 112}, {1690, 1750, 112, 128},
}
local function ground_y(x)
  if x >= 360 and x < 480 then return 104 end
  if x >= 1160 and x < 1280 then return 112 end
  if x >= 1570 and x < 1690 then return 112 end
  for _, slope in ipairs(slopes) do
    if x >= slope[1] and x < slope[2] then
      return slope[3] + (slope[4] - slope[3]) * (x - slope[1]) / (slope[2] - slope[1])
    end
  end
  return 128
end

local function overlap(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

local function put_fruit(x, y)
  fruits[#fruits + 1] = {x = x, y = y, taken = false}
end

local function reset_level()
  fruits, enemies, springs = {}, {}, {}
  for x = 100, 1820, 68 do
    local rise = ((x // 68) % 3 == 0) and 28 or 17
    put_fruit(x, ground_y(x) - rise)
  end
  for _, x in ipairs({315, 340, 365, 710, 735, 930, 955, 980, 1120, 1145, 1180, 1540, 1570, 1600}) do
    put_fruit(x, ground_y(x) - 48)
  end
  for _, x in ipairs({540, 805, 1240, 1460, 1720}) do
    enemies[#enemies + 1] = {x = x, base = ground_y(x), phase = x * 0.1, alive = true}
  end
  for _, x in ipairs({650, 1380}) do springs[#springs + 1] = {x = x, t = 0} end
  P = {x = 36, y = 96, vx = 0, vy = 0, ground = true, face = 1,
       ball = false, invuln = 0, loop_t = 0, dead = 0, jump_hold = false}
  cam, score, collected, lives, clock, loop_done = 0, 0, 0, 3, 0, false
end

local function start_play()
  reset_level()
  bg(3, {map = "FAR", prio = 3})
  bg(1, {map = "LEVEL", prio = 1, wrap = false})
  show(BG3 | BG1 | OBJ)
  state, state_time = "play", 0
end

function _init()
  hero_sh, enemy_sh, fruit_sh = sheet("HERO"), sheet("BEETLE"), sheet("GEM")
  spring_sh, goal_sh = sheet("SPRING"), sheet("GOAL")
  palette("OBJ", true)
  for y = 0, 159 do
    local k = math.min(1, y / 100)
    line_backdrop(y, rgb(19 + 119 * k, 86 + 126 * k, 185 + 56 * k))
  end
  sound("JUMP", "jump", 4)
  sound("FRUIT", "coin", 6)
  sound("HIT", "hit", 4)
  sound("POP", "explosion", 3)
  sound("BOOST", {wave = "saw", freq = 330, slide = 1400, sustain = 0.07, decay = 0.15, volume = 0.22})
  sound("WIN", "powerup", 7)
  best_time = stored("best_time")
  start_play()
  state = "title"
end

local function hurt()
  if P.invuln > 0 or P.dead > 0 then return end
  lives = lives - 1
  P.invuln, P.vy, P.vx, P.ground = 90, -4, -P.face * 2.4, false
  collected = math.max(0, collected - 5)
  sfx("HIT")
  if lives <= 0 then P.dead = 1 end
end

local function begin_loop()
  P.loop_t, P.ground, P.ball, P.vy = 1, false, true, 0
  loop_done = true
  sfx("BOOST")
end

local function move_loop()
  -- Clockwise full turn. Tangent points right at entry and exit.
  local angle = math.pi / 2 - TAU * P.loop_t / 42
  P.x = LOOP_X + math.cos(angle) * LOOP_R - 16
  P.y = LOOP_Y + math.sin(angle) * LOOP_R - 32
  P.loop_t = P.loop_t + 1
  if P.loop_t > 42 then
    P.loop_t, P.x, P.y, P.vx, P.vy = 0, LOOP_X + 17, 96, math.max(P.vx, 5.5), 0
    P.ground, P.ball = true, false
  end
end

local function move_player()
  if P.loop_t > 0 then move_loop() return end
  local input = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
  if input ~= 0 then
    P.face = input
    local accel = P.vx * input < 0 and BRAKE or ACCEL
    P.vx = math.max(-TOP, math.min(TOP, P.vx + input * accel))
  elseif P.ground then
    P.vx = P.vx > 0 and math.max(0, P.vx - FRICTION) or math.min(0, P.vx + FRICTION)
  end
  if P.ground and btnb("a") then
    P.vy, P.ground, P.ball, P.jump_hold = JUMP, false, true, true
    sfx("JUMP")
  end
  if P.jump_hold and not btn("a") and P.vy < -2.3 then P.vy, P.jump_hold = -2.3, false end
  local old_ground = P.ground
  local old_x = P.x
  P.x = math.max(0, math.min(WORLD_W - 32, P.x + P.vx))
  local old_feet = P.y + 32
  local floor = ground_y(P.x + 16)
  if old_ground and floor < old_feet and old_feet - floor <= 3 then
    P.y, P.vy = floor - 32, 0
  else
    P.vy = math.min(MAX_FALL, P.vy + GRAVITY)
    P.y = P.y + P.vy
    P.ground = false
    if P.vy >= 0 and P.y + 32 >= floor and old_feet <= floor + 3 then
      P.y, P.vy, P.ground, P.ball = floor - 32, 0, true, false
    end
  end
  -- Crest launches fast runners. Downhill returns speed.
  if old_ground and P.ground and P.vx > 4 and ((old_x + 16 < 360 and P.x + 16 >= 360)
       or (old_x + 16 < 1160 and P.x + 16 >= 1160) or (old_x + 16 < 1570 and P.x + 16 >= 1570)) then
    P.vy, P.ground = -2.4, false
  end
  if P.ground and floor > ground_y(P.x + 12) and P.vx > 0 then P.vx = math.min(TOP, P.vx + 0.07) end
  if not loop_done and P.ground and P.vx >= 3.8 and P.x + 16 >= LOOP_X - 2 and old_x + 16 < LOOP_X then
    begin_loop()
  end
end

local function update_play()
  clock = clock + 1
  if P.dead > 0 then
    P.dead, P.y, P.vy = P.dead + 1, P.y + P.vy, P.vy + GRAVITY
    if P.dead > 85 then state, state_time = "over", 0 end
    return
  end
  if P.invuln > 0 then P.invuln = P.invuln - 1 end
  move_player()
  for _, f in ipairs(fruits) do
    if not f.taken and overlap(P.x + 8, P.y + 6, 18, 26, f.x - 8, f.y - 8, 16, 16) then
      f.taken, collected, score = true, collected + 1, score + 100
      sfx("FRUIT", 0.4)
    end
  end
  for _, s in ipairs(springs) do
    if s.t > 0 then s.t = s.t - 1 end
    local sy = ground_y(s.x) - 16
    if P.loop_t == 0 and P.vy >= 0 and overlap(P.x + 8, P.y + 23, 16, 10, s.x - 8, sy, 16, 16) then
      P.vy, P.ground, P.ball, P.jump_hold, s.t = -8.5, false, true, false, 10
      sfx("BOOST")
    end
  end
  for _, e in ipairs(enemies) do
    if e.alive then
      e.x = e.x + math.sin(clock / 20 + e.phase) * 0.55
      local ey = ground_y(e.x) - 32
      if P.loop_t == 0 and overlap(P.x + 9, P.y + 7, 16, 24, e.x + 7, ey + 15, 18, 15) then
        if P.ball or (P.vy > 1.5 and P.y + 26 < ey + 18) then
          e.alive, P.vy, P.ground, score = false, -3.5, false, score + 250
          sfx("POP")
        else hurt() end
      end
    end
  end
  local target = P.x + 16 - 106 + P.vx * 11
  cam = math.max(0, math.min(WORLD_W - W, cam + (target - cam) * 0.17))
  if P.x >= WORLD_W - 65 then
    state, state_time = "won", 0
    score = score + collected * 50
    if not best_time or clock < best_time then
      best_time = clock
      store("best_time", clock)
    end
    sfx("WIN")
  end
end

function _update()
  frame, state_time = frame + 1, state_time + 1
  if state == "title" then
    if btnp("a") or btnp("start") then start_play() end
  elseif state == "play" then
    update_play()
  elseif state_time > 35 and (btnp("a") or btnp("start")) then
    start_play()
  end
end

local function draw_sprites()
  spr_clear()
  local n = 0
  local function put(sh, f, x, y, flags)
    if n < 128 and x > -32 and x < W and y > -32 and y < H then
      spr(n, sh, f, x, y, flags)
      n = n + 1
    end
  end
  if P.dead == 0 and (P.invuln == 0 or frame % 6 < 3) then
    local speed = math.abs(P.vx)
    local f
    if P.loop_t > 0 or (P.ball and P.vy >= 1) then
      f = 7 + (frame // 2) % 4
    elseif not P.ground then
      f = P.vy < 0 and 5 or 6
    elseif speed > 0.3 then
      f = 1 + (frame // math.max(2, 8 - math.floor(speed))) % 4
    else
      f = 0
    end
    put(hero_sh, f, P.x - cam, P.y, prio(0) | (P.face < 0 and FLIP_X or 0))
  end
  for _, e in ipairs(enemies) do
    if e.alive then put(enemy_sh, (frame // 10) % 2, e.x - cam, ground_y(e.x) - 32, prio(1)) end
  end
  for _, f in ipairs(fruits) do
    local x = f.x - 8 - cam
    if not f.taken and x > -16 and x < W then
      put(fruit_sh, (frame // 7) % 4, x, f.y - 8 + math.sin(frame / 9 + f.x) * 2, prio(0))
    end
  end
  for _, s in ipairs(springs) do
    put(spring_sh, s.t > 0 and 1 or 0, s.x - 8 - cam, ground_y(s.x) - 16, prio(0))
  end
  put(goal_sh, (frame // 9) % 4, WORLD_W - 58 - cam, ground_y(WORLD_W - 58) - 32, prio(0))
end

local function draw_world()
  scroll(3, cam * 0.38, 0)
  scroll(1, cam, 0)
  draw_sprites()
end

local function draw_hud()
  rect(0, 0, 480, 34, 0x102445)
  rect(0, 34, 480, 2, 0xFFD45C)
  text("FRUTAS " .. collected, 12, 8, {font = "arcade", color = 0xFFE872, outline = 0x14243D})
  text("PUNTOS " .. score, 170, 8, {font = "arcade", color = 0xFFFFFF, outline = 0x14243D})
  text("VIDAS " .. lives, 367, 8, {font = "arcade", color = 0xFFFFFF, outline = 0x14243D})
  text(string.format("%d:%02d", clock // 3600, (clock // 60) % 60), 467, 44,
       {font = "arcade", align = "right", color = 0xFFFFFF, outline = 0x14243D})
end

function _draw()
  draw_world()
  if state == "title" then
    shade(0, 0, 480, 320)
    rect(32, 58, 416, 209, 0x102445)
    box(32, 58, 416, 209, 0xFFD45C)
    rect(42, 68, 396, 5, 0x2AA4B8)
    text("ARDILLA", 240, 88, {font = "arcade", scale = 2, align = "center", color = 0xFFE872,
                              gradient = 0xFF8A30, outline = 0x512535, shadow = 0x000000})
    text("RELAMPAGO", 240, 122, {font = "arcade", scale = 2, align = "center", color = 0xFFE872,
                                gradient = 0xFF8A30, outline = 0x512535})
    text("COSTA ESMERALDA", 240, 165, {font = "arcade", align = "center", color = 0x78E8DF})
    text("CORRE  SALTA  GIRA", 240, 193, {font = "arcade", align = "center", color = 0xFFFFFF})
    if frame % 60 < 42 then text("PULSA A", 240, 228, {font = "arcade", align = "center", color = 0xFFE872}) end
    if best_time then text(string.format("RECORD %d:%02d", best_time // 3600, best_time // 60 % 60),
                           240, 276, {font = "arcade", align = "center", color = 0xFFFFFF, outline = 0x102445}) end
    return
  end
  draw_hud()
  if state == "won" or state == "over" then
    shade(0, 72, 480, 180)
    rect(40, 90, 400, 139, 0x102445)
    box(40, 90, 400, 139, 0xFFD45C)
    if state == "won" then
      text("META!", 240, 108, {font = "arcade", scale = 3, align = "center", color = 0xFFE872,
                              gradient = 0xFF8A30, outline = 0x512535})
      text("FRUTAS " .. collected .. "   " .. string.format("%d:%02d", clock // 3600, clock // 60 % 60),
           240, 163, {font = "arcade", align = "center", color = 0xFFFFFF})
    else
      text("FIN DE JUEGO", 240, 117, {font = "arcade", scale = 2, align = "center", color = 0xFF7868,
                                    outline = 0x512535})
    end
    if state_time > 35 then text("A: OTRA CARRERA", 240, 198,
                                  {font = "arcade", align = "center", color = 0x78E8DF}) end
  end
end
