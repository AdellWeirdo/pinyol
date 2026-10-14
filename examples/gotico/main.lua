-- Gótico: a castle hall at night, the way a 32-bit console's gothic action game drew it (art.py): characters in up
-- to 256 colours; light that adds up (candle glows and fireballs drawn with img's add) and things half seen through
-- (a ghost, the afterimages of a dash: img's alpha; the moonbeams are mixed into the hall by art/make_art.py); a boss that turns and swells (img's angle and scale),
-- as a PlayStation or a Saturn turned and scaled its sprites; columns in front of everyone.
-- Lluna: arrows walk, up jumps, A lashes the whip, B dashes back leaving afterimages. Reach the skull and break it.
local juice = require("juice")
local particles = require("particles")

local HALL_W, LEVEL_W = 720, 720 * 3
local FLOOR, ARENA = 300, 720 * 3 - 480   -- where the feet are; where the camera stops for the boss
local W, BACK, FEET = 240, 50, 100        -- Lluna's frame, her centre and her feet in it
local IDLE = {0, 1, 2, 3, 4, 3, 2, 1}
local WHIP = {10, 10, 11, 11, 12, 12, 12, 12, 13, 13, 14, 14}
local CANDLES = {130, 470, 830, 1190, 1550, 1910}

state = "title" -- (global: tests/gotico.script)
L, bats, ghost, boss, fire = {}, {}, nil, nil, {}
cam = 0
local t = 0
local fx = particles.new()
local trail = {} -- the dash's afterimages: where she was, and how she looked
local look = {}

local function reset()
  L = {x = 80, y = 0, vx = 0, vy = 0, dir = 1, act = "idle", t = 0, hp = 100, hurt = 0, frame = 0}
  bats = {{x = 600, y = 140, base = 140, t = 0, hp = 1}, {x = 900, y = 120, base = 120, t = 40, hp = 1},
          {x = 1300, y = 150, base = 150, t = 80, hp = 1}}
  ghost = {x = 1100, y = 180, hp = 3, flash = 0}
  boss = {x = LEVEL_W - 150, y = 150, hp = 30, t = 0, flash = 0, angle = 0}
  fire, trail, cam, state = {}, {}, 0, "play"
  fx:clear()
end

function _init()
  show(0)
  sound("SFX_WHIP", {wave = "noise", freq = 2000, slide = -6000, sustain = 0.02, decay = 0.12, volume = 0.3})
  sound("SFX_HIT", "hit", 5)
  sound("SFX_HURT", {wave = "saw", freq = 500, slide = -800, sustain = 0.1, decay = 0.25, volume = 0.3})
  sound("SFX_DASH", {wave = "noise", freq = 600, slide = 1200, sustain = 0.03, decay = 0.1, volume = 0.2})
  sound("SFX_FIRE", {wave = "sine", freq = 200, slide = 400, sustain = 0.05, decay = 0.2, volume = 0.3})
  sound("SFX_BOOM", "explosion", 9)
end

-- ------------------------------------------------------------------ playing

local function hit_box(x, y, w, h, bx, by, bw, bh) return x < bx + bw and bx < x + w and y < by + bh and by < y + h end

local function hurt(dmg, from_x)
  if L.hurt > 0 then return end
  L.hp, L.hurt, L.vx, L.vy, L.act = L.hp - dmg, 60, (L.x < from_x and -3 or 3), -3, "jump"
  sfx("SFX_HURT")
  juice.shake(4)
  if L.hp <= 0 then state, t = "over", 0 end
end

local function update_lluna()
  L.t = L.t + 1
  if L.hurt > 0 then L.hurt = L.hurt - 1 end
  local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
  local ground = L.y >= 0
  if L.act == "whip" then
    L.frame = WHIP[math.min(L.t, #WHIP)]
    if L.t >= 5 and L.t <= 8 then -- the chain stretched out: whatever it reaches
      local hx = L.dir > 0 and L.x + 20 or L.x - 170
      local hy = FLOOR - 70 + L.y
      for _, b in ipairs(bats) do
        if b.hp > 0 and hit_box(hx, hy, 150, 24, b.x - 30, b.y - 20, 60, 40) then b.hp = 0 sfx("SFX_HIT") fx:burst(b.x - cam, b.y, 14, {speed = 3, colours = {0xC080FF, 0x402060}, life = 18, size = 2}) end
      end
      if ghost and ghost.flash == 0 and hit_box(hx, hy, 150, 24, ghost.x - 40, ghost.y - 60, 80, 120) then
        ghost.hp, ghost.flash = ghost.hp - 1, 20
        sfx("SFX_HIT")
        if ghost.hp <= 0 then fx:burst(ghost.x - cam, ghost.y, 30, {speed = 2, colours = {0xC0E0FF, 0x406080}, life = 30, size = 3}) ghost = nil end
      end
      if boss and boss.flash == 0 and hit_box(hx, hy - 60, 150, 90, boss.x - 90, boss.y - 90, 180, 180) then
        boss.hp, boss.flash = boss.hp - 1, 12
        sfx("SFX_HIT")
        juice.freeze(3)
      end
    end
    if L.t >= #WHIP then L.act, L.t = "idle", 0 end
  elseif L.act == "dash" then -- backwards, fast, leaving afterimages
    L.x = L.x - L.dir * 6
    if L.t % 2 == 0 then trail[#trail + 1] = {x = L.x, y = L.y, frame = L.frame, dir = L.dir, life = 14} end
    if L.t >= 10 then L.act, L.t = "idle", 0 end
  else
    if L.hurt < 40 then
      L.vx = dx * 2.4
      if dx ~= 0 then L.dir = dx end
    end
    if ground and btnp("up") then L.vy, L.act, L.t = -7, "jump", 0 end
    if btnp("a") then L.act, L.t = "whip", 0 sfx("SFX_WHIP") end
    if btnp("b") and ground then L.act, L.t = "dash", 0 sfx("SFX_DASH") end
    if L.act ~= "whip" and L.act ~= "dash" then
      if not ground then L.act, L.frame = "jump", L.vy < -3 and 16 or (L.vy < 1 and 17 or 18)
      elseif dx ~= 0 then L.act, L.frame = "walk", 5 + (L.t // 6) % 5
      else L.act, L.frame = "idle", IDLE[(L.t // 8) % #IDLE + 1] end
    end
  end
  L.x = math.max(cam + 20, math.min(LEVEL_W - 20, L.x + (L.act == "whip" and 0 or L.vx)))
  L.vy = L.vy + 0.35
  L.y = math.min(0, L.y + L.vy)
  if L.y == 0 then L.vy = 0 end
end

local function update_foes()
  for _, b in ipairs(bats) do -- they flutter on a wave and swoop when she is near
    if b.hp > 0 then
      b.t = b.t + 1
      local near = math.abs(b.x - L.x) < 220
      b.x = b.x + (L.x < b.x and -1.2 or 1.2) * (near and 1 or 0.3)
      b.y = b.base + math.sin(b.t / 12) * 30 + (near and 60 * math.sin(b.t / 40) ^ 2 or 0)
      if L.hurt == 0 and hit_box(L.x - 15, FLOOR - 90 + L.y, 30, 90, b.x - 25, b.y - 15, 50, 30) then hurt(10, b.x) end
    end
  end
  if ghost then -- drifting towards her through everything, half seen
    ghost.x = ghost.x + (L.x < ghost.x and -0.7 or 0.7)
    ghost.y = 200 + math.sin(t / 30) * 20
    if ghost.flash > 0 then ghost.flash = ghost.flash - 1 end
    if math.abs(ghost.x - L.x) < 300 and L.hurt == 0 and hit_box(L.x - 15, FLOOR - 90 + L.y, 30, 90, ghost.x - 30, ghost.y - 40, 60, 100) then hurt(15, ghost.x) end
  end
  if boss and cam >= ARENA - 4 then -- turns, swells, spits fire
    boss.t = boss.t + 1
    if boss.flash > 0 then boss.flash = boss.flash - 1 end
    boss.angle = math.sin(boss.t / 50) * 20
    boss.y = 150 + math.sin(boss.t / 35) * 30
    if boss.t % 70 == 0 then
      local a = math.atan(FLOOR - 50 - boss.y, L.x - boss.x)
      fire[#fire + 1] = {x = boss.x, y = boss.y + 30, vx = math.cos(a) * 3, vy = math.sin(a) * 3}
      sfx("SFX_FIRE")
    end
    if boss.hp <= 0 then
      fx:burst(boss.x - cam, boss.y, 60, {speed = 5, colours = {0xFFE080, 0xFF6020, 0x401020}, life = 40, size = 4})
      sfx("SFX_BOOM")
      juice.shake(10)
      boss, state, t = nil, "won", 0
    end
  end
  for i = #fire, 1, -1 do
    local f = fire[i]
    f.x, f.y = f.x + f.vx, f.y + f.vy
    if L.hurt == 0 and hit_box(L.x - 15, FLOOR - 90 + L.y, 30, 90, f.x - 10, f.y - 10, 20, 20) then hurt(12, f.x) table.remove(fire, i)
    elseif f.y > FLOOR + 20 or f.x < cam - 40 or f.x > cam + 520 then table.remove(fire, i) end
  end
end

function _update()
  local frozen = juice.update()
  fx:update()
  t = t + 1
  for i = #trail, 1, -1 do trail[i].life = trail[i].life - 1 if trail[i].life <= 0 then table.remove(trail, i) end end
  if state == "title" then
    if btnp("a") or btnp("start") then reset() end
    return
  end
  if frozen or state ~= "play" then
    if state ~= "play" and t > 60 and btnp("a") then state = "title" end
    return
  end
  update_lluna()
  update_foes()
  cam = math.floor(math.max(0, math.min(ARENA, L.x - 200)))
end

-- ------------------------------------------------------------------ drawing

local MIRROR = {flip_x = true}
local GLOW = {add = true, scale = 1}

local function hall(c)
  local first = (c // 2) // HALL_W
  for w = first, first + 1 do
    local x = w * HALL_W - c // 2
    if w % 2 == 1 then img("BG_HALL", x, 0, MIRROR) else img("BG_HALL", x, 0) end
  end
  for _, x in ipairs(CANDLES) do -- the candles' glow, added to what is under it, flickering
    local sx = x - c
    if sx > -60 and sx < 540 then
      GLOW.scale = 1 + 0.08 * noise(x, t / 7)
      img("FX_GLOW", sx - 48 * GLOW.scale, 150 - 48 * GLOW.scale, GLOW)
      circ(sx, 150, 3, 0xFFF0C0)
    end
  end
end

local function lluna_at(x, y, frame, dir, o)
  o.frame, o.flip_x = frame, dir < 0
  img("SPR_LLUNA", x - (dir < 0 and W - 1 - BACK or BACK), FLOOR - FEET + y, o)
end

function _draw()
  if state == "title" then
    hall(t % (LEVEL_W * 2))
    text("GÓTICO", 240, 70, {font = "gothic", scale = 2, align = "center", color = 0xE8D8FF, gradient = 0x8040C0,
                             outline = 0x100818, shadow = 0x000000})
    if (t // 30) % 2 == 0 then text("PULSA A", 240, 230, {font = "arcade", align = "center", color = 0xFFFFFF, outline = 0x100818}) end
    return
  end
  local ox, oy = juice.offset()
  camera(ox, oy)
  hall(cam)
  for _, b in ipairs(bats) do
    if b.hp > 0 then img("SPR_BAT", b.x - cam - 60, b.y - 50, {frame = (t // 4) % 5, flip_x = L.x > b.x}) end
  end
  if ghost then -- half seen; whiter when struck
    img("SPR_GHOST", ghost.x - cam - 60, ghost.y - 90, {alpha = ghost.flash > 0 and 0.9 or 0.5, flip_x = L.x > ghost.x})
  end
  if boss then
    local k = 1 + 0.06 * math.sin(boss.t / 20) -- it breathes
    img("SPR_BOSS", boss.x - cam - 100, boss.y - 100, {angle = boss.angle, scale = k, tint = boss.flash > 0 and boss.flash % 4 < 2 and 0xFFFFFF or nil})
  end
  for _, tr in ipairs(trail) do -- the dash's afterimages, fading
    look.alpha, look.tint, look.add = tr.life / 20, 0x8080FF, nil
    lluna_at(tr.x - cam, tr.y, tr.frame, tr.dir, look)
  end
  look.alpha, look.add = nil, nil
  look.tint = L.hurt > 0 and L.hurt % 6 < 3 and 0xFFFFFF or nil
  if state ~= "over" then lluna_at(L.x - cam, L.y, L.frame, L.dir, look) end
  for _, f in ipairs(fire) do img("FX_GLOW", f.x - cam - 24, f.y - 24, {add = true, scale = 0.5}) end
  if cam < ARENA - 200 then -- the columns, nearer than everyone, now and then (none in the skull's room)
    local cx = (cam * 1.3) % (HALL_W * 2)
    img("BG_COLUMNS", -cx, 0) img("BG_COLUMNS", HALL_W * 2 - cx, 0)
  end
  camera()
  fx:draw()
  rect(14, 12, 204, 14, 0x100818)
  rect(16, 14, math.max(0, 2 * L.hp), 10, 0xC02040)
  text("LLUNA", 16, 30, {font = "gothic", color = 0xE8D8FF, outline = 0x100818})
  if boss and cam >= ARENA - 4 then
    rect(262, 12, 204, 14, 0x100818)
    rect(264, 14, math.floor(200 * boss.hp / 30), 10, 0x8040C0)
  end
  if state == "won" then text("LA CALAVERA CAE", 240, 120, {font = "gothic", scale = 2, align = "center", color = 0xE8D8FF, outline = 0x100818}) end
  if state == "over" then text("FIN", 240, 120, {font = "gothic", scale = 3, align = "center", color = 0xC02040, outline = 0x100818}) end
  juice.draw()
end
