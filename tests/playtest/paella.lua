-- playtest adapter for Paella de combate (see docs/playtest.md).
--
-- The chef: PT_CFG.chef, else chefs[seed % 6 + 1] (estrella espuma pinche arrocero brioche crianza). The adapter starts the mission itself (dbg_play).
-- PT_CFG.boss_only = true starts straight at the boss (a quick way to measure the boss fight).
--
-- The perfect player is a closed-loop planner. Every tick it (1) lists what can hurt it in the next ~70-110 ticks (every hostile shot flown forward to the floor and its
-- blast, the kamikaze's dive, the boss's beams / stomp / shock wave, pecking soldiers, the crab, the boss's body), (2) picks where it wants to stand and how to aim (a
-- firing spot that hits the nearest gull, the open pot or the open head), (3) searches ~150 short input plans (walk, turn, jump at a tick with a short or full hold, crouch)
-- by simulating the chef's own physics, and takes the first tick of the safest plan that ends closest to the wanted spot. It never throws grenades and never boards the tractor.
-- It also sets c.frame the way Chef.draw does (headless does not draw, and the muzzle of a shot depends on the frame drawn the tick before).
local Play = require("core.play")
local Boss = require("core.boss")
local Foes = require("core.foes")
local Shots = require("core.shots")
local Items = require("core.items")
local Tractor = require("core.tractor")
local Chef = require("core.chef")
local Run = require("core.run")
local C = require("core.const")

local CHEFS = {"estrella", "espuma", "pinche", "arrocero", "brioche", "crianza"}
local CFG = PT_CFG or {}
local CHEF_ID = CFG.chef or CHEFS[(CFG.seed or 0) % 6 + 1]
local FLOOR, W = C.FLOOR, C.W
local MARGIN = 2 -- pixels added to every danger
local MB = 1 -- ... and to the boss's beams (the only escape from a salvo is a few pixels wide: see the notes)
local H_GROUND, H_BOSS = 70, 120
local BEAM_LOOK = 45 -- ticks before a salvo that the planner starts to care (it has gone to a spot with an escape by then)

-- The boss's beam salvo: the escape is a few pixels wide (found by an exhaustive search of every input of the next 50-70 ticks, tools in the notes), so the perfect player
-- stands on an exact spot under the head (x = key, in pixels from the arena's left edge), shooting straight up at the head, and plays back the tape found for that spot.
-- Each token is one tick: L/N/R (walk), "c" (crouch held), "J" (jump held).
local TAPE_DATA = {
  slow = {
    ["125.3"] = "L..,L..,L..,L..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,Nc.,Rc.,Rc.,Rc.,Rc.,R..,Lc.,N.J,N.J,L.J,N.J,L.J,L.J,L.J,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,",
    ["125.6"] = "L..,L..,L..,L..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,Nc.,Rc.,Rc.,Rc.,Rc.,R..,Lc.,N.J,N.J,L.J,N.J,L.J,L.J,L.J,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,",
    ["125.9"] = "L..,L..,L..,L..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,Nc.,Rc.,Rc.,Rc.,Rc.,R..,Lc.,N.J,N.J,L.J,N.J,L.J,L.J,L.J,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,",
    ["126.2"] = "L..,L..,L..,L..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,Nc.,Rc.,Rc.,Rc.,Rc.,R..,Lc.,N.J,N.J,L.J,N.J,L.J,L.J,L.J,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,",
    ["126.5"] = "L..,L..,L..,L..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,R..,Nc.,Rc.,Rc.,Rc.,Rc.,R..,Lc.,N.J,N.J,L.J,N.J,L.J,L.J,L.J,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,L..,",
  },
  fast = {
  },
}

local TAPES = {slow = {}, fast = {}}
for var, set in pairs(TAPE_DATA) do
  for k, str in pairs(set) do
    local arr = {}
    for tok in str:gmatch("[^,]+") do arr[#arr + 1] = {({L = -1, N = 0, R = 1})[tok:sub(1, 1)], tok:sub(2, 2) == "c", tok:sub(3, 3) == "J"} end
    TAPES[var][tonumber(k)] = arr
  end
end
local KEYS10 = {} -- spots (tenths of a pixel from the left edge of the arena) that have a tape
for k in pairs(TAPES.slow) do if k >= 125.85 then KEYS10[#KEYS10 + 1] = math.floor(k * 10 + 0.5) end end -- (the shot goes up at x + 16 and its radius must reach the head's left edge, 150.6)
table.sort(KEYS10)
local KEYSET = {}
for _, k in ipairs(KEYS10) do KEYSET[k] = true end
local tape = nil -- the tape being played: {arr = ..., i = n}

-- ------------------------------------------------------------------ bookkeeping (logs for the report)
local last = {b = false, c = false, cancel = 0}
local deaths_zone = {}
local RING = {}
local boss_enter_t, boss_dead_t, boss_deaths = nil, nil, 0
local boss_logged = false
local gren_enter = nil
local last_bstate = nil
local last_death_cause = "-"

local function near_cause(c)
  local best, bd = nil, 1e9
  for _, s in ipairs(Shots.theirs) do
    local d = math.abs(s.x - c.x) + math.abs((s.y - (c.y - 36))) * 0.7 - s.r
    if d < bd then best, bd = "shot_" .. s.kind, d end
  end
  for _, f in ipairs(Foes.list) do
    if f.state ~= "dying" then
      local d = math.abs(f.x - c.x) + math.abs(f.y - c.y) * 0.3
      if d < 90 and d < bd then best, bd = "foe_" .. f.kind .. "_" .. f.state, d end
    end
  end
  if Boss.active then
    if Boss.state == "stomp" and Boss.st >= 55 and Boss.st < 70 and math.abs(c.x - (Boss.x - 110)) < 90 then return "boss_stomp_legs" end
    if c.x > Boss.x - 70 then return "boss_touch" end
    if bd > 25 and best == nil then best = "boss_" .. tostring(Boss.state) end
  end
  return best or "unknown"
end

local hurt0 = Chef.hurt
Chef.hurt = function(...)
  local c = Play.chef
  if c and Chef.get() == c and c.state == "play" and c.inv <= 0 and not c.vehicle and c.shield <= 0 then
    local cause = near_cause(c)
    local where = Boss.active and ("boss_" .. tostring(Boss.state)) or ("z" .. Play.zone)
    last_death_cause = cause
    if CFG.dbg then
      for _, l in ipairs(RING) do log("RING " .. l) end
      local hbx, hby, hbw, hbh = c.hit_box()
      log(string.format("RING chef box x=%.1f y=%.1f w=%.0f h=%.0f (cam %.0f)", hbx - Play.cam, hby, hbw, hbh, Play.cam))
      for _, sh in ipairs(Shots.theirs) do log(string.format("RING shot %s x=%.1f y=%.1f vx=%.1f vy=%.1f r=%d", sh.kind, sh.x - Play.cam, sh.y, sh.vx, sh.vy, sh.r)) end
    end
    if Boss.active then boss_deaths = boss_deaths + 1 end
    log(string.format("PT_DEATH chef=%s zone=%d where=%s cause=%s x=%.0f cam=%.0f boss_hp=%s boss_st=%s lives_left=%d", CHEF_ID, Play.zone, where, cause, c.x, Play.cam,
      Boss.active and string.format("%.0f", Boss.hp) or "-", Boss.active and tostring(Boss.st) or "-", c.lives - 1))
  end
  return hurt0(...)
end

-- the frame Chef.draw would pick (muzzle of the next shot depends on it)
local function emu_frame(c)
  if c.state == "dead" or c.state == "win" then return end
  if c.inv > 0 and (c.inv // 4) % 2 == 0 then return end
  if c.vehicle then c.frame = c.aim == "up" and "aim_up_0" or "idle_" .. (c.t // 10) % 4 return end
  local k = (c.fire_t // 3) % 2
  local f
  if c.throw_t > 0 then f = "throw_" .. math.min(2, (16 - c.throw_t) // 6)
  elseif c.stab_t > 0 then f = "stab_" .. math.min(2, (14 - c.stab_t) // 5)
  else
    local firing = c.fire_t < 10
    if c.crouch then
      if firing then f = "crouch_fire_" .. k elseif c.moving then f = "crawl_" .. (c.t // 8) % 2 else f = "crouch_0" end
    elseif c.aim == "up" or c.aim == "diag" then f = firing and ("fire_up_" .. k) or "aim_up_0"
    elseif c.aim == "down" then f = firing and ("fire_down_" .. k) or "jump_1"
    elseif not c.ground then f = firing and ("jumpfire_" .. k) or ("jump_" .. (c.vy < -2.5 and 0 or (c.vy < 1.5 and 1 or 2)))
    elseif c.moving then f = firing and ("runfire_" .. (c.t // 4) % 4) or ("run_" .. (c.t // 4) % 6)
    elseif firing then f = "fire_" .. k
    else f = "idle_" .. (c.t // 10) % 4 end
  end
  c.frame = f
end

-- ------------------------------------------------------------------ the world, flown forward
local function hazards(c, H, cam)
  local hz = {shots = {}, blasts = {}, kamis = {}, pecks = {}, crabs = {}, legs = nil, beams = nil}
  for k = 1, H do hz.shots[k], hz.blasts[k] = {}, {} end
  local function add_shot(kind, x, y, vx, vy, r, grav, k0, t0)
    local t, k = t0 or 0, k0
    while k <= H do
      t = t + 1
      if kind == "bomb" or grav then vy = vy + 0.18 end
      x, y = x + vx, y + vy
      if x < cam - 80 or x > cam + W + 80 or t > 400 then return end
      local l = hz.shots[k]
      l[#l + 1] = {x, y, r}
      if (kind == "bomb" or kind == "shell" or kind == "rocket" or kind == "beam") and y >= FLOOR - 6 then
        local b = hz.blasts[k]
        b[#b + 1] = {x, FLOOR - 20, kind == "rocket" and 46 or 40}
        return
      end
      k = k + 1
    end
  end
  hz.add_shot = add_shot
  for _, s in ipairs(Shots.theirs) do add_shot(s.kind, s.x, s.y, s.vx, s.vy, s.r, s.grav, 1, s.t) end
  for _, f in ipairs(Foes.list) do
    if f.state ~= "dying" and f.state ~= "gone" then
      if f.kind == "soldier" and (f.state == "walk" or f.state == "peck" or f.state == "shoot") then hz.pecks[#hz.pecks + 1] = f.x end
      if f.kind == "crab" then hz.crabs[#hz.crabs + 1] = f.x end
      if f.kind == "kamikaze" then
        if f.state == "dive" then
          local x, y, st = f.x, f.y, f.st
          for k = 1, H do
            x, y, st = x + f.vx, y + f.vy, st + 1
            hz.kamis[#hz.kamis + 1] = {k, x, y}
            if y >= FLOOR - 16 or st > 120 then
              local b = hz.blasts[k]
              b[#b + 1] = {x, math.min(y, FLOOR) - 20, 44}
              break
            end
          end
        elseif f.state == "windup" then
          hz.dive = hz.dive or {}
          hz.dive[#hz.dive + 1] = {k = math.max(1, 37 - f.st), x = f.x, y = f.y}
        elseif f.state == "hover" then
          hz.dive = hz.dive or {}
          hz.dive[#hz.dive + 1] = {k = math.max(1, 71 - f.st) + 37, x = f.x, y = f.y}
        end
      end
    end
  end
  if Boss.active and Boss.state ~= "dying" then
    local B = Boss
    hz.boss_x = B.x
    if B.state == "stomp" then
      if B.st < 66 then hz.legs = {from = math.max(1, 55 - B.st), to = 65 - B.st + 1, x = B.x - 110} end
      if B.st < 62 then
        local k0 = 62 - B.st
        add_shot("shock", B.x - 130, FLOOR - 12, -4.2, 0, 12, false, k0, 0)
        if B.hp < B.max_hp * 0.55 then add_shot("shock", B.x - 130, FLOOR - 12, -3.0, 0, 12, false, k0, 0) end
      end
    elseif B.state == "beam" then
      local fast = B.hp < B.max_hp * 0.55
      hz.beams = {}
      if B.st < 110 and 110 - B.st <= BEAM_LOOK then hz.beams[#hz.beams + 1] = 110 - B.st end
      if fast and B.st < 130 and 130 - B.st <= BEAM_LOOK then hz.beams[#hz.beams + 1] = 130 - B.st end
    end
  end
  return hz
end

local function inside_box(sx, sy, r, bx, by, bw, bh) return sx + r > bx and sx - r < bx + bw and sy + r > by and sy - r < by + bh end

-- one step towards a spot: walk far away, finish with small steps (a crawl is 1.3 px) so it ends within a pixel of it
local function go_move(d)
  if d > 4.1 then return 1, false elseif d < -4.1 then return -1, false end
  local ad = math.abs(d)
  local bd, bdx, bcr = ad, 0, false
  if math.abs(ad - 2.7) < bd then bd, bdx, bcr = math.abs(ad - 2.7), d > 0 and 1 or -1, false end
  if math.abs(ad - 1.3) < bd then bd, bdx, bcr = math.abs(ad - 1.3), d > 0 and 1 or -1, true end
  return bdx, bcr
end

-- what the chef does at tick k of a plan: dx, crouch, jump held
local function act(p, k, x, tx)
  local dx
  if p.cont then -- the rest of a run-and-jump already begun
    return p.d, false, (k >= p.f and k < p.t)
  end
  if p.off then -- wait (or stay at the spot) until the dangerous tick, then run in a direction and jump
    if k <= p.off then
      local dx2, cr2 = go_move(tx - x)
      return dx2, cr2, false
    end
    local kk = k - p.off
    return p.d, false, (kk >= p.tj and kk < p.tj + p.hold)
  end
  if p.go then
    local dx2, cr2 = go_move(tx - x)
    return dx2, cr2, false
  else dx = (k <= p.sw) and p.d1 or ((k <= p.sw2) and p.d2 or p.d3) end
  return dx, (p.cr and k <= p.cr) or false, (p.tj ~= nil and k >= p.tj and k < p.tj + p.hold)
end

-- simulate a plan: returns the tick of the first hit (H + 1 if none), the final x, and tick-1 action
local function run_plan(c, p, hz, H, cam, tx, boss_mode)
  local x, y, vy, ground = c.x, c.y, c.vy, c.ground
  local prevb = p.prevb
  local maxx = Chef.max_x or 1e9
  local inv = c.inv
  local tr = Tractor.list[1]
  local bx_ = hz.boss_x
  local cxs, cys = {}, {}
  local first
  for k = 1, H do
    local dx, cr, b = act(p, k, x, tx)
    if k == 1 then first = {dx, cr, b} end
    local crouch = cr and ground
    local vx = dx * (crouch and 1.3 or 2.7)
    if b and not prevb and ground and not crouch then vy, ground = C.JUMP, false end
    if not b and vy < -4.5 then vy = -4.5 end
    prevb = b
    vy = math.min(vy + C.GRAVITY, C.MAX_FALL)
    x = math.max(cam + 26, math.min(maxx, x + vx))
    y = y + vy
    if y >= FLOOR then y, vy, ground = FLOOR, 0, true end
    cxs[k], cys[k] = x, y
    if inv - k <= 0 then
      local h = crouch and C.CROUCH_H or C.HERO_H
      local bx, by = x - C.HERO_W / 2 - MARGIN, y - h - MARGIN
      local bw, bh = C.HERO_W + 2 * MARGIN, h + 2 * MARGIN
      local hit = false
      local sl = hz.shots[k]
      for i = 1, #sl do
        local s = sl[i]
        if inside_box(s[1], s[2], s[3], bx, by, bw, bh) then hit = true WHY = "shot" break end
      end
      if not hit then
        local bl = hz.blasts[k]
        for i = 1, #bl do
          local b2 = bl[i]
          if math.abs(bx + bw / 2 - b2[1]) < b2[3] + bw / 2 and math.abs(by + bh / 2 - b2[2]) < b2[3] + bh / 2 then hit = true WHY = "blast" break end
        end
      end
      if not hit then
        for i = 1, #hz.kamis do
          local km = hz.kamis[i]
          if km[1] == k and math.abs(x - km[2]) < 34 + MARGIN and math.abs((y - 40) - km[3]) < 46 + MARGIN then hit = true WHY = "kami" break end
        end
      end
      if not hit and y > FLOOR - 36 then
        for i = 1, #hz.pecks do if math.abs(x - hz.pecks[i]) < 62 + MARGIN then hit = true WHY = "peck" break end end
      end
      if not hit and y > FLOOR - 30 then
        for i = 1, #hz.crabs do if math.abs(x - hz.crabs[i]) < 84 + MARGIN then hit = true WHY = "crab" break end end
      end
      if not hit and bx_ then
        if x > bx_ - 60 - MARGIN then hit = true WHY = "bosstouch"
        elseif hz.legs and k >= hz.legs.from and k < hz.legs.to and math.abs(x - hz.legs.x) < 70 + MARGIN and y > FLOOR - 20 - MARGIN then hit = true WHY = "legs" end
      end
      if not hit and tr and tr.state == "parked" and (tr.nb or 0) - k <= 0 and tr.hp > 0 and vy > 0 and math.abs(x - tr.x) < 74 and y > FLOOR - 100 and y < FLOOR - 16 then hit = true WHY = "tractor" end
      if hit then return k, x, first end
    end
  end
  -- dynamic dangers that depend on where the chef is when they start (kamikaze dive, boss beams)
  local function dyn_shot(k0, sx, sy, vx, vy, r, kind)
    local t, x2, y2 = 0, sx, sy
    for k = k0, H + 40 do
      t = t + 1
      x2, y2 = x2 + vx, y2 + vy
      local kk = math.min(k, H)
      if k <= H then
        local h = C.HERO_H
        local px, py = cxs[k], cys[k]
        if inv - k <= 0 and inside_box(x2, y2, r, px - C.HERO_W / 2 - MB, py - h - MB, C.HERO_W + 2 * MB, h + 2 * MB) then return k end
      end
      if y2 >= FLOOR - 6 then
        if k <= H and inv - k <= 0 then
          local px, py = cxs[k], cys[k]
          local bw, bh = C.HERO_W + 2 * MB, C.HERO_H + 2 * MB
          if math.abs(px - x2) < 40 + bw / 2 and math.abs(py - bh / 2 + MB - (FLOOR - 20)) < 40 + bh / 2 then return k end
        end
        return nil
      end
    end
  end
  if hz.dive then
    for _, d in ipairs(hz.dive) do
      if d.k < H then
        local px, py = cxs[d.k], cys[d.k]
        local dx, dy = px - d.x, (py - 40) - d.y
        local l = math.max(1, math.sqrt(dx * dx + dy * dy))
        local vx, vy2 = dx / l * 6.2, dy / l * 6.2
        local x2, y2 = d.x, d.y
        for k = d.k + 1, math.min(H, d.k + 120) do
          x2, y2 = x2 + vx, y2 + vy2
          if inv - k <= 0 and math.abs(cxs[k] - x2) < 34 + MARGIN and math.abs((cys[k] - 40) - y2) < 46 + MARGIN then return k, x, first end
          if y2 >= FLOOR - 16 then
            if inv - k <= 0 and math.abs(cxs[k] - x2) < 44 + 15 + MARGIN and math.abs(cys[k] - 36 - (math.min(y2, FLOOR) - 20)) < 44 + 36 + MARGIN then return k, x, first end
            break
          end
        end
      end
    end
  end
  if hz.beams and Boss.active then
    local B = Boss
    local mx, my = (hz.boss_x or B.x) - 147, (hz.boss_y or B.y) - 224
    for _, kf in ipairs(hz.beams) do
      if kf <= H then
        local px = cxs[kf]
        for lane = -1, 1 do
          local tx2 = px + lane * 90
          local dx, dy = tx2 - mx, FLOOR - my
          local l = math.sqrt(dx * dx + dy * dy)
          local k = dyn_shot(kf, mx, my, dx / l * 6.5, dy / l * 6.5, 16, "beam")
          if k then WHY = "beam" .. lane return k, x, first end
        end
      end
    end
  end
  return H + 1, x, first
end

-- the static dangers at tick k for a chef at (x, y); `m` is the margin in pixels
local function hit_now(hz, k, x, y, crouch, m, tr, vy)
  local h = crouch and C.CROUCH_H or C.HERO_H
  local bx, by = x - C.HERO_W / 2 - m, y - h - m
  local bw, bh = C.HERO_W + 2 * m, h + 2 * m
  local sl = hz.shots[k]
  for i = 1, #sl do
    local s = sl[i]
    if inside_box(s[1], s[2], s[3], bx, by, bw, bh) then return true end
  end
  local bl = hz.blasts[k]
  for i = 1, #bl do
    local b2 = bl[i]
    if math.abs(bx + bw / 2 - b2[1]) < b2[3] + bw / 2 and math.abs(by + bh / 2 - b2[2]) < b2[3] + bh / 2 then return true end
  end
  for i = 1, #hz.kamis do
    local km = hz.kamis[i]
    if km[1] == k and math.abs(x - km[2]) < 34 + m and math.abs((y - 40) - km[3]) < 46 + m then return true end
  end
  if y > FLOOR - 36 then
    for i = 1, #hz.pecks do if math.abs(x - hz.pecks[i]) < 62 + m then return true end end
  end
  if y > FLOOR - 30 then
    for i = 1, #hz.crabs do if math.abs(x - hz.crabs[i]) < 84 + m then return true end end
  end
  local bx_ = hz.boss_x
  if bx_ then
    if x > bx_ - 60 - m then return true end
    if hz.legs and k >= hz.legs.from and k < hz.legs.to and math.abs(x - hz.legs.x) < 70 + m and y > FLOOR - 20 - m then return true end
  end
  if tr and tr.state == "parked" and (tr.nb or 0) - k <= 0 and tr.hp > 0 and vy > 0 and math.abs(x - tr.x) < 74 and y > FLOOR - 100 and y < FLOOR - 16 then return true end
  return false
end

-- viability search: depth first over the inputs of the next H ticks (walk, jump held or not, crouch), the goal-ward ones first, remembering the states that were tried.
-- Returns the first input of a path that survives all H ticks (or of the one that lasts longest) and how long it lasts.
local ACT_ORDER = {}
local function dfs_plan(c, hz, H, cam, tx, m, budget)
  local maxx = Chef.max_x or 1e9
  local lo = cam + 26
  local inv0 = c.inv
  local tr = Tractor.list[1]
  local memo, nodes = {}, 0
  local floor_ = math.floor
  local function expand(k, x, y, vy, gr, pb)
    -- survive from tick k on: returns the number of ticks survived (up to H - k + 1)
    if k > H then return 0 end
    local xb, yb, vb = floor_((x - cam) / 1.5), floor_((FLOOR - y) / 3), floor_((vy + 12) * 2)
    local key = ((((k * 512 + xb) * 128 + yb) * 64 + vb) * 2 + (gr and 1 or 0)) * 2 + (pb and 1 or 0)
    local mv = memo[key]
    if mv then return mv end
    nodes = nodes + 1
    local best = 0
    if nodes <= budget then
      local d = tx - x
      local g = d > 1.5 and 1 or (d < -1.5 and -1 or 0)
      local o1, o2, o3
      if g == 0 then o1, o2, o3 = 0, 1, -1 elseif g > 0 then o1, o2, o3 = 1, 0, -1 else o1, o2, o3 = -1, 0, 1 end
      local ord = {o1, o2, o3}
      for oi = 1, 3 do
        local dx = ord[oi]
        for opt = 1, 3 do
          local b, cr = false, false
          if opt == 2 then b = true elseif opt == 3 then
            if not gr then break end
            cr = true
          end
          local crouch = cr and gr
          local vx = dx * (crouch and 1.3 or 2.7)
          local vy2, gr2 = vy, gr
          if b and not pb and gr and not crouch then vy2, gr2 = C.JUMP, false end
          if not b and vy2 < -4.5 then vy2 = -4.5 end
          vy2 = math.min(vy2 + C.GRAVITY, C.MAX_FALL)
          local x2 = math.max(lo, math.min(maxx, x + vx))
          local y2 = y + vy2
          if y2 >= FLOOR then y2, vy2, gr2 = FLOOR, 0, true end
          local dead = (inv0 - k <= 0) and hit_now(hz, k, x2, y2, crouch, m, tr, vy2)
          if not dead then
            local dep = 1 + expand(k + 1, x2, y2, vy2, gr2, b)
            if dep > best then best = dep end
            if best >= H - k + 1 then break end
          end
        end
        if best >= H - k + 1 then break end
      end
    end
    memo[key] = best
    return best
  end
  -- root: try the inputs in order and keep the first full survivor (else the longest)
  local d = tx - c.x
  local g = d > 1.5 and 1 or (d < -1.5 and -1 or 0)
  local ord = g == 0 and {0, 1, -1} or (g > 0 and {1, 0, -1} or {-1, 0, 1})
  local bestd, besta = -1, nil
  for oi = 1, 3 do
    local dx = ord[oi]
    for opt = 1, 3 do
      local b, cr = false, false
      if opt == 2 then b = true elseif opt == 3 then
        if not c.ground then break end
        cr = true
      end
      local crouch = cr and c.ground
      local vx = dx * (crouch and 1.3 or 2.7)
      local vy, gr = c.vy, c.ground
      if b and not last.b and gr and not crouch then vy, gr = C.JUMP, false end
      if not b and vy < -4.5 then vy = -4.5 end
      vy = math.min(vy + C.GRAVITY, C.MAX_FALL)
      local x2 = math.max(lo, math.min(maxx, c.x + vx))
      local y2 = c.y + vy
      if y2 >= FLOOR then y2, vy, gr = FLOOR, 0, true end
      local dead = (inv0 - 1 <= 0) and hit_now(hz, 1, x2, y2, crouch, m, tr, vy)
      if not dead then
        local dep = 1 + expand(2, x2, y2, vy, gr, b)
        if dep > bestd then bestd, besta = dep, {dx, cr, b} end
        if dep >= H then NODES_TOTAL = (NODES_TOTAL or 0) + nodes return besta, bestd, nodes end
      end
    end
  end
  NODES_TOTAL = (NODES_TOTAL or 0) + nodes
  return besta, bestd, nodes
end

-- ------------------------------------------------------------------ aiming: where does a shot of this weapon hit?
local function muzzle_of(face, aim, crouch, ground)
  if aim == "up" or aim == "diag" then return 16 * face, -108 end
  if crouch then return 56 * face, -34 end
  if not ground then return 56 * face, -62 end
  return 58 * face, -64
end

local function shot_hits(w, mx, my, ax, ay, box, cam, kind)
  local sp, g, r = w.speed, w.gravity or 0, w.r
  local vx, vy = ax * sp, ay * sp
  local x, y = mx, my
  local hb, pb
  if kind then local bx = Boss.boxes() hb, pb = bx.head, bx.pot end
  for _ = 1, w.life do
    vy = vy + g
    x, y = x + vx, y + vy
    if x < cam - 60 or x > cam + W + 60 or y > FLOOR + 6 or y < -40 then return false end
    if kind then -- as Boss.hit_at: the pot, then the head, then the rest of the machine eats the shot
      if inside_box(x, y, r, pb[1], pb[2], pb[3], pb[4]) then return kind == "pot" end
      if inside_box(x, y, r, hb[1], hb[2], hb[3], hb[4]) then return kind == "head" end
      if not Boss.pot_fix and x > Boss.x - 155 and x < Boss.x + 150 and y > FLOOR - 330 then return false end -- (a copy of the game without that clank sets Boss.pot_fix)
    elseif inside_box(x, y, r, box[1], box[2], box[3], box[4]) then return true end
  end
  return false
end

local AIMS = {fwd = {1, 0}, diag = {0.7071, -0.7071}, up = {0, -1}}

-- the best (spot, face, aim) to hit a box from near x
local function firing_spot(c, box, cam, xlo, xhi, span, kind)
  local w = c.weapon
  local best, bc
  for off = -span, span, 20 do
    local sx = math.max(xlo, math.min(xhi, c.x + off))
    for face = -1, 1, 2 do
      for aim, v in pairs(AIMS) do
        if not (aim == "up" and false) then
          local mx, my = muzzle_of(face, aim, false, true)
          if shot_hits(w, sx + mx, FLOOR + my, v[1] * face, v[2], box, cam, kind) then
            local cost = math.abs(sx - c.x) + (face ~= c.dir and 25 or 0) + (aim == "fwd" and 0 or 10)
            if not bc or cost < bc then bc, best = cost, {x = sx, face = face, aim = aim} end
          end
        end
      end
    end
  end
  return best
end

-- ------------------------------------------------------------------ the decision
local last_plan
local plans_cache = {}

local function build_plans(H, boss_mode)
  local key = H
  if plans_cache[key] then return plans_cache[key] end
  local P = {}
  local pats = {}
  for d = -1, 1 do pats[#pats + 1] = {d, d, H, H, d} end
  for _, sw in ipairs({8, 16}) do
    for d1 = -1, 1 do
      for d2 = -1, 1 do
        if d1 ~= d2 then pats[#pats + 1] = {d1, d2, sw, sw + 16, 0} end
      end
    end
    for d1 = -1, 1, 2 do pats[#pats + 1] = {d1, d1, sw, sw, 0} end
  end
  for _, d in ipairs(pats) do
    local base = {d1 = d[1], d2 = d[2], sw = d[3], sw2 = d[4], d3 = d[5]}
    P[#P + 1] = base
    for tj = 1, H - 8, 6 do
      P[#P + 1] = {d1 = d[1], d2 = d[2], sw = d[3], sw2 = d[4], d3 = d[5], tj = tj, hold = 9}
      P[#P + 1] = {d1 = d[1], d2 = d[2], sw = d[3], sw2 = d[4], d3 = d[5], tj = tj, hold = 40}
    end
  end
  for _, d in ipairs({-1, 0, 1}) do
    P[#P + 1] = {d1 = d, d2 = d, sw = H, sw2 = H, d3 = d, cr = 40}
    P[#P + 1] = {d1 = d, d2 = d, sw = H, sw2 = H, d3 = d, cr = 15}
  end
  plans_cache[key] = P
  return P
end

local MACRO = {} -- (direction, jump tick, hold) triples: run one way and jump at a tick, holding the button a number of ticks
for d = -1, 1 do
  for tj = 1, 40, 2 do
    for _, hold in ipairs({8, 10, 12, 14, 16, 20, 26, 40}) do MACRO[#MACRO + 1] = {d, tj, hold} end
  end
end
local MP = {} -- the one plan table the macro search reuses
local function macro_set(i, off)
  local m = MACRO[i]
  MP.off, MP.d, MP.tj, MP.hold = off, m[1], m[2], m[3]
  return MP
end

-- boss beam: from which standing spot x0 (at the tick the beam fires) is there an escape? Worked out a few spots a tick while the boss walks in (the call budget is
-- 20M steps), once for the slow and once for the fast boss (a second salvo).
local beam_cache = {}
local function boss_final_x()
  if Boss.state == "intro" then return Boss.target_x + (Boss.x - Boss.target_x) * 0.97 ^ (151 - Boss.st) end
  return Boss.x
end
local function empty_hz(H, bx, by)
  local hz = {shots = {}, blasts = {}, kamis = {}, pecks = {}, crabs = {}, boss_x = bx, boss_y = by}
  for k = 1, H do hz.shots[k], hz.blasts[k] = {}, {} end
  return hz
end
local function beam_spots_step(cam, n)
  local bc = beam_cache
  if not bc.xs then
    bc.slow, bc.fast, bc.i, bc.done = {}, {}, 0, false
    bc.xs = {}
    for x0 = cam + 26, Boss.target_x - 75, 4 do bc.xs[#bc.xs + 1] = x0 end
  end
  if bc.done then return end
  local H = 100
  for _ = 1, n do
    bc.i = bc.i + 1
    if bc.i > 2 * #bc.xs then bc.done = true return end
    local fast = bc.i > #bc.xs
    local x0 = bc.xs[fast and bc.i - #bc.xs or bc.i]
    local hz = empty_hz(H, boss_final_x(), Boss.y)
    hz.beams = {1}
    if fast then hz.beams[2] = 21 end
    local c2 = {x = x0, y = FLOOR, vy = 0, ground = true, inv = 0}
    local ok = false
    for i = 1, #MACRO do
      local p = macro_set(i, 0)
      p.prevb = false
      local k = run_plan(c2, p, hz, H, cam, x0)
      if k > H then ok = true break end
    end
    (fast and bc.fast or bc.slow)[#(fast and bc.fast or bc.slow) + 1] = {x0, ok}
  end
end

-- the chef's x is always a multiple of a tenth of a pixel (steps of 2.7 and 1.3): find the fewest steps that land exactly on a spot with a tape
local STEPS = {{27, false}, {-27, false}, {13, true}, {-13, true}}
local function near_key(x10f)
  for _, k in ipairs(KEYS10) do if math.abs(x10f - k) <= 2.5 then return k end end
  return nil
end
local function approach_step(c, cam, left)
  local x10 = math.floor((c.x - C.LEVEL_W) * 10 + 0.5) -- (the boss's x is from LEVEL_W; the camera may stop a pixel short of it)
  if near_key((c.x - C.LEVEL_W) * 10) and c.dir == 1 then return 0, false, true end -- (the straight-up shot leaves 16 px to the right of a chef who faces right)
  local seen = {[x10 * 2 + (c.dir == 1 and 1 or 0)] = true}
  local cur = {{x10, 0, c.dir == 1 and 1 or 0}}
  for _ = 1, math.min(left, 16) do
    local nxt = {}
    for _, e in ipairs(cur) do
      for si = 1, 4 do
        local nx = math.max(260, e[1] + STEPS[si][1])
        local fl = STEPS[si][1] > 0 and 1 or 0
        local k = nx * 2 + fl
        if not seen[k] then
          seen[k] = true
          local first = e[2] ~= 0 and e[2] or si
          if KEYSET[nx] and fl == 1 then return (STEPS[first][1] > 0) and 1 or -1, STEPS[first][2], false end
          nxt[#nxt + 1] = {nx, first, fl}
        end
      end
    end
    cur = nxt
  end
  return nil
end

local function set_goal(c, cam)
  -- returns {x = wanted spot, face, aim} and the target (or nil)
  local maxx = Chef.max_x or 1e9
  local goal = {x = c.x, face = c.dir, aim = "fwd"}
  if Boss.active then
    local lim = math.min(maxx, Boss.x - 75)
    goal.face = 1
    if Boss.state == "pot" then
      -- the pot cannot be hurt by shots (Boss.hit_at: the machine eats them first): only a pressure cooker thrown from near it does (blast 78 px)
      goal.x, goal.aim, goal.grenade = lim, "fwd", Boss.pot_open
      if Boss.pot_fix then
        local sp = firing_spot(c, nil, cam, lim, lim, 0, "pot")
        if sp and Boss.pot_open then goal.aim = sp.aim end
      end
    elseif Boss.head_open then
      local sp = firing_spot(c, nil, cam, cam + 26, lim, 220, "head")
      if sp then goal.x, goal.aim, goal.head = sp.x, sp.aim, true else goal.x = math.min(lim, cam + 130) end
    else
      goal.x = math.min(lim, cam + 130) -- keep room on both sides while rockets and stomps come
    end
    if Boss.state == "beam" and Boss.st < 112 and beam_cache.done then
      local list = (Boss.hp < Boss.max_hp * 0.55) and beam_cache.fast or beam_cache.slow
      local best, bd
      local gs, ge
      local function close_group()
        if gs then
          local mid = (gs + ge) / 2
          local d = math.abs(mid - goal.x) + 0.3 * math.abs(mid - c.x)
          if (ge - gs) >= 4 and (not bd or d < bd) then best, bd = mid, d end
        end
        gs, ge = nil, nil
      end
      for _, e in ipairs(list) do
        if e[2] and e[1] <= lim then
          if gs and e[1] - ge <= 4 then ge = e[1] else close_group() gs, ge = e[1], e[1] end
        else close_group() end
      end
      close_group()
      if best then
        goal.x = best
        local sp = firing_spot(c, nil, cam, best, best, 0, "head")
        goal.aim, goal.head = sp and sp.aim or "fwd", sp ~= nil
      end
    end
    return goal
  end
  -- gulls
  local best, bs
  for _, f in ipairs(Foes.list) do
    if f.state ~= "dying" and f.state ~= "gone" then
      local bx, by, bw, bh = Foes.box(f)
      if bx + bw > cam - 30 and bx < cam + W + 30 then
        local pr = ({kamikaze = -80, drone = -30, bazooka = -40, crab = 0, soldier = 0})[f.kind] or 0
        local sc = math.abs(f.x - c.x) + pr
        if not bs or sc < bs then bs, best = sc, {f = f, box = {bx, by, bw, bh}} end
      end
    end
  end
  if best then
    local f = best.f
    local sp = firing_spot(c, best.box, cam, cam + 30, maxx, 100)
    local stand = f.kind == "crab" and 210 or 120
    if sp and (f.kind ~= "soldier" or math.abs(sp.x - f.x) > 95) and (f.kind ~= "crab" or math.abs(sp.x - f.x) > 190) then
      goal.x, goal.face, goal.aim = sp.x, sp.face, sp.aim
    else
      local face = f.x >= c.x and 1 or -1
      goal.x, goal.face, goal.aim = f.x - face * stand, face, "fwd"
      if f.d.fly then goal.x = f.x - face * 20 end
    end
    goal.target = true
  else
    goal.x, goal.face, goal.aim = c.x + 150, 1, "fwd"
  end
  -- things worth picking up
  local bi, bd
  for _, it in ipairs(Items.list) do
    local want = (it.kind:sub(1, 6) == "crate_" and 200) or (it.kind == "heart" and 260) or (it.kind == "shield" and 200) or (it.kind == "ammo" and 260) or (it.kind == "food" and 150) or 0
    local d = math.abs(it.x - c.x)
    if want > 0 and d < want and it.x > cam + 40 and it.x < cam + W - 40 and (not best or math.abs(best.f.x - c.x) > 140) and (not bd or d < bd) then bi, bd = it, d end
  end
  if bi then goal.x = bi.x end
  return goal
end

local function decide(pt)
  local c = Play.chef
  if not c or c.state ~= "play" or c.vehicle or Play.state == "clear" or Play.state == "over" then tape = nil return {} end
  local cam = Play.cam
  -- the beam salvo: a tape being played, or the walk to the exact spot that has one
  if tape then
    local e = tape.arr[tape.i]
    tape.i = tape.i + 1
    if not e then tape = nil else
      local out = {a = true}
      if e[1] < 0 then out.left = true elseif e[1] > 0 then out.right = true end
      if e[2] then out.down = true end
      if e[3] then out.b = true end
      last.b, last.c = e[3] and true or false, false
      return out
    end
  end
  if Boss.active and Boss.state == "beam" and Boss.st <= 109 and #KEYS10 > 0 and #Shots.theirs == 0 and c.inv <= 0 then
    local x10 = near_key((c.x - C.LEVEL_W) * 10)
    if Boss.st == 109 then
      if x10 and c.dir == 1 and c.ground and c.vy == 0 and not last.b then
        local fast = Boss.hp < Boss.max_hp * 0.55
        local arr = (fast and TAPES.fast[x10 / 10]) or TAPES.slow[x10 / 10]
        if CFG.dbg then log(string.format("PT_TAPE key=%.1f fast=%s", x10 / 10, tostring(fast))) end
        tape = {arr = arr, i = 1}
        local e = tape.arr[1]
        tape.i = 2
        local out = {a = true}
        if e[1] < 0 then out.left = true elseif e[1] > 0 then out.right = true end
        if e[2] then out.down = true end
        if e[3] then out.b = true end
        last.b, last.c = e[3] and true or false, false
        return out
      end
    else
      local out = {a = true}
      local dxs, crs, stay = approach_step(c, cam, 109 - Boss.st)
      if dxs == nil then
        local g1, g2 = go_move(C.LEVEL_W + 126 - c.x)
        dxs, crs = g1, g2
      end
      if stay then out.up = true end
      if CFG.dbg and Boss.st % 10 == 0 then log(string.format('SPOTDBG st=%d x=%.2f stay=%s c.aim=%s cool=%d mine=%d hp=%.1f head_open=%s dir=%d w=%s p=%s s1=%s', Boss.st, c.x - cam, tostring(stay), c.aim, c.cool, #Shots.mine, Boss.hp, tostring(Boss.head_open), c.dir, c.weapon.name, tostring(c.weapon.pellets), Shots.mine[1] and string.format('%.1f,%.1f v=%.1f,%.1f', Shots.mine[1].x - cam, Shots.mine[1].y, Shots.mine[1].vx, Shots.mine[1].vy) or '-')) end
      if dxs < 0 then out.left = true elseif dxs > 0 then out.right = true end
      if crs then out.down = true end
      last.b, last.c = false, false
      return out
    end
  end
  local H = Boss.active and H_BOSS or H_GROUND
  NODES_TOTAL = 0
  if CFG.dbg and pt.t % 25 == 0 then log(string.format('TICK %d x=%.0f cam=%.0f foes=%d shots=%d', pt.t, c.x, cam, #Foes.list, #Shots.theirs)) end
  local goal = set_goal(c, cam)
  if CFG.dbg and Boss.active and Boss.state == "beam" and Boss.st == 2 then
    for _, nm in ipairs({"slow", "fast"}) do
      local t = {}
      for _, e in ipairs(beam_cache[nm] or {}) do t[#t + 1] = string.format("%d%s", e[1] - cam, e[2] and "+" or "-") end
      log("SPOTS " .. nm .. " " .. table.concat(t, " "))
    end
  end
  if Boss.active then beam_spots_step(cam, 2) end
  local hz = hazards(c, H, cam)
  local tx = goal.x
  local base = {go = true, prevb = last.b}
  local hit_k, _, first = run_plan(c, base, hz, H, cam, tx)
  local chosen = first
  local cont_ok = false
  if hit_k <= H and last.cont and pt.t < last.cont.to_abs + 40 then
    local cp = {cont = true, d = last.cont.d, f = last.cont.from_abs - pt.t + 1, t = last.cont.to_abs - pt.t + 1, prevb = last.b}
    local kc, _, f1 = run_plan(c, cp, hz, H, cam, tx)
    if kc > H then chosen, cont_ok, last_plan = f1, true, "C" end
  end
  if hit_k > H then last.cont = nil end
  if hit_k <= H and not cont_ok then
    local macro = hz.beams and hz.beams[1]
    if macro then
      local best, bk, bc, bp, bestp
      for i = 1, #MACRO do
        local p = macro_set(i, hz.beams[1] - 1)
        p.prevb = last.b
        local k, ex, f1 = run_plan(c, p, hz, H, cam, tx)
        local cost = math.abs(ex - tx)
        if k > H then
          if not best or bk <= H or cost < bc then best, bk, bc, bp, bestp = f1, k, cost, "M", {off = p.off, d = p.d, tj = p.tj, hold = p.hold} end
        elseif (not best or bk <= H) and (not bk or k > bk or (k == bk and cost < bc)) then best, bk, bc, bp, bestp = f1, k, cost, "M", {off = p.off, d = p.d, tj = p.tj, hold = p.hold} end
      end
      chosen = best or first
      last_plan = bp
      last.cont = nil
      if bestp then last.cont = {d = bestp.d, from_abs = pt.t + bestp.off + bestp.tj - 1, to_abs = pt.t + bestp.off + bestp.tj - 1 + bestp.hold} end
    else
      local pick, pick_d
      for ti, m in ipairs({6, 2, 0}) do
        local a, dep = dfs_plan(c, hz, H, cam, tx, m, ({2500, 2000, 1500})[ti])
        if a and (not pick_d or dep > pick_d) then pick, pick_d = a, dep end
        if dep >= H then break end
      end
      chosen = pick or first
      last_plan = "D" .. tostring(pick_d)
      last.cont = nil
    end
  end
  local dx, crouch, jump = chosen[1], chosen[2], chosen[3]
  if CFG.dbg and Boss.active and (Boss.state == "beam") and (Boss.st % 5 == 0 or (Boss.st > 104 and Boss.st < 135)) then
    log(string.format("DBG st=%d x=%.1f y=%.1f goal=%.1f base_hit=%d chosen=%s,%s,%s beams=%s plan=%s", Boss.st, c.x - cam, c.y, tx - cam, hit_k, tostring(dx), tostring(crouch), tostring(jump), hz.beams and tostring(hz.beams[1]) or "-", tostring(last_plan)))
  end
  if CFG.dbg then
    RING[#RING + 1] = string.format("t=%d st=%s/%s x=%.1f y=%.1f hit_k=%d plan=%s dx=%s cr=%s j=%s nshots=%d", pt.t, tostring(Boss.state), tostring(Boss.st), c.x - cam, c.y, hit_k, tostring(last_plan), tostring(chosen[1]), tostring(chosen[2]), tostring(chosen[3]), #Shots.theirs)
    if #RING > 45 then table.remove(RING, 1) end
  end
  if CFG.dbg and Boss.active and Boss.state == "pot" and Boss.st % 10 == 0 then
    log(string.format("POT st=%d open=%s x=%.1f goal=%.1f aim=%s face=%d c.aim=%s cool=%d hp=%.1f hit_k=%d plan=%s mine=%d", Boss.st, tostring(Boss.pot_open), c.x - cam, tx - cam, goal.aim, goal.face, c.aim, c.cool, Boss.hp, hit_k, tostring(last_plan), #Shots.mine))
  end
  local out = {}
  -- aim and fire
  local fire_now = c.cool <= 1
  local a = true
  if (Boss.active and Boss.state == "beam" and Boss.st < 112) or hit_k <= H or #Shots.theirs > 0 then
    goal.aim = "fwd" -- no wiggling at the spot of an escape, nor while dodging
    goal.face = c.dir
  end
  if crouch then
    out.down = true
  elseif goal.aim == "diag" then
    out.up = true
    if fire_now then dx = goal.face elseif last.cancel ~= 0 then dx = last.cancel end
  elseif goal.aim == "up" then
    out.up = true
    if fire_now then dx = 0 end
  else
    if fire_now and dx ~= 0 and dx ~= goal.face and c.dir == goal.face then a = false end
    if c.dir ~= goal.face and dx == 0 and not crouch then dx = goal.face end -- turn round
  end
  last.cancel = (goal.aim == "diag" and fire_now and not crouch) and -goal.face or 0
  if dx < 0 then out.left = true elseif dx > 0 then out.right = true end
  if jump then out.b = true end
  out.a = a
  if goal.grenade and c.grenades > 0 and c.throw_t == 0 and c.ground and not last.c and not crouch and c.x > Boss.x - 135 and c.x < Boss.x - 62 then out.c = true end
  last.c = out.c or false
  last.b = jump and true or false
  return out
end

-- ------------------------------------------------------------------ the adapter
local function start_mission()
  if CFG.boss_only then dbg_play(CHEF_ID) dbg_boss() else dbg_play(CHEF_ID) end
end

local function tick_hook()
  local c = Play.chef
  if G.state ~= "play" or not c then return end
  emu_frame(c)
  if Boss.active then
    if not boss_enter_t then boss_enter_t = Play.t gren_enter = c.grenades end
    if Boss.hp <= 0 and not boss_dead_t then boss_dead_t = Boss.t end
    if Boss.state ~= last_bstate then
      last_bstate = Boss.state
      log(string.format("PT_ST chef=%s t=%d state=%s hp=%.1f gren=%d lives=%d", CHEF_ID, Boss.t, tostring(Boss.state), Boss.hp, c.grenades, c.lives))
    end
  end
end

local err_logged = false
PLAYTEST = {
  stuck_ticks = 5400,
  playing = function()
    if (G.state == "title" or G.state == "select") and PT and PT.t >= 2 then start_mission() end
    return G.state == "play"
  end,
  progress = function()
    if Boss.active then return C.LEVEL_W + 100 + (Boss.max_hp - Boss.hp) end
    return Play.cam or 0
  end,
  done = function()
    tick_hook()
    local res
    if G.state == "results" or G.state == "ending" then res = "win"
    elseif G.state == "continue" or G.state == "over" then res = "lose" end
    if res and not boss_logged then
      boss_logged = true
      log(string.format("PT_BOSS gren_enter=%s gren_end=%s chef=%s result=%s reached=%s fight=%s net=%s deaths_in_boss=%d max_hp=%s hp_left=%s run_deaths=%d", tostring(gren_enter), tostring(Play.chef and Play.chef.grenades), CHEF_ID, res, tostring(boss_enter_t ~= nil),
        tostring(boss_dead_t or "-"), tostring(boss_dead_t and boss_dead_t - 150 or "-"), boss_deaths, tostring(Boss.max_hp), tostring(Boss.active and math.max(0, Boss.hp) or "-"), Run.deaths))
    end
    return res
  end,
  where = function()
    if Boss.active then return "boss_" .. tostring(Boss.state) end
    return string.format("z%d_c%d", Play.zone, ((Play.cam % C.ZONE_W) // C.CHUNK) + 1)
  end,
  probe = function() return {n_lives = Play.chef and Play.chef.lives or 0, boss_hp = Boss.active and Boss.hp or 0, cam = Play.cam or 0, score = Run.score or 0} end,
  deaths = function() return Run.deaths end,
  perfect = function(pt)
    local ok, r = pcall(decide, pt)
    if ok then return r end
    if not err_logged then err_logged = true log("PT_ERROR " .. tostring(r)) end
    return {a = true, right = true}
  end,
}
