-- Veloz: a speed platformer the way a 16-bit console's looked (art.py), Mega Drive and SNES at once:
--   the sea far behind moves at a speed of its own on every line (the Mega Drive's per-line scroll), the hills at
--   half the camera's speed, the level at its own; the sky is a gradient, one colour per line (as a SNES's HDMA did);
--   the pools in the pits are seen through (its colour maths); the level comes in through a mosaic; the title's floor
--   turns in Mode 7. Sprites of 32x32 in 15 colours or fewer.
-- The pangolin: arrows run (it takes a while to get going, and to stop), A jumps rolled into a ball. Rolled up, it
-- breaks the beetles; touched otherwise, it loses its gems, which bounce away and can be caught again; with none, a
-- life. Springs throw it up. Reach the goal.
local LEVEL = require("level")
local TW, TH = #LEVEL[1], #LEVEL
local ACCEL, DECEL, SKID, TOP_SPEED = 0.08, 0.06, 0.3, 4
local GRAVITY, JUMP, SPRING, MAX_FALL = 0.21, -4.6, -7.5, 6

local hero_sh, beetle_sh, gem_sh, spring_sh, goal_sh
P, beetles, gems, flying = {}, {}, {}, {} -- (global: tests/veloz.script)
state, score, lives, carried = "title", 0, 3, 0
cam, springs = 0, {}
local timer, goal_x, goal_y, mosaic_t, clock = 0, 0, 0, 0, 0
local start_x, start_y = 32, 96

local function tile(tx, ty)
  if tx < 0 or tx >= TW then return "#" end
  if ty < 0 or ty >= TH then return "." end
  return LEVEL[ty + 1]:sub(tx + 1, tx + 1)
end
local function wall(x, y) return tile(x // 8, y // 8) == "#" end

local function overlap(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

local function play_layers()
  bg(3, {map = "FAR", prio = 3, mosaic = true})
  bg(2, {map = "HILLS", prio = 2, mosaic = true})
  bg(1, {map = "LEVEL", prio = 1, wrap = false, mosaic = true})
  bg(0, {map = "WATER", prio = 0, wrap = false})
  blend(BG0, BG1 | BG2 | BG3 | OBJ | BACK, 9, 7) -- the pools: seen through
end

local function respawn()
  P = {x = start_x, y = start_y, vx = 0, vy = 0, ground = false, face = 1, ball = false, hurt = 0, dead = 0, t = 0}
  carried, cam, mosaic_t = 0, 0, 16
end

local function reset_level()
  beetles, gems, flying, springs, score, lives = {}, {}, {}, {}, 0, 3
  for ty = 0, TH - 1 do
    for tx = 0, TW - 1 do
      local c = tile(tx, ty)
      if c == "o" then gems[#gems + 1] = {x = tx * 8 - 4, y = ty * 8 - 4}
      elseif c == "e" then beetles[#beetles + 1] = {x = tx * 8 - 8, y = ty * 8 - 16, dir = -1, dead = 0}
      elseif c == "s" then springs[#springs + 1] = {x = tx * 8 - 4, y = ty * 8 + 8 - 16, t = 0}
      elseif c == "P" then start_x, start_y = tx * 8 - 8, ty * 8 - 16
      elseif c == "F" then goal_x, goal_y = tx * 8 - 8, ty * 8 - 16 end
    end
  end
  clock = 0
  respawn()
end

function _init()
  hero_sh, beetle_sh, gem_sh = sheet("HERO"), sheet("BEETLE"), sheet("GEM")
  spring_sh, goal_sh = sheet("SPRING"), sheet("GOAL")
  palette("OBJ", true)
  for y = 0, H - 1 do -- the sky: deep blue high up to pale at the horizon, a colour per line
    local k = math.min(1, y / 92)
    line_backdrop(y, rgb(40 + 140 * k, 90 + 130 * k, 200 + 50 * k))
  end
  bg(0, {map = "ROLL", mode = "affine"}) -- the title's floor
  show(BG0 | OBJ | BACK)
  sound("SFX_JUMP", "jump", 3)
  sound("SFX_GEM", "coin", 9)
  sound("SFX_POP", "explosion", 2)
  sound("SFX_SPRING", {wave = "square", freq = 220, slide = 1800, sustain = 0.1, decay = 0.15, volume = 0.3})
  sound("SFX_LOSE", {wave = "saw", freq = 900, slide = -1500, sustain = 0.1, decay = 0.3, volume = 0.3})
  sound("SFX_WIN", "powerup", 6)
  reset_level()
end

-- ------------------------------------------------------------------ playing

local function hurt()
  if P.hurt > 0 or P.dead > 0 then return end
  if carried > 0 then -- the gems fly off in a fan, and can be caught again for a while
    for i = 1, math.min(carried, 16) do
      local a = math.pi * (0.15 + 0.7 * (i - 1) / 15)
      flying[#flying + 1] = {x = P.x + 12, y = P.y + 8, vx = math.cos(a) * 3 * (i % 2 * 2 - 1), vy = -math.sin(a) * 4,
                             life = 200}
    end
    carried, P.hurt, P.vx, P.vy = 0, 90, -P.face * 2, -3
    sfx("SFX_LOSE")
  else
    P.dead, P.vy, lives = 1, -5, lives - 1
    sfx("SFX_LOSE")
    music()
  end
end

local function move()
  local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
  if dx ~= 0 then
    if P.vx * dx < 0 then P.vx = P.vx + dx * SKID -- turning round: a skid first
    else P.vx = math.max(-TOP_SPEED, math.min(TOP_SPEED, P.vx + dx * ACCEL)) end
    P.face = dx
  elseif P.ground then
    P.vx = P.vx > 0 and math.max(0, P.vx - DECEL) or math.min(0, P.vx + DECEL)
  end
  if btnb("a") and P.ground then P.vy, P.ground, P.ball, P.jumped = JUMP, false, true, true sfx("SFX_JUMP") end
  if not btn("a") and P.vy < -2 and P.jumped then P.vy = -2 end -- a short press, a short jump (not a spring's)
  P.vy = math.min(P.vy + GRAVITY, MAX_FALL)
  P.x = P.x + P.vx -- across: the body is x+8 .. x+23, y+6 .. y+31
  for _, py in ipairs({P.y + 10, P.y + 20, P.y + 28}) do
    if P.vx > 0 and wall(math.floor(P.x + 23), math.floor(py)) then P.x, P.vx = (math.floor(P.x + 23) // 8) * 8 - 24, 0 end
    if P.vx < 0 and wall(math.floor(P.x + 8), math.floor(py)) then P.x, P.vx = (math.floor(P.x + 8) // 8 + 1) * 8 - 8, 0 end
  end
  local old = P.y + 31
  P.y, P.ground = P.y + P.vy, false
  if P.vy >= 0 then
    for _, px in ipairs({P.x + 10, P.x + 21}) do
      local fy = math.floor(P.y + 32)
      local c, top = tile(math.floor(px) // 8, fy // 8), (fy // 8) * 8
      if c == "#" or (c == "=" and old < top) then P.y, P.vy, P.ground, P.ball = top - 32, 0, true, false end
    end
  elseif wall(math.floor(P.x + 16), math.floor(P.y + 6)) then
    P.y, P.vy = (math.floor(P.y + 6) // 8 + 1) * 8 - 6, 0
  end
  P.x = math.max(0, P.x)
end

local function update_play()
  clock = clock + 1
  if P.dead > 0 then
    P.dead, P.vy = P.dead + 1, P.vy + GRAVITY
    P.y = P.y + P.vy
    if P.dead > 100 then if lives > 0 then respawn() else state, timer = "over", 0 end end
    return
  end
  P.t = P.t + 1
  if P.hurt > 0 then P.hurt = P.hurt - 1 end
  move()
  if P.y > TH * 8 then P.dead, P.vy, lives = 1, -5, lives - 1 sfx("SFX_LOSE") return end -- into a pit
  for i = #gems, 1, -1 do
    local g = gems[i]
    if overlap(P.x + 8, P.y + 6, 16, 26, g.x, g.y, 16, 16) then
      table.remove(gems, i)
      carried, score = carried + 1, score + 10
      sfx("SFX_GEM", 0.5)
    end
  end
  for i = #flying, 1, -1 do
    local g = flying[i]
    g.x, g.y, g.vy, g.life = g.x + g.vx, g.y + g.vy, g.vy + 0.18, g.life - 1
    if wall(math.floor(g.x + 8), math.floor(g.y + 15)) and g.vy > 0 then g.vy = -g.vy * 0.75 end
    if g.life < 170 and overlap(P.x + 8, P.y + 6, 16, 26, g.x, g.y, 16, 16) then
      table.remove(flying, i)
      carried = carried + 1
      sfx("SFX_GEM", 0.5)
    elseif g.life <= 0 or g.y > TH * 8 then table.remove(flying, i) end
  end
  for _, s in ipairs(springs) do
    if s.t > 0 then s.t = s.t - 1 end
    if P.vy >= 0 and overlap(P.x + 8, P.y + 24, 16, 8, s.x, s.y, 16, 16) then
      P.vy, P.ground, P.ball, P.jumped, s.t = SPRING, false, true, false, 12
      sfx("SFX_SPRING")
    end
  end
  for _, b in ipairs(beetles) do
    if b.dead > 0 then b.dead = b.dead + 1
    elseif b.x > cam - 40 and b.x < cam + 280 then
      local nx = b.x + b.dir * 0.5
      local ahead = b.dir > 0 and nx + 26 or nx + 6
      if wall(math.floor(ahead), math.floor(b.y + 20)) or not wall(math.floor(ahead), math.floor(b.y + 33)) then
        b.dir = -b.dir
      else b.x = nx end
      if overlap(P.x + 8, P.y + 6, 16, 26, b.x + 6, b.y + 14, 20, 16) then
        if P.ball then -- rolled up: it breaks
          b.dead, P.vy, score = 1, P.vy > 0 and -3.5 or P.vy, score + 100
          sfx("SFX_POP", 0.6)
        else hurt() end
      end
    end
  end
  local target = P.x + 16 - 120 + P.vx * 14 -- the camera looks ahead of the run
  cam = math.max(0, math.min(TW * 8 - W, cam + (target - cam) * 0.15))
  if P.x + 16 >= goal_x + 16 then state, timer = "won", 0 music() sfx("SFX_WIN") score = score + carried * 100 end
end

function _update()
  timer = timer + 1
  if state == "title" then
    if btnp("a") or btnp("start") then
      reset_level()
      play_layers()
      show(ALL)
      state = "play"
    end
  elseif state == "play" then
    update_play()
  elseif (state == "won" or state == "over") and timer > 60 and btnp("a") then
    reset_level()
    state = "play"
  end
  if mosaic_t > 0 then mosaic_t = mosaic_t - 1 end
end

-- ------------------------------------------------------------------ drawing

local function draw_sprites()
  spr_clear()
  local n = 0
  local function put(sh, f, x, y, flags)
    if n < 128 and x > -32 and x < W and y > -32 and y < H then spr(n, sh, f, x, y, flags) n = n + 1 end
  end
  if P.hurt % 6 < 4 then
    local f = P.ball and 4 + (timer // 2) % 4 or (math.abs(P.vx) > 0.3 and (timer // math.max(2, 8 - math.floor(math.abs(P.vx) * 1.5))) % 4 or 0)
    put(hero_sh, f, P.x - cam, P.y, prio(1) | (P.face < 0 and FLIP_X or 0))
  end
  for _, b in ipairs(beetles) do
    if b.dead < 20 then put(beetle_sh, (timer // 8) % 2, b.x - cam, b.y, prio(1) | (b.dir > 0 and FLIP_X or 0) | (b.dead > 0 and MOSAIC or 0)) end
  end
  for _, g in ipairs(gems) do put(gem_sh, (timer // 6) % 4, g.x - cam, g.y, prio(1)) end
  for _, g in ipairs(flying) do if g.life > 40 or g.life % 4 < 2 then put(gem_sh, (timer // 3) % 4, g.x - cam, g.y, prio(1)) end end
  for _, s in ipairs(springs) do put(spring_sh, s.t > 0 and 1 or 0, s.x - cam, s.y, prio(1)) end
  put(goal_sh, state == "won" and (timer // 4) % 4 or 0, goal_x - cam, goal_y, prio(1))
end

function _draw()
  if state == "title" then -- a floor turning under the title, in Mode 7
    mode7(0, 128 + 90 * math.cos(timer / 140), 128 + 90 * math.sin(timer / 140), timer / 2, 40, 60, 160)
    spr_clear()
    spr(0, hero_sh, 4 + (timer // 3) % 4, W // 2 - 16, 70, prio(0))
    text("PANGOLIN", 240, 30, {font = "arcade", scale = 3, align = "center", color = 0xFFF070, gradient = 0xF06010,
                               outline = 0x101040, shadow = 0x000000})
    text("VELOZ", 240, 84, {font = "arcade", scale = 2, align = "center", color = 0x80E0FF, outline = 0x101040})
    if (timer // 30) % 2 == 0 then text("PULSA A", 240, 290, {font = "arcade", align = "center", color = 0xFFFFFF, outline = 0x101040}) end
    return
  end
  scroll(3, cam * 0.15, 0)
  for y = 92, H - 1 do line_scroll(3, y, math.floor(cam * (0.2 + 0.5 * (y - 92) / 68)), 0) end -- the sea, line by line
  scroll(2, cam * 0.5, 0)
  scroll(1, cam, 0)
  scroll(0, cam, 0)
  mosaic(1 + mosaic_t // 2, 1 + mosaic_t // 2)
  draw_sprites()
  local function hud(label, value, y)
    text(label, 16, y, {font = "arcade", color = 0xFFE020, outline = 0x101040})
    text(value, 176, y, {font = "arcade", color = 0xFFFFFF, outline = 0x101040})
  end
  hud("PUNTOS", tostring(score), 10)
  hud("TIEMPO", string.format("%d:%02d", clock // 3600, clock // 60 % 60), 30)
  hud("GEMAS", tostring(carried), 50)
  text("x" .. lives, 464, 10, {font = "arcade", align = "right", color = 0xFFFFFF, outline = 0x101040})
  if state == "won" then
    text("¡META!", 240, 120, {font = "arcade", scale = 3, align = "center", color = 0xFFF070, outline = 0x101040})
  elseif state == "over" then
    text("GAME OVER", 240, 140, {font = "arcade", scale = 3, align = "center", color = 0xFF4040, outline = 0x101040})
  end
end
