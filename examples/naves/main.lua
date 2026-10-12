-- Naves: a horizontal shoot-'em-up on np2d's virtual hardware (docs/lua.md).
--   BG3 is a field of stars on one layer: every line scrolls at its own speed (parallax by line);
--   BG2 is a ringed planet on an affine layer, turning slowly;
--   sprites for the ship, shots, enemies, their bullets, power-ups, and explosions blended over everything;
--   the bomb flashes the screen white with a fade.

local SHOT_EVERY, SPEED = 7, 1.7
local ship_sh, saucer_sh, mine_sh, shots_sh, boom_sh, power_sh

state = "title"        -- title, play, over
score, lives, bombs, power = 0, 3, 3, 1
hiscore = 0
ship = {}
shots, enemies, ebullets, booms, powerups = {}, {}, {}, {}, {}
local star_x, star_speed = {}, {}
local timer, wave_t, wave_n, cooldown, flash, spin = 0, 0, 0, 0, 0, 0

local function hit(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

local function explode(x, y)
  booms[#booms + 1] = {x = x, y = y, t = 0}
  sfx("SFX_BOOM", 0.6)
end

local function new_game()
  score, lives, bombs, power = 0, 3, 3, 1
  ship = {x = 24, y = 72, inv = 90, tilt = 0}
  shots, enemies, ebullets, booms, powerups = {}, {}, {}, {}, {}
  wave_t, wave_n, cooldown = 0, 0, 0
end

function _init()
  ship_sh = sheet("SHIP"); saucer_sh = sheet("SAUCER"); mine_sh = sheet("MINE")
  shots_sh = sheet("SHOTS"); boom_sh = sheet("BOOM"); power_sh = sheet("POWER")
  palette("OBJ", true)
  bg(3, {map = "STARS", prio = 3})
  bg(2, {map = "PLANET", mode = "affine", prio = 2, wrap = false})
  backdrop(rgb(8, 6, 24))
  for y = 0, H - 1 do
    star_x[y] = 0
    star_speed[y] = 0.25 + ((y * 37) % 7) * 0.22 -- each line its own speed: near stars streak, far ones crawl
  end
  hiscore = stored("hiscore", 0)
  new_game()
end

local function spawn_wave()
  wave_n = wave_n + 1
  local kind = wave_n % 3
  local base = 20 + math.random(0, 100)
  for i = 0, 4 do
    if kind == 0 then -- a line of saucers on a sine
      enemies[#enemies + 1] = {kind = "saucer", x = W + i * 20, y = base, base = base, t = i * 12, hp = 1}
    elseif kind == 1 then -- mines drifting in a column
      enemies[#enemies + 1] = {kind = "mine", x = W + i * 6, y = 16 + i * 28, base = 0, t = 0, hp = 3}
    else -- saucers diving at the ship
      enemies[#enemies + 1] = {kind = "diver", x = W + i * 16, y = 10 + i * 30, base = 0, t = 0, hp = 1}
    end
  end
end

local function fire()
  sfx("SFX_SHOT", 0.4)
  shots[#shots + 1] = {x = ship.x + 12, y = ship.y + 4, vy = 0}
  if power >= 2 then shots[#shots + 1] = {x = ship.x + 8, y = ship.y + 4, vy = -0.6} end
  if power >= 3 then shots[#shots + 1] = {x = ship.x + 8, y = ship.y + 4, vy = 0.6} end
end

local function bomb()
  bombs = bombs - 1
  flash = 16
  sfx("SFX_BOMB")
  for _, e in ipairs(enemies) do explode(e.x, e.y); score = score + 50 end
  enemies, ebullets = {}, {}
end

local function ship_hit()
  explode(ship.x, ship.y)
  sfx("SFX_HIT")
  lives = lives - 1
  power = 1
  if lives <= 0 then
    state, timer = "over", 0
    if score > hiscore then hiscore = score; store("hiscore", score) end
  else
    ship.inv = 120
  end
end

local function update_play()
  -- the ship
  local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
  local dy = (btn("down") and 1 or 0) - (btn("up") and 1 or 0)
  ship.x = math.max(0, math.min(W - 16, ship.x + dx * SPEED))
  ship.y = math.max(0, math.min(H - 16, ship.y + dy * SPEED))
  ship.tilt = dy
  cooldown = math.max(cooldown - 1, 0)
  if btn("a") and cooldown == 0 then fire(); cooldown = SHOT_EVERY end
  if btnp("c") and bombs > 0 then bomb() end
  if ship.inv > 0 then ship.inv = ship.inv - 1 end

  -- waves
  wave_t = wave_t + 1
  if wave_t > math.max(70, 160 - wave_n * 6) then wave_t = 0; spawn_wave() end

  for i = #shots, 1, -1 do
    local s = shots[i]
    s.x, s.y = s.x + 5, s.y + s.vy
    if s.x > W then table.remove(shots, i) end
  end

  for i = #enemies, 1, -1 do
    local e = enemies[i]
    e.t = e.t + 1
    if e.kind == "saucer" then
      e.x = e.x - 1.1
      e.y = e.base + math.sin(e.t / 14) * 22
      if e.t % 90 == 45 then -- a shot aimed at the ship
        local ang = math.atan(ship.y - e.y, ship.x - e.x)
        ebullets[#ebullets + 1] = {x = e.x, y = e.y + 4, vx = math.cos(ang) * 1.4, vy = math.sin(ang) * 1.4}
      end
    elseif e.kind == "mine" then
      e.x = e.x - 0.6
    else -- diver
      e.x = e.x - 1.6
      if e.x < 170 then e.y = e.y + (ship.y > e.y and 0.7 or -0.7) end
    end
    local dead = false
    for j = #shots, 1, -1 do
      local s = shots[j]
      if hit(s.x, s.y + 2, 8, 4, e.x + 2, e.y + 2, 12, 12) then
        table.remove(shots, j)
        e.hp = e.hp - 1
        if e.hp <= 0 then dead = true; break end
      end
    end
    if dead then
      explode(e.x, e.y)
      score = score + (e.kind == "mine" and 30 or 10)
      if math.random(10) == 1 then powerups[#powerups + 1] = {x = e.x, y = e.y} end
      table.remove(enemies, i)
    elseif e.x < -16 then
      table.remove(enemies, i)
    elseif ship.inv == 0 and hit(ship.x + 3, ship.y + 5, 10, 6, e.x + 2, e.y + 2, 12, 12) then
      table.remove(enemies, i)
      ship_hit()
      if state ~= "play" then return end
    end
  end

  for i = #ebullets, 1, -1 do
    local b = ebullets[i]
    b.x, b.y = b.x + b.vx, b.y + b.vy
    if b.x < -8 or b.x > W or b.y < -8 or b.y > H then table.remove(ebullets, i)
    elseif ship.inv == 0 and hit(ship.x + 4, ship.y + 6, 8, 4, b.x + 2, b.y + 2, 4, 4) then
      table.remove(ebullets, i)
      ship_hit()
      if state ~= "play" then return end
    end
  end

  for i = #powerups, 1, -1 do
    local p = powerups[i]
    p.x = p.x - 0.8
    if hit(ship.x, ship.y, 16, 16, p.x, p.y, 8, 8) then
      power = math.min(power + 1, 3)
      sfx("SFX_POWER")
      table.remove(powerups, i)
    elseif p.x < -8 then table.remove(powerups, i) end
  end
end

function _update()
  timer = timer + 1
  for y = 0, H - 1 do star_x[y] = (star_x[y] + star_speed[y] * (state == "play" and 1.6 or 1)) % 256 end
  spin = spin + 0.15
  if flash > 0 then flash = flash - 1 end
  for i = #booms, 1, -1 do
    booms[i].t = booms[i].t + 1
    if booms[i].t >= 15 then table.remove(booms, i) end
  end
  if state == "title" then
    if btnp("a") then new_game(); state = "play"; music("MUS_SPACE") end
  elseif state == "play" then
    update_play()
  elseif state == "over" then
    if timer > 60 and btnp("a") then state = "title"; music() end
  end
end

function _draw()
  for y = 0, H - 1 do line_scroll(3, y, star_x[y], 0) end
  rot(2, spin, 1, 64, 64, 180, 52)

  spr_clear()
  local n = 0
  local function put(sh, f, x, y, fl)
    if n < 128 then spr(n, sh, f, x, y, fl or 0); n = n + 1 end
  end
  for _, b in ipairs(booms) do put(boom_sh, b.t // 3, b.x, b.y, BLEND) end
  if state == "play" and (ship.inv == 0 or (ship.inv // 4) % 2 == 0) then
    put(ship_sh, ship.tilt < 0 and 1 or ship.tilt > 0 and 2 or 0, ship.x, ship.y)
  end
  for _, s in ipairs(shots) do put(shots_sh, 0, s.x, s.y) end
  for _, b in ipairs(ebullets) do put(shots_sh, 1, b.x, b.y) end
  for _, p in ipairs(powerups) do put(power_sh, 0, p.x, p.y) end
  for _, e in ipairs(enemies) do
    if e.kind == "mine" then put(mine_sh, (e.t // 8) % 2, e.x, e.y)
    else put(saucer_sh, (e.t // 10) % 2, e.x, e.y) end
  end
  blend(0, ALL, 12, 8) -- only BLEND sprites (the explosions) mix with what is behind them
  if flash > 0 then fade("light", ALL, flash) end

  -- its own look: arcade letters (fonts/arcade.fnt, silk.fnt) and a neon frame (FR_NEON), made by art.py
  text(string.format("%06d", score), 12, 8, 0xFFFFFF, "arcade")
  text("RÉCORD " .. string.format("%06d", math.max(hiscore, score)), SCREEN_W - 12, 8, 0xC8C8FF, "silk", "right")
  text("VIDAS " .. lives .. "   BOMBAS " .. bombs .. "   POTENCIA " .. power, 12, SCREEN_H - 26, 0xA0FFC0, "silk")
  if state == "title" then
    frame("FR_NEON", 30, 92, 420, 136, 2)
    text("NAVES", SCREEN_W // 2, 108, {font = "arcade", scale = 3, align = "center", color = 0x70F4FF,
                                      gradient = 0xFF60C8, outline = 0x101030})
    text("A disparar · C bomba · cruceta mover", SCREEN_W // 2, 166, 0x90A8C0, "silk", "center")
    text("PULSA A", SCREEN_W // 2, 192, {font = "arcade", align = "center", color = 0xFFE070, wave = 2})
  elseif state == "over" then
    shade(0, 0, SCREEN_W, SCREEN_H)
    frame("FR_NEON", 90, 104, 300, 112, 2)
    text("FIN DE LA PARTIDA", SCREEN_W // 2, 126, {font = "arcade", align = "center", color = 0xFF60C8,
                                                  outline = 0x101030, shake = 1})
    text("PUNTOS " .. score, SCREEN_W // 2, 168, 0x70F4FF, "arcade", "center")
  end
end
