-- Gol de oro: five a side, the way a Neo Geo football game looks. Every pixel at the screen's full 480x320 from
-- packed pictures (art.py): a pitch twice as wide as the screen and a stand full of people (its left half, and the
-- same mirrored), footballers in four kits that are one picture in four palettes (img's pal). You play red, towards
-- the right: the one nearest the ball is yours. Arrows: run (with the ball at your feet). A: shoot or pass that way.
local juice = require("juice")

local HALF = 917                      -- the pitch picture: the left half; the right is it mirrored
local W, H = 2 * HALF, 635
local TOP, BOTTOM = 232, 620          -- the touchlines (the near one is the screen's bottom edge)
local MOUTH = {342, 404}              -- the goals' posts, far and near, where they stand on the line
local GOAL_Y = 373                    -- the middle of a goal
local BAR = 70                        -- the crossbar's height
-- The pitch is drawn as a camera in the stand sees it: the goal lines lean. Where each one is, at a height y:
local function left(y) return 160 - 0.635 * (y - 228) end
local function right(y) return W - left(y) end
local KITS = {red = nil, blue = "KIT_BLUE", keep_red = "KIT_GREEN", keep_blue = "KIT_YELLOW"}
local MATCH = 60 * 90

ball = {x = HALF, y = 420, z = 0, vx = 0, vy = 0, vz = 0} -- (global: tests/futbol.script reads and moves them)
players, score, state = {}, {0, 0}, "title"
local cam_x, cam_y, clock, timer = 0, 0, 0, 0
owner = nil -- who has the ball at his feet (global: tests let go of it)
local look = {}
local front = {} -- each team's one nearest the ball, this tick

local SPOTS = { -- a side's places, as fractions of its half (attacking to the right): keeper, two back, two up
  {0.03, 0.5}, {0.28, 0.3}, {0.28, 0.72}, {0.62, 0.38}, {0.62, 0.66},
}

local function spot(team, i) -- where a player stands, from his team's places and where the ball is
  local s = SPOTS[i]
  local fx = s[1] * HALF + (i > 1 and (ball.x - HALF) * 0.35 or 0)
  local y = TOP + s[2] * (BOTTOM - TOP)
  local x = team == 1 and left(y) + 20 + fx or right(y) - 20 - fx
  return math.max(left(y), math.min(right(y), x)), y
end

function kickoff(to) -- (global: the benchmark starts again with eleven a side)
  ball = {x = HALF, y = (TOP + BOTTOM) / 2, z = 0, vx = 0, vy = 0, vz = 0}
  players, owner = {}, nil
  for team = 1, 2 do
    for i = 1, bench and 11 or 5 do -- (the console's benchmark plays eleven a side)
      local k = (i - 1) % 5 + 1
      local x, y = spot(team, k)
      players[#players + 1] = {team = team, keeper = i == 1, x = x + (i > 5 and (team == 1 and 60 or -60) or 0),
                               y = y + (i > 5 and 40 or 0), k = k, dir = team == 1 and 1 or -1, t = 0, frame = 2,
                               cool = 0, kit = i == 1 and (team == 1 and KITS.keep_red or KITS.keep_blue) or
                                               (team == 2 and KITS.blue or nil)}
    end
  end
  if to then ball.x = HALF + (to == 1 and -20 or 20) end
end

function _init()
  show(0) -- no 240x160 world: every pixel at the screen's resolution
  sound("SND_KICK", "hit", 3)
  sound("SND_WHISTLE", {wave = "square", freq = 2200, vibrato = 0.4, vibrato_speed = 30, sustain = 0.35, decay = 0.1,
                        volume = 0.3})
  sound("SND_GOAL", "powerup", 7)
end

-- ------------------------------------------------------------------ playing

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local function nearest(team) -- of a team, the one nearest the ball (not the keeper unless the ball is his)
  local best, bd = nil, 1e9
  for _, p in ipairs(players) do
    if p.team == team and not p.keeper then
      local d = dist(p, ball)
      if d < bd then best, bd = p, d end
    end
  end
  return best
end

local function kick(p, dx, dy, power, lift)
  local n = math.sqrt(dx * dx + dy * dy)
  if n < 0.01 then dx, dy, n = p.dir, 0, 1 end
  ball.vx, ball.vy, ball.vz = dx / n * power, dy / n * power, lift
  owner, p.cool = nil, 20
  sfx("SND_KICK", 0.5)
end

local function run_to(p, x, y, speed)
  local dx, dy = x - p.x, y - p.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d > 2 then
    p.x, p.y = p.x + dx / d * math.min(speed, d), p.y + dy / d * math.min(speed, d)
    if math.abs(dx) > 1 then p.dir = dx > 0 and 1 or -1 end
    return true
  end
  return false
end

local function goal_of(team) return team == 1 and right(GOAL_Y) or left(GOAL_Y) end -- where a team scores

local function think(p, me) -- one footballer's tick: the player's own, or the console's
  p.t = p.t + 1
  if p.cool > 0 then p.cool = p.cool - 1 end
  local moving = false
  if p.keeper then -- along his line, after the ball; it is his when it comes near
    local gy = math.max(MOUTH[1] - 10, math.min(MOUTH[2] + 10, ball.y))
    moving = run_to(p, p.team == 1 and left(gy) + 18 or right(gy) - 18, gy, 1.8)
    if not owner and dist(p, ball) < 22 and ball.z < 30 and p.cool == 0 then -- caught, then thrown up the pitch
      kick(p, p.team == 1 and 1 or -1, (math.random() - 0.5) * 0.8, 5.5, 3)
    end
  elseif p == me then
    local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
    local dy = (btn("down") and 1 or 0) - (btn("up") and 1 or 0)
    if dx ~= 0 or dy ~= 0 then
      local n = math.sqrt(dx * dx + dy * dy)
      p.x, p.y, moving = p.x + dx / n * 2.4, p.y + dy / n * 2.4, true
      if dx ~= 0 then p.dir = dx end
    end
    if owner == p and btnp("a") then -- that way, or at the goal when standing
      if dx == 0 and dy == 0 then kick(p, goal_of(1) - p.x, GOAL_Y - p.y, 7.5, 2.5)
      else kick(p, dx, dy, 6.5, 1.5) end
    end
  elseif p == front[p.team] then -- the console's nearest: to the ball, then at the goal
    if owner == p then
      local gx, gy = goal_of(p.team), GOAL_Y + math.sin(p.t / 30) * 25
      moving = run_to(p, gx, gy, 1.9)
      if math.abs(p.x - gx) < 230 and p.cool == 0 then kick(p, gx - p.x, gy - p.y, 7, 2.5) end
    else
      moving = run_to(p, ball.x, ball.y, 2.1)
    end
  else -- the others: to their places, which move with the ball
    local x, y = spot(p.team, p.k)
    moving = run_to(p, x, y, 1.4)
  end
  p.y = math.max(TOP, math.min(BOTTOM, p.y))
  p.x = math.max(left(p.y) - 20, math.min(right(p.y) + 20, p.x))
  p.frame = moving and (p.t // 5) % 5 or 1
  if not owner and p.cool == 0 and ball.z < 12 and dist(p, ball) < 14 then owner = p end -- the ball at his feet
end

local function update_ball()
  if owner then -- in front of the feet of whoever has it
    ball.x, ball.y, ball.z, ball.vx, ball.vy, ball.vz = owner.x + owner.dir * 12, owner.y, 0, 0, 0, 0
    for _, p in ipairs(players) do -- a tackle: one of the others close enough takes it, now and then
      if p.team ~= owner.team and not p.keeper and dist(p, ball) < 12 and math.random() < 0.08 then
        owner, p.cool = p, 0
        sfx("SND_KICK", 0.3)
        break
      end
    end
    return
  end
  ball.x, ball.y, ball.z = ball.x + ball.vx, ball.y + ball.vy, ball.z + ball.vz
  ball.vz = ball.vz - 0.25
  if ball.z <= 0 then ball.z, ball.vz = 0, -ball.vz * 0.45 if ball.vz < 0.8 then ball.vz = 0 end end
  local f = ball.z > 0 and 0.995 or 0.97
  ball.vx, ball.vy = ball.vx * f, ball.vy * f
  if ball.y < TOP or ball.y > BOTTOM then ball.vy = -ball.vy ball.y = math.max(TOP, math.min(BOTTOM, ball.y)) end
  for team, line in ipairs({right(ball.y), left(ball.y)}) do
    local past = team == 1 and ball.x > line or team == 2 and ball.x < line
    if past then
      if ball.y > MOUTH[1] and ball.y < MOUTH[2] and ball.z < BAR then -- a goal
        score[team] = score[team] + 1
        state, timer = "goal", 0
        sfx("SND_GOAL")
        juice.shake(6)
        return
      end
      ball.x, ball.vx = line + (team == 1 and -4 or 4), -ball.vx * 0.4 -- off the line: back in, softly
    end
  end
end

-- ------------------------------------------------------------------ the loop

function _update()
  juice.update()
  timer = timer + 1
  if state == "title" then
    if btnp("a") or btnp("start") then
      score, clock, state = {0, 0}, 0, "play"
      kickoff()
      sfx("SND_WHISTLE")
    end
    return
  end
  if state == "goal" then
    if timer > 120 then kickoff(score[1] > score[2] and 2 or 1) state = "play" sfx("SND_WHISTLE") end
  elseif state == "play" then
    clock = clock + 1
    front[1], front[2] = nearest(1), nearest(2) -- once a tick: each footballer asking would be n times n
    for _, p in ipairs(players) do think(p, not autoplay and front[1] or nil) end
    update_ball()
    if clock >= MATCH then state, timer = "end", 0 sfx("SND_WHISTLE") end
  elseif state == "end" and timer > 90 and btnp("a") then
    state = "title"
  end
  cam_x = math.max(0, math.min(W - 480, cam_x + (ball.x - 240 - cam_x) * 0.12))
  cam_y = math.max(0, math.min(H - 320, cam_y + (ball.y - 200 - cam_y) * 0.12))
end

-- ------------------------------------------------------------------ drawing

local MIRROR = {flip_x = true}
local cast = {}

function _draw()
  local cx, cy = math.floor(cam_x), math.floor(cam_y)
  local ox, oy = juice.offset()
  camera(cx + ox, cy + oy)
  if cx < HALF then img("BG_PITCH", 0, 0) end
  if cx + 480 > HALF then img("BG_PITCH", HALF, 0, MIRROR) end
  rect(HALF - 2, TOP - 4, 4, BOTTOM - TOP + 20, 0xF0F4F0) -- the halfway line (the picture's leans: it is drawn here)
  local n = 0
  for _, p in ipairs(players) do n = n + 1 cast[n] = p end
  for i = n + 1, #cast do cast[i] = nil end
  table.sort(cast, function(a, b) return a.y < b.y end)
  local me = state == "play" and nearest(1)
  local shadowed = false
  for _, p in ipairs(cast) do
    if not shadowed and p.y > ball.y then -- the ball and its shadow among the players, by depth
      circ(ball.x, ball.y, 4, 0x204018)
      circ(ball.x, ball.y - ball.z - 4, 5, 0xFFFFFF) circ(ball.x - 1, ball.y - ball.z - 5, 2, 0x303030)
      shadowed = true
    end
    shade(p.x - 14, p.y - 3, 28, 6)
    if p == me then circ(p.x, p.y + 2, 9, 0xFFE070, false) end
    look.frame, look.flip_x, look.pal = p.frame, p.dir < 0, p.kit
    img("SPR_PLAYER", p.x - (p.dir < 0 and 42 or 30), p.y - 70, look)
  end
  if not shadowed then
    circ(ball.x, ball.y, 4, 0x204018)
    circ(ball.x, ball.y - ball.z - 4, 5, 0xFFFFFF) circ(ball.x - 1, ball.y - ball.z - 5, 2, 0x303030)
  end
  camera()
  rect(104, 6, 272, 26, 0x101018)
  text(string.format("%d - %d", score[1], score[2]), 240, 10, {font = "arcade", scale = 2, align = "center",
                                                               color = 0xFFFFFF})
  rect(110, 10, 18, 18, 0xE03030) rect(352, 10, 18, 18, 0x3060E0)
  local secs = math.max(0, (MATCH - clock) // 60)
  text(string.format("%d:%02d", secs // 60, secs % 60), 240, 36, {font = "arcade", align = "center", color = 0xFFE070,
                                                                  outline = 0x101018})
  if state == "title" then
    text("GOL", 240, 90, {font = "arcade", scale = 5, align = "center", color = 0xFFE070, gradient = 0xFF6020,
                          outline = 0x101018})
    text("DE ORO", 240, 170, {font = "arcade", scale = 2, align = "center", color = 0xFFFFFF, outline = 0x101018})
    if (timer // 30) % 2 == 0 then
      text("PULSA A", 240, 220, {font = "arcade", align = "center", color = 0xFFFFFF, outline = 0x101018})
    end
  elseif state == "goal" then
    text("¡GOL!", 240, 120, {font = "arcade", scale = 5, align = "center", color = 0xFFE070, gradient = 0xFF6020,
                             outline = 0x101018, wave = 3})
  elseif state == "end" then
    text("FINAL", 240, 120, {font = "arcade", scale = 4, align = "center", color = 0xFFFFFF, outline = 0x101018})
  end
  juice.draw()
end
