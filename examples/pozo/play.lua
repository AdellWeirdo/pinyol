-- play: the game. A claw slides round the rim of a well and fires down its lanes; things climb up out of the far end.
--   claw: left and right move it a lane (hold to run), A fires, B is the zapper (the first use of a level clears the
--   well, the second takes one enemy).
--   garra (flipper): climbs, flips across lanes, and on the rim runs at the claw.  nodriza (tanker): splits in two when
--   shot or half way up.  pua (spiker): climbs a little way and goes back, leaving a spike that kills the claw as it
--   dives down the lane at the end of the level.
local V, W, Snd = require("vec"), require("well"), require("sound")
local P = {}

local BULLET_V, MAX_BULLETS, FIRE_EVERY = 0.034, 8, 7
local FOE_H = 0.07 -- how deep an enemy is, in depth
local YELLOW, RED, PINK, GREEN, WHITE = 0xFFE040, 0xFF3050, 0xFF40FF, 0x40FF60, 0xFFFFC0
local COLOUR = {garra = RED, nodriza = PINK, pua = GREEN}
local POINTS = {garra = 150, nodriza = 100, pua = 200}

P.score, P.lives, P.level, P.extra = 0, 3, 1, 20000
P.mode, P.t, P.flash = "play", 0, 0 -- play | dying | warp | over
P.me = {lane = 1, q = 1.5, cool = 0, dead = 0, safe = 0}
P.foes, P.bullets, P.debris, P.spikes = {}, {}, {}, {}
P.queue, P.spawn_t, P.zaps, P.kills = {}, 0, 0, 0
P.hook = function(id) end -- main sets it: an achievement or an extra life, by name

-- ------------------------------------------------------------------ lanes

local function step(lane, dir) -- the lane beside `lane` (nil at the end of an open well)
  local k = lane + dir
  if W.closed then return (k - 1) % W.n + 1 end
  if k < 1 or k > W.n then return nil end
  return k
end

local function toward(from, to) -- which way (-1, 0, 1) to go from lane `from` to `to`, the short way round
  if from == to then return 0 end
  local d = to - from
  if W.closed then
    local n = W.n
    d = (d + n // 2) % n - n // 2
    if d == 0 then return 1 end
  end
  return d > 0 and 1 or -1
end

local function lane_at(f) -- the lane an enemy is in for a shot (half way through a flip it changes)
  if f.flip and f.flip.t >= 0.5 then return f.flip.to end
  return f.lane
end

-- ------------------------------------------------------------------ sparks

local function boom(x, y, n, colour, speed, size) -- an explosion: pieces of line flying off, turning
  local D = P.debris
  for _ = 1, n do
    local a = math.random() * 2 * math.pi
    local v = speed * (0.4 + math.random() * 0.8)
    local life = 22 + math.random(18)
    D[#D + 1] = {x = x, y = y, vx = math.cos(a) * v, vy = math.sin(a) * v, a = math.random() * math.pi, spin = (math.random() - 0.5) * 0.5,
                 len = size * (0.6 + math.random() * 0.8), life = life, max = life, c = colour}
  end
  while #D > 60 do table.remove(D, 1) end
end

local function award(n)
  local before = P.score
  P.score = P.score + n
  if P.score >= P.extra then
    P.extra = P.extra + 20000
    P.lives = math.min(P.lives + 1, 6)
    P.hook("extra")
  end
  if before < 10000 and P.score >= 10000 then P.hook("diezmil") end
end

-- ------------------------------------------------------------------ the enemies

local function spawn(kind, lane, d)
  local L = P.level
  local f = {kind = kind, lane = lane or math.random(W.n), d = d or 1.0, t = 0}
  if kind == "garra" then f.v = 0.0030 + 0.00035 * L
  elseif kind == "nodriza" then f.v = 0.0021 + 0.0002 * L
  else f.v, f.stop = 0.0028 + 0.0002 * L, 0.25 + math.random() * 0.3 end
  P.foes[#P.foes + 1] = f
  return f
end

local function remove(f)
  for i, g in ipairs(P.foes) do if g == f then table.remove(P.foes, i) return end end
end

local function split(f) -- a nodriza opens into two garras, one in each lane beside it
  for _, dir in ipairs({-1, 1}) do
    local k = step(f.lane, dir)
    if k then spawn("garra", k, f.d) end
  end
end

local function kill(f, how)
  remove(f)
  local x, y = W.at(lane_at(f), 0.5, f.d + FOE_H / 2)
  local s = W.scale(f.d)
  boom(x, y, 7, COLOUR[f.kind], 2.2 + 3 * s, 12 * s + 5)
  award(POINTS[f.kind])
  P.kills = P.kills + 1
  P.hook("primera")
  Snd.play(f.kind == "nodriza" and "SFX_POP" or "SFX_HIT")
  if f.kind == "nodriza" and how ~= "zap" then split(f) end
end

local function caught() -- the claw is taken
  local me = P.me
  me.dead = 1
  P.mode, P.t = "dying", 0
  P.lives = P.lives - 1
  local x, y = W.rim_at(me.q)
  boom(x, y, 16, W.pal[3], 5, 18)
  Snd.play("SFX_DIE")
  P.flash = 10
end

local function update_foes()
  local me = P.me
  for i = #P.foes, 1, -1 do
    local f = P.foes[i]
    if f.kind == "garra" then
      if f.rim then
        f.t = f.t + 1
        if f.t >= 15 then
          f.t = 0
          local dir = toward(f.lane, me.lane)
          if dir ~= 0 then f.lane = step(f.lane, dir) or f.lane end
        end
        if f.lane == me.lane and P.mode == "play" and me.dead == 0 and me.safe == 0 then caught() end
      else
        if f.flip then
          f.flip.t = f.flip.t + 1 / 16
          f.d = f.d - f.v * 0.5
          if f.flip.t >= 1 then f.lane, f.flip = f.flip.to, nil end
        else
          f.d = f.d - f.v
          if f.d < 0.93 and f.d > 0.12 and math.random() < 0.0036 + 0.0004 * P.level then
            local dir = math.random() < 0.5 and -1 or 1
            local k = step(f.lane, dir)
            if not k then dir = -dir k = step(f.lane, dir) end
            if k then f.flip = {to = k, dir = dir, t = 0} end
          end
        end
        if f.d <= 0 then f.d, f.rim, f.t, f.flip = 0, true, 0, nil end
      end
    elseif f.kind == "nodriza" then
      f.d = f.d - f.v
      if f.d <= 0.45 then
        remove(f)
        split(f)
        Snd.play("SFX_BLIP")
      end
    else -- pua
      if f.back then
        f.d = f.d + f.v * 1.3
        if f.d >= 1.02 then remove(f) end
      else
        f.d = f.d - f.v
        if f.d <= f.stop then f.back = true end
      end
      local sp = P.spikes[f.lane]
      if not sp or f.d < sp then P.spikes[f.lane] = f.d end
    end
  end
end

-- ------------------------------------------------------------------ the claw and its shots

P.ai = false -- the title plays itself, as an arcade machine does while nobody is there

local function ai_input() -- what a player would press: go to the lane of the nearest enemy, fire, zap when it gets crowded
  local me = P.me
  local best
  for _, f in ipairs(P.foes) do
    if f.kind ~= "pua" and (not best or f.d < best.d) then best = f end
  end
  P.ai_t = (P.ai_t or 0) + 1
  local dir = 0
  if best and P.ai_t % 5 == 0 then
    local target = lane_at(best)
    if target ~= me.lane then dir = toward(me.lane, target) end
  end
  local fire = best ~= nil and P.ai_t % 3 ~= 0
  local zap = best ~= nil and best.d < 0.2 and P.zaps == 0 and #P.foes >= 3 and P.ai_t % 7 == 0
  return dir, fire, zap
end

local function read_input()
  if P.ai then return ai_input() end
  local dir = 0
  if btnp("left", 9, 3) then dir = -1 elseif btnp("right", 9, 3) then dir = 1 end
  return dir, btn("a"), btnp("b")
end

local function update_claw()
  local me = P.me
  if me.safe > 0 then me.safe = me.safe - 1 end
  local dir, fire, zap = read_input()
  if dir ~= 0 then
    local k = step(me.lane, dir)
    if k then me.lane = k Snd.play("SFX_MOVE") end
  end
  local target = me.lane + 0.5
  local diff = target - me.q
  if W.closed then diff = (diff + W.n / 2) % W.n - W.n / 2 end
  if math.abs(diff) > 0.45 then diff = diff > 0 and 0.45 or -0.45 end
  me.q = me.q + diff
  if W.closed then me.q = (me.q - 1) % W.n + 1 end
  if me.cool > 0 then me.cool = me.cool - 1 end
  if fire and me.cool == 0 and #P.bullets < MAX_BULLETS then
    P.bullets[#P.bullets + 1] = {lane = me.lane, d = 0.02}
    me.cool = FIRE_EVERY
    Snd.play("SFX_SHOT")
  end
  if zap and P.zaps < 2 then
    P.zaps = P.zaps + 1
    P.flash = 14
    P.hook("descarga")
    Snd.play("SFX_ZAP")
    if P.zaps == 1 then
      for i = #P.foes, 1, -1 do kill(P.foes[i], "zap") end
    else
      local best
      for _, f in ipairs(P.foes) do if f.kind ~= "pua" and (not best or f.d < best.d) then best = f end end
      if best then kill(best, "zap") end
    end
  end
end

local function update_bullets()
  for i = #P.bullets, 1, -1 do
    local b = P.bullets[i]
    b.d = b.d + BULLET_V
    local hit = false
    for _, f in ipairs(P.foes) do
      if lane_at(f) == b.lane and ((f.rim and b.d < 0.07) or (not f.rim and math.abs(f.d + FOE_H / 2 - b.d) < 0.05)) then
        kill(f)
        hit = true
        break
      end
    end
    if not hit then
      local sp = P.spikes[b.lane]
      if sp and b.d >= sp - 0.01 then -- the end of a spike: it shortens
        sp = sp + 0.04
        P.spikes[b.lane] = sp < 1 and sp or nil
        award(1)
        Snd.play("SFX_SPIKE")
        hit = true
      end
    end
    if hit or b.d >= 1 then table.remove(P.bullets, i) end
  end
end

local function update_debris()
  for i = #P.debris, 1, -1 do
    local d = P.debris[i]
    d.x, d.y, d.a, d.life = d.x + d.vx, d.y + d.vy, d.a + d.spin, d.life - 1
    d.vx, d.vy = d.vx * 0.97, d.vy * 0.97
    if d.life <= 0 then table.remove(P.debris, i) end
  end
end

-- ------------------------------------------------------------------ levels

function P.begin_level(level)
  P.level = level
  W.set(level)
  local me = P.me
  me.lane = W.closed and 1 or (W.n + 1) // 2
  me.q, me.cool, me.dead, me.safe = me.lane + 0.5, 0, 0, 90
  P.foes, P.bullets, P.spikes = {}, {}, {}
  local q, total = {}, math.min(8 + 2 * level, 36)
  for i = 1, total do
    local r = math.random()
    local kind = "garra"
    if level >= 2 and r < 0.22 then kind = "nodriza" elseif level >= 3 and r > 0.88 then kind = "pua" end
    q[i] = kind
  end
  P.queue, P.spawn_t, P.zaps = q, 40, 0
  P.mode, P.t = "play", 0
  if level >= 5 then P.hook("hondo") end
end

function P.new_game()
  P.score, P.lives, P.extra, P.kills = 0, 3, 20000, 0
  P.debris = {}
  P.flash = 0
  P.begin_level(1)
end

local function start_warp()
  P.mode, P.t = "warp", 0
  P.warp_hit = P.spikes[P.me.lane] -- a spike in the claw's lane is where it will crash
  P.crashed = false
  Snd.play("SFX_WARP")
end

local function update_warp()
  local me = P.me
  P.t = P.t + 1
  if P.t <= 62 and not P.crashed then
    local dw = P.t / 62 * 0.97
    if P.warp_hit and dw >= P.warp_hit then
      P.crashed = true
      local x, y = W.at(me.lane, 0.5, dw)
      boom(x, y, 14, W.pal[3], 4, 12)
      P.lives = P.lives - 1
      Snd.play("SFX_DIE")
      P.flash = 8
    end
  end
  if P.t == 62 then
    award(100 * P.level)
    if P.lives <= 0 then P.mode, P.t = "over", 0 return end
    P.begin_level(P.level + 1)
    P.mode, P.t = "warp", 62
    Snd.play("SFX_LEVEL")
  end
  if P.t >= 104 then P.mode, P.t = "play", 0 end
end

function P.update()
  P.t = P.t + (P.mode == "warp" and 0 or 1)
  if P.flash > 0 then P.flash = P.flash - 1 end
  update_debris()
  if P.mode == "warp" then update_warp() return end
  if P.mode == "dying" then
    update_foes()
    update_bullets()
    P.t = P.t + 0
    if P.t >= 80 then
      if P.lives > 0 then
        local me = P.me
        me.dead, me.safe, P.mode, P.t = 0, 110, "play", 0
        for i = #P.foes, 1, -1 do if P.foes[i].rim then table.remove(P.foes, i) end end
      else
        P.mode, P.t = "over", 0
      end
    end
    return
  end
  if P.mode ~= "play" then return end
  update_claw()
  update_bullets()
  update_foes()
  if #P.queue > 0 then
    P.spawn_t = P.spawn_t - 1
    local alive = 0
    for _, f in ipairs(P.foes) do if f.kind ~= "pua" then alive = alive + 1 end end
    if P.spawn_t <= 0 and alive < 3 + P.level // 2 + 1 then
      spawn(table.remove(P.queue, 1))
      P.spawn_t = math.max(24, 70 - 4 * P.level)
    end
  elseif #P.foes == 0 and P.me.dead == 0 then
    start_warp()
  end
end

-- ------------------------------------------------------------------ drawing

local function draw_claw(q, depth, scale, colour)
  local x, y = W.qat(q, depth)
  local x0, y0 = W.qat(q - 0.44, depth)
  local x1, y1 = W.qat(q + 0.44, depth)
  local vx, vy = W.vanish()
  local nx, ny = x - vx, y - vy
  local nl = math.sqrt(nx * nx + ny * ny)
  if nl < 1 then nx, ny, nl = 0, 1, 1 end
  nx, ny = nx / nl, ny / nl
  local out, deep = 17 * scale, 11 * scale
  local lt_x, lt_y = x0 + nx * out, y0 + ny * out
  local rt_x, rt_y = x1 + nx * out, y1 + ny * out
  local li_x, li_y = x0 * 0.62 + x * 0.38 - nx * 2 * scale, y0 * 0.62 + y * 0.38 - ny * 2 * scale
  local ri_x, ri_y = x1 * 0.62 + x * 0.38 - nx * 2 * scale, y1 * 0.62 + y * 0.38 - ny * 2 * scale
  local mx, my = x - nx * deep, y - ny * deep
  V.open({lt_x, lt_y, li_x, li_y, mx, my, ri_x, ri_y, rt_x, rt_y}, colour, 3)
end

local function draw_foe(f)
  local c = COLOUR[f.kind]
  local q, d = f.lane, f.d
  if f.flip then q = f.lane + f.flip.dir * f.flip.t end
  if f.kind == "garra" then
    local tilt = f.flip and math.sin(math.pi * f.flip.t) * 0.05 or 0
    local ax, ay = W.qat(q + 0.08, d + tilt)
    local bx, by = W.qat(q + 0.92, d - tilt)
    local cx, cy = W.qat(q + 0.08, d + FOE_H - tilt)
    local ex, ey = W.qat(q + 0.92, d + FOE_H + tilt)
    V.shape({ax, ay, bx, by, cx, cy, ex, ey}, c, 2)
  elseif f.kind == "nodriza" then
    local lx, ly = W.qat(q + 0.06, d + FOE_H / 2)
    local tx, ty = W.qat(q + 0.5, d)
    local rx, ry = W.qat(q + 0.94, d + FOE_H / 2)
    local bx, by = W.qat(q + 0.5, d + FOE_H)
    V.shape({lx, ly, tx, ty, rx, ry, bx, by}, c, 2)
    V.line(lx, ly, rx, ry, c, 1)
    V.line(tx, ty, bx, by, c, 1)
  else
    local zig, pts = {{0.5, 0}, {0.88, 0.026}, {0.12, 0.052}, {0.88, 0.078}, {0.5, 0.104}}, {}
    for i, z in ipairs(zig) do
      pts[i * 2 - 1], pts[i * 2] = W.qat(q + z[1], d + z[2])
    end
    V.open(pts, c, 2)
  end
end

P.claw = draw_claw

function P.draw()
  local me = P.me
  if P.mode == "warp" then
    P.draw_warp()
  else
    W.draw(me.dead == 0 and me.lane or nil)
    for lane, ds in pairs(P.spikes) do
      local x0, y0 = W.at(lane, 0.5, ds)
      local x1, y1 = W.at(lane, 0.5, 1)
      V.line(x0, y0, x1, y1, GREEN, 2)
    end
    for _, f in ipairs(P.foes) do draw_foe(f) end
    for _, b in ipairs(P.bullets) do
      local x0, y0 = W.at(b.lane, 0.5, b.d)
      local x1, y1 = W.at(b.lane, 0.5, b.d + 0.045)
      V.line(x0, y0, x1, y1, WHITE, 2)
    end
    if me.dead == 0 and (me.safe == 0 or (ticks() // 4) % 2 == 0) then draw_claw(me.q, 0, 1, W.pal[3]) end
  end
  for _, d in ipairs(P.debris) do
    local dx, dy = math.cos(d.a) * d.len / 2, math.sin(d.a) * d.len / 2
    V.line(d.x - dx, d.y - dy, d.x + dx, d.y + dy, V.dim(d.c, 0.25 + 0.75 * d.life / d.max), 1)
  end
end

function P.draw_warp()
  local me, t = P.me, P.t
  if t < 62 then
    W.draw(nil, 1 - t / 100)
    local dw = t / 62 * 0.97
    for k = 0, 5 do -- rings rushing by
      local d = ((k / 6) + t * 0.012) % 1
      W.ring(d, V.dim(W.pal[2], 0.4 + 0.6 * (1 - d)))
    end
    if not P.crashed then draw_claw(me.lane + 0.5, dw, W.scale(dw), W.pal[3]) end
    for lane, ds in pairs(P.spikes) do
      local x0, y0 = W.at(lane, 0.5, ds)
      local x1, y1 = W.at(lane, 0.5, 1)
      V.line(x0, y0, x1, y1, GREEN, 2)
    end
  else
    local k = math.min(1, (t - 62) / 30)
    W.draw(nil, k)
    for j = 0, 5 do
      local d = (((j / 6) + (104 - t) * 0.012) % 1)
      W.ring(d, V.dim(W.pal[2], (0.4 + 0.6 * (1 - d)) * (1 - k)))
    end
    if t > 78 then draw_claw(me.q, 0, 1, W.pal[3]) end
  end
end

return P
