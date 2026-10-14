-- Ratón de biblioteca: aventura de plataformas en los cuatro tonos de la Game Boy, a pantalla completa (una Game Boy
-- moderna): el mundo de 240x160 entero, una barra de marcador arriba y la biblioteca debajo.
local LEVEL = require("level")
local TW, TH = #LEVEL[1], #LEVEL
local VX, VY, VW, VH = 0, 16, 240, 144 -- la biblioteca, bajo la barra de marcador (16 de alto)
local GRAVITY, JUMP, RUN, ACCEL, FRICTION = 0.23, -5.2, 1.65, 0.22, 0.72
local LIGHT, MID, DARK, INK = 0x9BBC0F, 0x8BAC0F, 0x306230, 0x0F380F
local mouse_sh, cat_sh, cheese_sh, door_sh
P, cats, cheese_list = {}, {}, {}
state, lives, cheese, cheese_total, cam, exit_x = "title", 3, 0, 0, 0, 0
local timer, beat = 0, 0
local start_x, start_y = 16, 112

local function tile(tx, ty)
  if tx < 0 or tx >= TW then return "#" end
  if ty < 0 or ty >= TH then return "." end
  return LEVEL[ty + 1]:sub(tx + 1, tx + 1)
end

local function support(x, y)
  local c = tile(math.floor(x) // 8, math.floor(y) // 8)
  return c == "=" or c == "#"
end

local function overlap(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and bx < ax + aw and ay < by + bh
end

local function respawn()
  P = {x = start_x, y = start_y, vx = 0, vy = 0, ground = false, coyote = 0,
       face = 1, invuln = 85}
  cam = math.max(0, math.min(TW * 8 - VW, start_x - (VW // 2 - 8)))
end

local function reset_game()
  cats, cheese_list, cheese, cheese_total, lives = {}, {}, 0, 0, 3
  for ty = 0, TH - 1 do
    for tx = 0, TW - 1 do
      local c = tile(tx, ty)
      if c == "o" then
        cheese_list[#cheese_list + 1] = {x = tx * 8, y = ty * 8, got = false}
        cheese_total = cheese_total + 1
      elseif c == "c" then
        cats[#cats + 1] = {x = tx * 8 - 4, y = ty * 8 - 8, dir = -1, sleepy = 0}
      elseif c == "P" then start_x, start_y = tx * 8, ty * 8
      elseif c == "E" then exit_x = tx * 8 end
    end
  end
  respawn()
end

function _init()
  mouse_sh, cat_sh = sheet("MOUSE"), sheet("CAT")
  cheese_sh, door_sh = sheet("CHEESE"), sheet("DOOR")
  bg(1, {map = "LIBRARY", prio = 1, wrap = false})
  palette("OBJ", true)
  backdrop(LIGHT)
  sound("JUMP", {wave = "square", freq = 390, slide = 1400, sustain = 0.02, decay = 0.12, volume = 0.25})
  sound("PICK", {wave = "square", freq = 880, sustain = 0.03, decay = 0.12, arp = 1.5, arp_time = 0.04, volume = 0.3})
  sound("HURT", {wave = "noise", freq = 300, slide = -850, sustain = 0.04, decay = 0.18, volume = 0.35})
  sound("STOMP", {wave = "noise", freq = 500, decay = 0.10, volume = 0.25})
  sound("WIN", "powerup", 4)
  reset_game()
end

local function move_mouse()
  local left, right = btn("left"), btn("right")
  if left and not right then
    P.vx, P.face = math.max(P.vx - ACCEL, -RUN), -1
  elseif right and not left then
    P.vx, P.face = math.min(P.vx + ACCEL, RUN), 1
  else
    P.vx = P.vx * FRICTION
    if math.abs(P.vx) < 0.05 then P.vx = 0 end
  end
  P.coyote = P.ground and 6 or math.max(0, P.coyote - 1)
  if btnb("a") and P.coyote > 0 then
    P.vy, P.ground, P.coyote = JUMP, false, 0
    sfx("JUMP")
  end
  if not btn("a") and P.vy < -2.2 then P.vy = -2.2 end
  P.vy = math.min(P.vy + GRAVITY, 4.5)
  P.x = math.max(0, math.min(TW * 8 - 16, P.x + P.vx))
  local old_bottom = P.y + 16
  P.y, P.ground = P.y + P.vy, false
  if P.vy >= 0 then
    local bottom = P.y + 16
    for _, px in ipairs({P.x + 3, P.x + 12}) do
      local top = (math.floor(bottom) // 8) * 8
      if old_bottom <= top and support(px, bottom) then
        P.y, P.vy, P.ground = top - 16, 0, true
        break
      end
    end
  end
  if P.y > TH * 8 then respawn() end
end

local function hurt(cat)
  if P.invuln > 0 then return end
  lives = lives - 1
  sfx("HURT")
  if lives <= 0 then state, timer = "over", 0 return end
  P.invuln, P.vy, P.vx = 90, -3.5, cat.dir * -2
end

local function update_cats()
  for _, cat in ipairs(cats) do
    if cat.sleepy > 0 then
      cat.sleepy = cat.sleepy - 1
    else
      local nx = cat.x + cat.dir * 0.45
      local ahead = cat.dir > 0 and nx + 14 or nx + 2
      if not support(ahead, cat.y + 17) then cat.dir = -cat.dir else cat.x = nx end
      if overlap(P.x + 3, P.y + 3, 10, 13, cat.x + 2, cat.y + 6, 12, 10) then
        if P.vy > 0.5 and P.y + 13 < cat.y + 10 then
          cat.sleepy, P.vy = 150, -3.4
          sfx("STOMP")
        else
          hurt(cat)
        end
      end
    end
  end
end

local function update_play()
  if P.invuln > 0 then P.invuln = P.invuln - 1 end
  move_mouse()
  for _, piece in ipairs(cheese_list) do
    if not piece.got and overlap(P.x + 3, P.y + 2, 10, 14, piece.x, piece.y, 8, 8) then
      piece.got, cheese = true, cheese + 1
      sfx("PICK")
    end
  end
  update_cats()
  if cheese == cheese_total and overlap(P.x + 2, P.y, 12, 16, exit_x, 112, 16, 16) then
    state, timer = "won", 0
    sfx("WIN")
  end
  cam = math.max(0, math.min(TW * 8 - VW, P.x - (VW // 2 - 8)))
end

local MELODY = {"E5", "G5", "B5", 0, "A5", "G5", "E5", 0,
                "D5", "E5", "G5", 0, "E5", "D5", "C5", 0}
local function music_tick()
  beat = beat + 1
  if beat % 12 ~= 0 then return end
  local i = (beat // 12 - 1) % #MELODY + 1
  if MELODY[i] ~= 0 then
    tone(0, MELODY[i], {wave = "square", duty = 0.25, decay = 0.13, volume = 0.12})
  end
  if i % 4 == 1 then tone(1, "C3", {wave = "square", decay = 0.20, volume = 0.10}) end
end

function _update()
  timer = timer + 1
  if state == "title" then
    if btnp("a") or btnp("start") then reset_game() state, beat = "play", 0 end
  elseif state == "play" then
    update_play()
    if state == "play" then music_tick() end
  elseif (state == "won" or state == "over") and timer > 35 and (btnp("a") or btnp("start")) then
    reset_game()
    state, beat = "play", 0
  end
end

local function draw_world()
  spr_clear()
  local n = 0
  local pose = 0
  if not P.ground then pose = 3
  elseif math.abs(P.vx) > 0.2 then pose = 1 + (timer // 7) % 2 end
  if state ~= "title" and (P.invuln == 0 or timer % 6 < 3) then
    spr(n, mouse_sh, pose, VX + P.x - cam, VY + P.y, prio(0) | (P.face < 0 and FLIP_X or 0))
    n = n + 1
  end
  for _, cat in ipairs(cats) do
    if cat.x - cam > -16 and cat.x - cam < VW then
      spr(n, cat_sh, cat.sleepy > 0 and 2 or (timer // 15) % 2,
          VX + cat.x - cam, VY + cat.y, prio(0) | (cat.dir > 0 and FLIP_X or 0))
      n = n + 1
    end
  end
  for _, piece in ipairs(cheese_list) do
    if not piece.got and piece.x - cam > -8 and piece.x - cam < VW then
      spr(n, cheese_sh, (timer // 12) % 2, VX + piece.x - cam, VY + piece.y, prio(0))
      n = n + 1
    end
  end
  spr(n, door_sh, cheese == cheese_total and 1 or 0, VX + exit_x - cam, VY + 112, prio(1))
end

local function center(s, y, scale)
  text(s, 240, y, {font = "arcade", align = "center", color = INK, scale = scale or 1})
end

function _draw()
  scroll(1, cam - VX, -VY)
  draw_world()
  rect(0, 0, 480, 30, LIGHT)
  rect(0, 30, 480, 2, INK)
  text(string.format("QUESOS %02d/%02d", cheese, cheese_total), 14, 8, {font = "arcade", color = INK})
  text("VIDAS " .. lives, 466, 8, {font = "arcade", color = INK, align = "right"})
  if state == "title" then
    rect(96, 76, 288, 176, LIGHT)
    box(96, 76, 288, 176, INK)
    center("RATON DE", 96)
    center("BIBLIOTECA", 120)
    center("A: SALTAR", 160)
    center("COGE 11 QUESOS", 182)
    if (timer // 30) % 2 == 0 then center("PULSA A", 218) end
  elseif state == "won" then
    rect(108, 102, 264, 105, LIGHT)
    box(108, 102, 264, 105, INK)
    center("¡BIBLIOTECA", 120)
    center("CONQUISTADA!", 141)
    center("A: OTRA VEZ", 181)
  elseif state == "over" then
    rect(108, 115, 264, 92, LIGHT)
    box(108, 115, 264, 92, INK)
    center("LOS GATOS GANAN", 133)
    center("A: REINTENTAR", 177)
  elseif cheese == cheese_total then
    center("¡SAL POR LA PUERTA!", 274)
  end
end
