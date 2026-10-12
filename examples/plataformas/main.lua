-- Plataformas: a platformer on np2d's virtual hardware (docs/lua.md).
--   BG3 far mountains and BG2 hills scroll slower than the level (parallax);
--   BG1 is the level; BG0 is water, blended over everything behind it, with a wavy scroll per line;
--   the sky is a gradient on the backdrop, one colour per line; the HUD is text at full resolution.

local LEVEL = require("level")
local TW, TH = #LEVEL[1], #LEVEL
local LW = TW * 8

local GRAVITY, JUMP, RUN, ACCEL, FRICTION, MAX_FALL = 0.22, -4.4, 1.7, 0.22, 0.78, 4.2

local hero_sh, slime_sh, coin_sh, flag_sh, spark_sh
P = {}                 -- the hero (global so tests can read it)
state = "title"        -- title, play, dead, won
coins, coins_total = 0, 0
slimes, coin_list = {}, {}  -- global: tests place the hero next to them
local sparks = {}
local flag_x, flag_y = 0, 0
local start_x, start_y = 16, 112
local cam, timer, mosaic_t, play_ticks = 0, 0, 0, 0

local function tile(tx, ty)
  if tx < 0 or tx >= TW then return "#" end -- the level's sides are walls
  if ty < 0 or ty >= TH then return "." end
  return LEVEL[ty + 1]:sub(tx + 1, tx + 1)
end

local function wall(x, y) -- a pixel inside ground or brick
  local c = tile(x // 8, y // 8)
  return c == "#" or c == "B"
end

local function overlap(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

local function respawn()
  P = {x = start_x, y = start_y, vx = 0, vy = 0, ground = false, coyote = 0, face = 1, frame = 0, hurt = 0}
end

local function reset_level()
  slimes, coin_list, sparks = {}, {}, {}
  coins, coins_total = 0, 0
  for ty = 0, TH - 1 do
    for tx = 0, TW - 1 do
      local c = tile(tx, ty)
      if c == "o" then coin_list[#coin_list + 1] = {x = tx * 8, y = ty * 8, got = false}; coins_total = coins_total + 1
      elseif c == "s" then slimes[#slimes + 1] = {x = tx * 8 - 4, y = ty * 8 - 8, dir = -1, dead = 0}
      elseif c == "P" then start_x, start_y = tx * 8, ty * 8
      elseif c == "F" then flag_x, flag_y = tx * 8, ty * 8 end
    end
  end
  respawn()
  play_ticks = 0
end

function _init()
  hero_sh = sheet("HERO"); slime_sh = sheet("SLIME"); coin_sh = sheet("COIN")
  flag_sh = sheet("FLAG"); spark_sh = sheet("SPARK")
  palette("OBJ", true)
  bg(3, {map = "MOUNTAINS", prio = 3, mosaic = true})
  bg(2, {map = "HILLS", prio = 2, mosaic = true})
  bg(1, {map = "LEVEL", prio = 1, wrap = false, mosaic = true})
  bg(0, {map = "WATER", prio = 0, wrap = false})
  blend(BG0, BG1 | BG2 | BG3 | OBJ | BACK, 10, 7) -- see-through water
  for y = 0, H - 1 do -- the sky: deep blue at the top to pale near the horizon
    local k = y / (H - 1)
    line_backdrop(y, rgb(64 + 120 * k, 120 + 100 * k, 220 + 30 * k))
  end
  reset_level()
end

local function move_hero()
  local left, right = btn("left"), btn("right")
  if left and not right then P.vx = math.max(P.vx - ACCEL, -RUN); P.face = -1
  elseif right and not left then P.vx = math.min(P.vx + ACCEL, RUN); P.face = 1
  else P.vx = P.vx * FRICTION; if math.abs(P.vx) < 0.05 then P.vx = 0 end end

  P.coyote = P.ground and 6 or math.max(P.coyote - 1, 0)
  if btnp("a") and P.coyote > 0 then
    P.vy, P.coyote, P.ground = JUMP, 0, false
    sfx("SFX_JUMP", 0.6)
  end
  if not btn("a") and P.vy < -1.6 then P.vy = -1.6 end -- a short press, a short jump
  P.vy = math.min(P.vy + GRAVITY, MAX_FALL)

  -- across: the body is x+3 .. x+12, y+2 .. y+15
  P.x = P.x + P.vx
  for _, py in ipairs({P.y + 3, P.y + 9, P.y + 15}) do
    if P.vx > 0 and wall(math.floor(P.x + 12), math.floor(py)) then P.x = (math.floor(P.x + 12) // 8) * 8 - 13; P.vx = 0 end
    if P.vx < 0 and wall(math.floor(P.x + 3), math.floor(py)) then P.x = (math.floor(P.x + 3) // 8 + 1) * 8 - 3; P.vx = 0 end
  end

  -- down and up; platforms (=) only hold from above
  local old_bottom = P.y + 15
  P.y = P.y + P.vy
  P.ground = false
  if P.vy >= 0 then
    for _, px in ipairs({P.x + 4, P.x + 11}) do
      local fy = math.floor(P.y + 16)
      local c = tile(math.floor(px) // 8, fy // 8)
      local top = (fy // 8) * 8
      if c == "#" or c == "B" or (c == "=" and old_bottom < top) then
        P.y, P.vy, P.ground = top - 16, 0, true
      end
    end
  else
    for _, px in ipairs({P.x + 4, P.x + 11}) do
      if wall(math.floor(px), math.floor(P.y + 2)) then P.y = (math.floor(P.y + 2) // 8 + 1) * 8 - 2; P.vy = 0 end
    end
  end
  if P.x < 0 then P.x = 0 end
end

local function hurt()
  state, timer = "dead", 0
  P.hurt = 1
  sfx("SFX_HURT")
end

local function update_play()
  play_ticks = play_ticks + 1
  move_hero()
  if P.y > H then hurt() return end -- into the water
  if tile(math.floor(P.x + 8) // 8, math.floor(P.y + 14) // 8) == "~" then hurt() return end

  for _, c in ipairs(coin_list) do
    if not c.got and overlap(P.x + 3, P.y + 2, 10, 14, c.x, c.y, 8, 8) then
      c.got = true
      coins = coins + 1
      sparks[#sparks + 1] = {x = c.x, y = c.y, t = 12}
      sfx("SFX_COIN", 0.7)
    end
  end

  for _, s in ipairs(slimes) do
    if s.dead > 0 then
      s.dead = s.dead + 1
    else
      local nx = s.x + s.dir * 0.4
      local ahead = s.dir > 0 and nx + 14 or nx + 1
      if wall(math.floor(ahead), math.floor(s.y + 8)) or not (wall(math.floor(ahead), math.floor(s.y + 17)) or tile(math.floor(ahead) // 8, math.floor(s.y + 17) // 8) == "=") then
        s.dir = -s.dir
      else
        s.x = nx
      end
      if overlap(P.x + 3, P.y + 2, 10, 14, s.x + 2, s.y + 6, 12, 10) then
        if P.vy > 0 and P.y + 12 < s.y + 10 then -- from above: squashed
          s.dead = 1
          P.vy = -3
          sfx("SFX_STOMP")
        else
          hurt()
          return
        end
      end
    end
  end

  if P.x + 8 >= flag_x and P.x <= flag_x + 12 then
    state, timer = "won", 0
    music()
    sfx("SFX_WIN")
    local best = stored("best_ticks")
    if not best or play_ticks < best then store("best_ticks", play_ticks) end
  end
end

function _update()
  timer = timer + 1
  if state == "title" then
    if btnp("a") then state, mosaic_t = "play", 16; music("MUS_LEVEL") end
  elseif state == "play" then
    update_play()
  elseif state == "dead" then
    if timer > 50 then respawn(); state, mosaic_t = "play", 16 end
  elseif state == "won" then
    if timer > 60 and btnp("a") then reset_level(); state, mosaic_t = "play", 16; music("MUS_LEVEL") end
  end
  if mosaic_t > 0 then mosaic_t = mosaic_t - 1 end
  for i = #sparks, 1, -1 do
    sparks[i].t = sparks[i].t - 1
    if sparks[i].t <= 0 then table.remove(sparks, i) end
  end
end

local function draw_sprites()
  spr_clear()
  local n = 0
  local pose = 0
  if state == "dead" then pose = 5
  elseif not P.ground then pose = P.vy < 0 and 3 or 4
  elseif math.abs(P.vx) > 0.2 then pose = 1 + (ticks() // 6) % 2 end
  spr(n, hero_sh, pose, P.x - cam, P.y, prio(1) | (P.face < 0 and FLIP_X or 0) | MOSAIC); n = n + 1
  for _, s in ipairs(slimes) do
    if s.dead < 40 and s.x - cam > -16 and s.x - cam < W then
      spr(n, slime_sh, s.dead > 0 and 2 or (ticks() // 15) % 2, s.x - cam, s.y, prio(1) | (s.dir > 0 and FLIP_X or 0)); n = n + 1
    end
  end
  for _, c in ipairs(coin_list) do
    if not c.got and c.x - cam > -8 and c.x - cam < W then
      spr(n, coin_sh, (ticks() // 8) % 4, c.x - cam, c.y, prio(1)); n = n + 1
    end
  end
  for _, sp in ipairs(sparks) do
    spr(n, spark_sh, 0, sp.x - cam, sp.y - (12 - sp.t), prio(1) | BLEND); n = n + 1
  end
  spr(n, flag_sh, (ticks() // 20) % 2, flag_x - cam, flag_y, prio(1))
end

function _draw()
  local target = P.x - 112
  cam = math.max(0, math.min(LW - W, target))
  scroll(3, cam * 0.25, 0)
  scroll(2, cam * 0.5, 0)
  scroll(1, cam, 0)
  scroll(0, cam, 0)
  for y = 140, H - 1 do -- the water's surface sways, line by line
    line_scroll(0, y, math.floor(cam + 2 * math.sin(ticks() / 12 + y / 3)), 0)
  end
  mosaic(1 + mosaic_t // 2, 1 + mosaic_t // 2)
  draw_sprites()

  -- the HUD, at the screen's full resolution, in its own look: sporty letters (fonts/marcador.fnt, titol.fnt) and
  -- brick blocks (FR_BLOQUE), made by art.py
  local hud = "MONEDAS " .. coins .. "/" .. coins_total
  text(hud, 14, 6, {font = "marcador", color = 0xFFFFFF, outline = 0x3A2A1E})
  if state == "title" then
    shade(0, 0, SCREEN_W, SCREEN_H)
    frame("FR_BLOQUE", 60, 84, 360, 140, 2)
    text("PLATAFORMAS", SCREEN_W // 2, 98, {font = "titol", align = "center", color = 0xFFE070, gradient = 0xFF8A20,
                                            outline = 0x5A2A10, shadow = 0x000000})
    text("Corre, salta, pisa a los limos", SCREEN_W // 2, 146, 0x5A3A20, "main", "center")
    text("PULSA A", SCREEN_W // 2, 176, {font = "marcador", align = "center", color = 0xC04030, wave = 2})
    local best = stored("best_ticks")
    if best then text(string.format("Mejor tiempo: %.1f s", best / 60), SCREEN_W // 2, 240, 0xFFFFFF, "main", "center") end
  elseif state == "won" then
    frame("FR_BLOQUE", 60, 94, 360, 124, 2)
    text("¡NIVEL COMPLETADO!", SCREEN_W // 2, 108, {font = "titol", align = "center", color = 0xFFE070,
                                                   gradient = 0xFF8A20, outline = 0x5A2A10})
    text(string.format("%d monedas en %.1f s", coins, play_ticks / 60), SCREEN_W // 2, 152, 0x5A3A20, "main", "center")
    if timer > 60 then text("A: otra vez", SCREEN_W // 2, 180, 0xC04030, "marcador", "center") end
    fade("light", BG1 | BG2 | BG3 | BACK, math.min(timer // 4, 8))
  else
    blend(BG0, BG1 | BG2 | BG3 | OBJ | BACK, 10, 7)
  end
end
