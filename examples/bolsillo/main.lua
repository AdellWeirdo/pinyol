-- Bolsillo: a platformer the way a Game Boy game looks (art.py), on the whole screen as a modern Game Boy would show
-- it: four tones, one background layer of 8x8 tiles, 16x16 sprites, a status bar across the top, two square voices
-- and a noise for sound. C changes the four tones, as a Game Boy Color let you pick the colours of an old game; the
-- choice is kept.
-- Bolet the mushroom: arrows walk, A jumps (a short press, a short jump); stomp the hedgehogs, mind the spikes.
local LEVEL = require("level")
local TW, TH = #LEVEL[1], #LEVEL
local VX, VY, VW, VH = 0, 16, 240, 144 -- the level, under the status bar (16 tall)
local GRAVITY, JUMP, RUN, ACCEL, FRICTION, MAX_FALL = 0.22, -4.2, 1.5, 0.2, 0.75, 4
PALETTES = { -- (global: tests/bolsillo.script) lightest to darkest
  {name = "DMG", 0x9BBC0F, 0x8BAC0F, 0x306230, 0x0F380F},
  {name = "POCKET", 0xE8E8E0, 0xA8A8A0, 0x585850, 0x181810},
  {name = "MARRON", 0xFFF8E0, 0xF0A860, 0x844018, 0x200800},
  {name = "AZUL", 0xF0F8FF, 0x70A8F8, 0x2040C0, 0x000818},
  {name = "SGB", 0xF8E8C8, 0xD89048, 0xA82820, 0x301850},
}

local hero_sh, hog_sh, coin_sh, flag_sh
P, hogs, coin_list = {}, {}, {} -- (global: the test reads and moves them)
state, coins, lives, tones, cam = "title", 0, 3, 1, 0
local timer, clock, shown_pal, beat = 0, 0, 0, 0
local start_x, start_y, flag_x, flag_y = 24, 104, 0, 0

local function tile(tx, ty)
  if tx < 0 or tx >= TW then return "#" end
  if ty < 0 or ty >= TH then return "." end
  return LEVEL[ty + 1]:sub(tx + 1, tx + 1)
end

local function solid(c) return c == "#" or c == "B" or c == "?" end
local function wall(x, y) return solid(tile(x // 8, y // 8)) end

local function overlap(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

local function use_tones(k) -- the four colours of the background and of the sprites, and the backdrop
  tones = (k - 1) % #PALETTES + 1
  local p = PALETTES[tones]
  for i = 1, 4 do pal(i, p[i]) pal(i, p[i], true) end
  backdrop(p[1])
end

local function respawn()
  P = {x = start_x, y = start_y, vx = 0, vy = 0, ground = false, coyote = 0, face = 1, dead = 0}
  cam = 0
end

local function reset_level()
  hogs, coin_list, coins, lives = {}, {}, 0, 3
  for ty = 0, TH - 1 do
    for tx = 0, TW - 1 do
      local c = tile(tx, ty)
      if c == "o" then coin_list[#coin_list + 1] = {x = tx * 8, y = ty * 8, got = false}
      elseif c == "e" then hogs[#hogs + 1] = {x = tx * 8 - 4, y = ty * 8 - 8, dir = -1, dead = 0}
      elseif c == "P" then start_x, start_y = tx * 8, ty * 8 - 8
      elseif c == "F" then flag_x, flag_y = tx * 8 - 4, ty * 8 end
    end
  end
  respawn()
  clock = 300 * 60
end

function _init()
  hero_sh, hog_sh, coin_sh, flag_sh = sheet("HERO"), sheet("HEDGEHOG"), sheet("COIN"), sheet("FLAG")
  bg(1, {map = "LEVEL", prio = 1, wrap = false})
  palette("OBJ", true)
  use_tones(stored("tones") or 1)
  sound("SFX_JUMP", {wave = "square", freq = 330, slide = 2400, sustain = 0.05, decay = 0.08, volume = 0.3})
  sound("SFX_COIN", {wave = "square", freq = 988, sustain = 0.04, decay = 0.12, arp = 1.33, arp_time = 0.05, volume = 0.3})
  sound("SFX_STOMP", {wave = "noise", freq = 400, slide = -1200, sustain = 0.02, decay = 0.1, volume = 0.35})
  sound("SFX_HURT", {wave = "square", freq = 600, slide = -900, sustain = 0.2, decay = 0.3, volume = 0.3})
  sound("SFX_WIN", "powerup", 4)
  reset_level()
end

-- ------------------------------------------------------------------ playing

local function move_hero()
  local left, right = btn("left"), btn("right")
  if left and not right then P.vx, P.face = math.max(P.vx - ACCEL, -RUN), -1
  elseif right and not left then P.vx, P.face = math.min(P.vx + ACCEL, RUN), 1
  else P.vx = P.vx * FRICTION if math.abs(P.vx) < 0.05 then P.vx = 0 end end
  P.coyote = P.ground and 6 or math.max(P.coyote - 1, 0)
  if btnb("a") and P.coyote > 0 then P.vy, P.coyote, P.ground = JUMP, 0, false sfx("SFX_JUMP") end
  if not btn("a") and P.vy < -1.6 then P.vy = -1.6 end -- a short press, a short jump
  P.vy = math.min(P.vy + GRAVITY, MAX_FALL)
  P.x = P.x + P.vx -- across: the body is x+3 .. x+12, y+2 .. y+15
  for _, py in ipairs({P.y + 3, P.y + 9, P.y + 15}) do
    if P.vx > 0 and wall(math.floor(P.x + 12), math.floor(py)) then P.x, P.vx = (math.floor(P.x + 12) // 8) * 8 - 13, 0 end
    if P.vx < 0 and wall(math.floor(P.x + 3), math.floor(py)) then P.x, P.vx = (math.floor(P.x + 3) // 8 + 1) * 8 - 3, 0 end
  end
  local old_bottom = P.y + 15
  P.y, P.ground = P.y + P.vy, false
  if P.vy >= 0 then -- down; platforms (=) only hold from above
    for _, px in ipairs({P.x + 4, P.x + 11}) do
      local fy = math.floor(P.y + 16)
      local c, top = tile(math.floor(px) // 8, fy // 8), (fy // 8) * 8
      if solid(c) or (c == "=" and old_bottom < top) then P.y, P.vy, P.ground = top - 16, 0, true end
    end
  else
    for _, px in ipairs({P.x + 4, P.x + 11}) do
      if wall(math.floor(px), math.floor(P.y + 2)) then P.y, P.vy = (math.floor(P.y + 2) // 8 + 1) * 8 - 2, 0 end
    end
  end
  P.x = math.max(cam, P.x)
end

local function hurt()
  if P.dead > 0 then return end
  P.dead, P.vy = 1, -3.5
  lives = lives - 1
  sfx("SFX_HURT")
  music() -- the tune stops, as it did
end

local function update_play()
  if P.dead > 0 then -- up, then down off the screen
    P.dead, P.vy = P.dead + 1, P.vy + GRAVITY
    P.y = P.y + P.vy
    if P.dead > 90 then
      if lives > 0 then respawn() else state, timer = "over", 0 end
    end
    return
  end
  move_hero()
  clock = clock - 1
  if P.y > TH * 8 or clock <= 0 then hurt() return end
  if tile(math.floor(P.x + 8) // 8, math.floor(P.y + 14) // 8) == "^" then hurt() return end
  for _, c in ipairs(coin_list) do
    if not c.got and overlap(P.x + 3, P.y + 2, 10, 14, c.x, c.y, 8, 8) then
      c.got, coins = true, coins + 1
      sfx("SFX_COIN")
    end
  end
  for _, h in ipairs(hogs) do
    if h.dead > 0 then h.dead = h.dead + 1
    elseif h.x > cam - 32 and h.x < cam + VW + 32 then
      local nx = h.x + h.dir * 0.4
      local ahead = h.dir > 0 and nx + 14 or nx + 1
      if wall(math.floor(ahead), math.floor(h.y + 8)) or not wall(math.floor(ahead), math.floor(h.y + 17)) then
        h.dir = -h.dir
      else h.x = nx end
      if overlap(P.x + 3, P.y + 2, 10, 14, h.x + 2, h.y + 6, 12, 10) then
        if P.vy > 0 and P.y + 12 < h.y + 10 then h.dead, P.vy = 1, -3 sfx("SFX_STOMP") -- from above: squashed
        else hurt() return end
      end
    end
  end
  cam = math.floor(math.max(cam, math.min(TW * 8 - VW, P.x - VW * 2 // 5))) -- it only goes forward, as it did
  if P.x + 8 >= flag_x then state, timer = "won", 0 music() sfx("SFX_WIN") end
end

-- two square voices and a noise: the tune, a note every 10 ticks (0 is a rest)
local TUNE = {"E5", "G5", "E6", "C6", "D6", "G6", 0, "G5", "E5", "G5", "C6", "A5", "B5", "G5", 0, 0}
local BASS = {"C3", "C3", "G3", "G3", "A2", "A2", "E3", "E3", "F2", "F2", "C3", "C3", "G2", "G2", "G2", "B2"}
local function music_tick()
  if state ~= "play" or P.dead > 0 then return end
  beat = beat + 1
  if beat % 10 ~= 0 then return end
  local i = (beat // 10) % #TUNE + 1
  if TUNE[i] ~= 0 then tone(0, TUNE[i], {wave = "square", duty = 0.25, decay = 0.12, volume = 0.18}) end
  if i % 2 == 1 then tone(1, BASS[(i + 1) // 2], {wave = "square", duty = 0.5, decay = 0.2, volume = 0.16}) end
  if i % 4 == 1 then tone(3, 2000, {wave = "noise", decay = 0.04, volume = 0.12}) end
end

function _update()
  timer = timer + 1
  if shown_pal > 0 then shown_pal = shown_pal - 1 end
  if btnp("c") then use_tones(tones + 1) store("tones", tones) shown_pal = 90 end
  if state == "title" then
    if btnp("a") or btnp("start") then reset_level() state, beat = "play", 0 end
  elseif state == "play" then
    update_play()
    music_tick()
  elseif (state == "won" or state == "over") and timer > 60 and btnp("a") then
    state = "title"
  end
end

-- ------------------------------------------------------------------ drawing

local function draw_sprites()
  spr_clear()
  local n, pose = 0, 0
  if P.dead > 0 then pose = 4
  elseif not P.ground then pose = 3
  elseif math.abs(P.vx) > 0.2 then pose = 1 + (timer // 8) % 2 end
  if state ~= "title" then
    spr(n, hero_sh, pose, VX + P.x - cam, VY + P.y, prio(0) | (P.face < 0 and FLIP_X or 0)) n = n + 1
  end
  for _, h in ipairs(hogs) do
    if h.dead < 30 and h.x - cam > -16 and h.x - cam < VW then
      spr(n, hog_sh, h.dead > 0 and 2 or (timer // 12) % 2, VX + h.x - cam, VY + h.y, prio(1) | (h.dir > 0 and FLIP_X or 0))
      n = n + 1
    end
  end
  for _, c in ipairs(coin_list) do
    if not c.got and c.x - cam > -8 and c.x - cam < VW then
      spr(n, coin_sh, (timer // 8) % 4, VX + c.x - cam, VY + c.y, prio(1)) n = n + 1
    end
  end
  spr(n, flag_sh, (timer // 20) % 2, VX + flag_x - cam, VY + flag_y, prio(1))
end

local function say(s, y, big) -- text in the darkest tone, centred on the screen (screen pixels)
  text(s, 240, y, {font = "arcade", align = "center", color = PALETTES[tones][4], scale = big and 2 or 1})
end

function _draw()
  scroll(1, cam - VX, -VY)
  draw_sprites()
  local p = PALETTES[tones]
  rect(0, 0, 480, 30, p[1]) -- the status bar, across the top
  rect(0, 30, 480, 2, p[4])
  text(string.format("x%d  o%02d", lives, coins), 14, 8, {font = "arcade", color = p[4]})
  text(string.format("%03d", math.max(0, clock // 60)), 466, 8, {font = "arcade", color = p[4], align = "right"})
  if state == "title" then
    rect(96, 64, 288, 144, p[1])
    box(96, 64, 288, 144, p[4])
    say("BOLSILLO", 84, true)
    say("PULSA A", 136)
    say("C: COLORES", 168)
  elseif state == "won" then
    say("¡META!", 120, true)
    say(coins .. " MONEDAS", 172)
  elseif state == "over" then
    say("GAME OVER", 136, true)
  end
  if shown_pal > 0 then say(p.name, 272) end
end
