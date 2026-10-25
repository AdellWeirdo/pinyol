-- playtest adapter for Cerezo (see docs/playtest.md).
-- playtest-gate: win   (tests/playtest_gate.py: the perfect player must finish the game; ctest runs it)
-- perfect(): a player who knows the quest (the 15 milestones, in order) and the map. It reads the game's own cells, flags and entities and
--   walks with a BFS over the real collision (an 8 px grid of hero positions; bushes and cobwebs count as passable and are cut or burnt on the
--   way), steps round the 18 px push of a screen change that would leave him inside a wall (a game bug, bugs/b04), fights with the pala
--   (guards respected, a mould timed), dodges projectiles and Topo Rey's telegraphed attacks, farms cherries for Sardina, shoots the nest,
--   pushes the block, lights the lantern and saves from the menu at each milestone (not when hurt).
-- A human-like bot (tools/playtest_bot.lua) presses what perfect() said some ticks ago: the hero and the dialog cursor are planned for where they
--   WILL be (the presses on their way are known), so the same player plays with a person's lag.
-- It never edits the game: it only wraps W.set/W.show/W.load (to know when the map changed) and Hero.hurt (to log what hurt him: CZ_HURT lines
--   with the screen and the cause), and logs CZ_MS (a milestone and its tick) and CZ_DEATH. CEREZO_OPT (set before this file): trace = true
--   adds CZ_TASK/CZ_POS/CZ_NAV/CZ_IGNORE lines, fight = true CZ_FIGHT.
local C = require("core.const")
local U = require("core.util")
local W = require("core.world")
local E = require("core.ents")
local Game = require("core.game")
local Hero = require("core.hero")
local Dialog = require("core.dialog")
local Cine = require("core.cine")
local Play = require("core.play")
local Menu = require("core.menu")
local Save = require("core.save")
local Areas = require("data.world").areas
local OPT = CEREZO_OPT or {}

local DIRS = U.DIRS
local STEP = 8                       -- grid of hero positions (sprite top-left) the BFS runs on (coarse: the game's script memory is small)
local FACES = {"up", "down", "left", "right"}

-- ------------------------------------------------------------------ bookkeeping
local ver = 0                        -- bumped when the map changes (a cut bush, an opened door, a new area)
for _, name in ipairs({"set", "show", "load"}) do
  local f = W[name]
  W[name] = function(...) ver = ver + 1 return f(...) end
end

local MILESTONES = {
  {"yaya_met", function() return Game.flags.yaya_met end},
  {"tirachinas", function() return Game.items.tirachinas end},
  {"pit1", function() return Game.pits >= 1 end},
  {"pit2", function() return Game.pits >= 2 end},
  {"pit3", function() return Game.pits >= 3 end},
  {"seal_open", function() return Game.flags.seal_open end},
  {"in_raiz", function() return W.aid == "raiz" end},
  {"key1", function() return Game.flags.key1 end},
  {"linterna", function() return Game.items.linterna end},
  {"key2", function() return Game.flags.key2 end},
  {"llave_jefe", function() return Game.flags.got_llave_jefe or Game.bosskeys.raiz end},
  {"boss_seen", function() return Game.flags.topo_intro end},
  {"topo_dead", function() return Game.flags.topo_dead end},
  {"planted", function() return Game.flags.tree_bloomed end},
  {"credits", function() return G.state == "credits" end},
}
local reached, n_reached = {}, 0
local deaths_n, last_state = 0, G.state
local T = 0                           -- ticks seen by the adapter

local function update_milestones()
  T = PT and PT.t or T
  for _, m in ipairs(MILESTONES) do
    if not reached[m[1]] and m[2]() then
      reached[m[1]] = true
      n_reached = n_reached + 1
      log(string.format("CZ_MS %s t=%d n=%d", m[1], T, n_reached))
    end
  end
  if G.state == "gameover" and last_state ~= "gameover" then
    deaths_n = deaths_n + 1
    log(string.format("CZ_DEATH n=%d t=%d", deaths_n, T))
  end
  last_state = G.state
end

local function where()
  if not W.aid then return "none" end
  return W.aid .. "_" .. W.sx .. "_" .. W.sy
end

-- what hurt the hero: the nearest enemy, projectile or boss to the point of the blow
local hurt0 = Hero.hurt
Hero.hurt = function(h, dmg, fx, fy)
  local r = hurt0(h, dmg, fx, fy)
  if r then
    local best, bd = "env", 1e9
    for _, e in ipairs(E.list) do
      if (e.kind == "enemy" or e.kind == "proj" or e.kind == "boss") and not e.dead then
        local d = U.dist(fx or 0, fy or 0, e.x + 8, e.y + 8)
        if d < bd then
          bd = d
          if e.kind == "enemy" then best = e.id
          elseif e.kind == "proj" then best = "proj_" .. tostring(e.frames and e.frames[1] or "?")
          else best = "boss_" .. tostring(e.mode) end
        end
      end
    end
    log(string.format("CZ_HURT where=%s cause=%s hp=%d dmg=%d t=%d", where(), best, Game.hp, dmg, T))
  end
  return r
end

if OPT.trace then
  local Tools = require("core.tools")
  local fire0 = Tools.fire
  Tools.fire = function(h)
    log(string.format("CZ_FIRE t=%d hero=%.1f,%.1f face=%s pinyoles=%d", T, h.x, h.y, h.face, Game.pinyoles))
    return fire0(h)
  end
end

local talks = 0 -- dialogs started (a slow player talking is progress too)
local dstart0 = Dialog.start
Dialog.start = function(...) talks = talks + 1 return dstart0(...) end

-- ------------------------------------------------------------------ the map as the bot sees it
local memo, memo_key = {}, nil
local function cell_class(gx, gy)       -- 0 blocked, 1 free, 2 a bush (solid, cuttable)
  local f = W.cell_flags(gx, gy)
  if not f then return 0 end
  if f.water or f.pit or f.spikes then return 0 end
  if f.solid then
    if f.cut then return 2 end
    if f.burn and Game.items.linterna then return 2 end -- a cobweb: the lit lantern burns it
    return 0
  end
  return 1
end

local solids, avoid_exits, goal_exit = {}, {}, nil   -- goal_exit: the exit the current task is for (the others are walls to the bot)
local function collect_solids()
  solids = {}
  avoid_exits = {}
  if W.area then
    for _, d in ipairs(W.area.things) do
      if d.kind == "exit" and d ~= goal_exit then avoid_exits[#avoid_exits + 1] = {d.cx * 16 + 2, d.cy * 16 + 2} end
    end
  end
  for _, e in ipairs(E.list) do
    if e.solid and not e.dead and e.kind ~= "hero" then
      solids[#solids + 1] = {e.x + (e.hx or 0), e.y + (e.hy or 0), e.hw or 16, e.hh or 16}
    end
  end
end

local function static_class(px, py)
  local key = (py + 64) * 4096 + (px + 64)
  local c = memo[key]
  if c then return c end
  local x0, x1 = math.floor((px + 3) / 16), math.floor((px + 12) / 16)
  local y0, y1 = math.floor((py + 8) / 16), math.floor((py + 14) / 16)
  c = 1
  for gy = y0, y1 do
    for gx = x0, x1 do
      local k = cell_class(gx, gy)
      if k == 0 then c = 0 elseif k == 2 and c == 1 then c = 2 end
    end
  end
  memo[key] = c
  return c
end

local function node_class(px, py)
  local c = static_class(px, py)
  if c == 0 then return 0 end
  for i = 1, #avoid_exits do
    local x = avoid_exits[i]
    if px + 4 < x[1] + 12 and x[1] < px + 12 and py + 9 < x[2] + 12 and x[2] < py + 14 then return 0 end
  end
  for i = 1, #solids do
    local s = solids[i]
    if px + 3 < s[1] + s[3] and s[1] < px + 13 and py + 8 < s[2] + s[4] and s[2] < py + 15 then return 0 end
  end
  return c
end

local function refresh_memo()
  local k = tostring(W.aid) .. ":" .. ver .. (Game.items.linterna and "L" or "")
  if k ~= memo_key then memo, memo_key = {}, k end
  collect_solids()
end

local function area_dims()
  local a = W.area
  return math.ceil(a.gw * 16 / STEP), math.ceil(a.gh * 16 / STEP)
end

local N8 = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1}}

-- Play.update_slide pushes the hero 18 px into the next screen without looking at the map, so a crossing is safe only where that
-- landing is free (else he is left inside a wall: a game bug the perfect player steps round, see bugs/slide_into_wall.script)
local function crossing_ok(ax, ay, bx, by)
  local sax, say = (ax + 8) // 240, (ay + 11) // 144
  local sbx, sby = (bx + 8) // 240, (by + 11) // 144
  if sax == sbx and say == sby then return true end
  local lx, ly = bx, by
  if sbx ~= sax then
    local X = math.max(sax, sbx) * 240
    lx = sbx > sax and X + 10 or X - 27
  elseif sby ~= say then
    local Y = math.max(say, sby) * 144
    ly = sby > say and Y + 7 or Y - 30
  end
  -- (the hero can only stand where the old screen lets him, so the lane is right; a pixel of slack either side is enough)
  if sbx ~= sax then
    return static_class(lx, ly) == 1 and static_class(lx, ly - 1) == 1 and static_class(lx, ly + 1) == 1
  end
  return static_class(lx, ly) == 1 and static_class(lx - 1, ly) == 1 and static_class(lx + 1, ly) == 1
end

-- the distance, in grid steps, from every node to the nearest of the goal nodes (-1: not reached); arrays, to spare memory
local QBUF = {}
local function build_field(goals)
  local GW, GH = area_dims()
  local dist, q, qh, qt = {}, QBUF, 1, 0
  for i = 1, GW * GH do dist[i] = -1 end
  for _, g in ipairs(goals) do
    local k = g[2] * GW + g[1]
    if dist[k + 1] == -1 then dist[k + 1] = 0 qt = qt + 1 q[qt] = k end
  end
  while qh <= qt do
    local k = q[qh]
    qh = qh + 1
    local ix, iy = k % GW, k // GW
    local d = dist[k + 1] + 1
    for i = 1, 8 do
      local dx, dy = N8[i][1], N8[i][2]
      local nx, ny = ix + dx, iy + dy
      if nx >= 0 and ny >= 0 and nx < GW and ny < GH then
        local nk = ny * GW + nx
        if dist[nk + 1] == -1 and node_class(nx * STEP, ny * STEP) ~= 0 and crossing_ok(nx * STEP, ny * STEP, ix * STEP, iy * STEP) then
          if i <= 4 or (node_class((ix + dx) * STEP, iy * STEP) ~= 0 and node_class(ix * STEP, (iy + dy) * STEP) ~= 0
                        and (nx * STEP + 8) // 240 == (ix * STEP + 8) // 240 and (ny * STEP + 11) // 144 == (iy * STEP + 11) // 144) then
            dist[nk + 1] = d
            qt = qt + 1
            q[qt] = nk
          end
        end
      end
    end
  end
  return {dist = dist, GW = GW, GH = GH}
end

local function round(v) return math.floor(v + 0.5) end

-- the point the hero should head for to follow the field `look` nodes ahead; nil when he is not on it
local function dget(field, ix, iy)
  if ix < 0 or iy < 0 or ix >= field.GW or iy >= field.GH then return nil end
  local d = field.dist[iy * field.GW + ix + 1]
  if d == nil or d < 0 then return nil end
  return d
end

local function follow(h, field, look)
  local hsx, hsy = (h.x + 8) // 240, (h.y + 11) // 144
  -- his node: the nearest of the four around him that is in the field and on his own screen (the nearest node may lie over the line
  -- he has not crossed yet)
  local ix, iy, cur, bdist
  local fx, fy = h.x // STEP, h.y // STEP
  for _, cx in ipairs({fx, fx + 1}) do
    for _, cy in ipairs({fy, fy + 1}) do
      if (cx * STEP + 8) // 240 == hsx and (cy * STEP + 11) // 144 == hsy then
        local d = dget(field, cx, cy)
        if d then
          local dd = (cx * STEP - h.x) ^ 2 + (cy * STEP - h.y) ^ 2
          if not bdist or dd < bdist then ix, iy, cur, bdist = cx, cy, d, dd end
        end
      end
    end
  end
  if cur == nil then -- not on a node of the field: the nearest one that is (on his own screen)
    local best, bd
    local rx, ry = round(h.x / STEP), round(h.y / STEP)
    for r = 1, 2 do
      for dy = -r, r do
        for dx = -r, r do
          local d = dget(field, rx + dx, ry + dy)
          if d and ((rx + dx) * STEP + 8) // 240 == hsx and ((ry + dy) * STEP + 11) // 144 == hsy and (not bd or d < bd) then
            best, bd = {rx + dx, ry + dy}, d
          end
        end
      end
      if best then break end
    end
    if not best then return nil end
    ix, iy, cur = best[1], best[2], bd
  end
  if cur == 0 then return ix * STEP, iy * STEP, 0 end
  local lx, ly = ix, iy
  for _ = 1, look do
    local bd, bx, by = dget(field, lx, ly), nil, nil
    for i = 1, 8 do
      local nx, ny = lx + N8[i][1], ly + N8[i][2]
      local d = dget(field, nx, ny)
      if d and d < bd and (i <= 4 or ((nx * STEP + 8) // 240 == (lx * STEP + 8) // 240 and (ny * STEP + 11) // 144 == (ly * STEP + 11) // 144)) then
        bd, bx, by = d, nx, ny
      end
    end
    if not bx then break end
    local crossing = (bx * STEP + 8) // 240 ~= hsx or (by * STEP + 11) // 144 ~= hsy
    if crossing then return lx * STEP, ly * STEP, cur, bx - lx, by - ly end -- the lane node before the line: the caller squares up, then crosses
    lx, ly = bx, by
    if bd == 0 then break end
  end
  return lx * STEP, ly * STEP, cur
end

-- a field to the nodes where pred(px, py) holds, kept (the last three) while nothing it depends on changes
local fcache, forder = {}, {}
local function field_for(key, pred, near)
  refresh_memo()
  local sig = {}
  for i = 1, #solids do sig[#sig + 1] = (solids[i][1] // 4) .. "," .. (solids[i][2] // 4) end
  local full = tostring(W.aid) .. ":" .. ver .. (Game.items.linterna and "L" or "") .. ":" .. key .. ":" .. table.concat(sig, ";")
  local f = fcache[key]
  if f and f.full == full then return f.field, f.n end
  local GW, GH = area_dims()
  local goals = {}
  local x0, y0, x1, y1 = 0, 0, GW - 1, GH - 1
  if near then -- only nodes near the thing can satisfy these predicates
    x0, y0 = math.max(0, (near[1] - 40) // STEP), math.max(0, (near[2] - 40) // STEP)
    x1, y1 = math.min(GW - 1, (near[1] + near[3] + 40) // STEP), math.min(GH - 1, (near[2] + near[4] + 40) // STEP)
  end
  for iy = y0, y1 do
    for ix = x0, x1 do
      if node_class(ix * STEP, iy * STEP) == 1 and pred(ix * STEP, iy * STEP) then goals[#goals + 1] = {ix, iy} end
    end
  end
  local field = #goals > 0 and build_field(goals) or {dist = {}, GW = GW, GH = GH}
  if not fcache[key] then
    forder[#forder + 1] = key
    if #forder > 3 then fcache[table.remove(forder, 1)] = nil end
  end
  fcache[key] = {full = full, field = field, n = #goals}
  return field, #goals
end

-- ------------------------------------------------------------------ hazards and the safe step
local HZ_T = {2, 4, 6, 8, 10, 12, 14, 16, 20, 24}
local hazards = {}                   -- per tick: {t_from, t_to, x, y, w, h, weight}

local function add_hz(hz, t0, t1, x, y, w, h, wt) hz[#hz + 1] = {t0, t1, x, y, w, h, wt} end

local function build_hazards(skip)
  local hz = {}
  for _, e in ipairs(E.list) do
    if not e.dead then
      if e.kind == "proj" then
        local x, y, z, vz = e.x, e.y, e.z or 0, e.vz or 0
        for t = 1, 26 do
          x, y = x + e.vx, y + e.vy
          if e.grav ~= 0 then
            z = z + vz
            vz = vz - e.grav
            if z <= 0 and (e.t + t) > 2 then break end
          end
          if not e.through then
            local f = W.cell_flags(math.floor((x + 4) / 16), math.floor((y + 4) / 16))
            if not f or f.solid then break end
          end
          if e.grav == 0 or z < 6 then add_hz(hz, t, t, x - 2, y - 2, e.size + 4, e.size + 4, 100) end
          if e.t + t >= e.life then break end
        end
      elseif e.kind == "enemy" and not e.hidden and (e.k.dmg or 1) ~= 0 then
        local bx, by, bw, bh = e.x + (e.bx or 0), e.y + (e.by or 0), e.bw or 16, e.bh or 16
        if e ~= skip then add_hz(hz, 0, 40, bx - 3, by - 3, bw + 6, bh + 6, 12) end
        if e.mode == "charge" or e.mode == "ready" then
          local d = DIRS[e.face or "down"]
          for t = 1, 40, 4 do
            local k = t * 2.6
            add_hz(hz, t, t + 4, bx + d[1] * k - 3, by + d[2] * k - 3, bw + 6, bh + 6, 60)
          end
        elseif e.id == "cuervo" and e.mode == "dive" then
          for t = 1, 24, 3 do add_hz(hz, t, t + 3, bx + e.vx * t - 3, by + e.vy * t - 3, bw + 6, bh + 6, 40) end
        end
      elseif e.kind == "boss" then
        if e.mode == "erupt_wind" and e.tx then
          local left = math.floor(60 * (e.hp <= 6 and 0.75 or 1)) - e.t
          if left > -4 then add_hz(hz, math.max(0, left - 2), math.max(2, left + 6), e.tx - 6, e.ty + 2, 44, 34, 200) end
        end
        if e.drops then
          for _, d in ipairs(e.drops) do
            local left = 50 - d.t
            if left >= -2 then add_hz(hz, math.max(0, left - 2), math.max(2, left + 4), d.x - 12, d.y - 12, 24, 24, 200) end
          end
        end
      end
    end
  end
  return hz
end

local SP = Hero.SPEED
local CANDS = {{0, 0}, {1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1}}

-- of the nine moves, the one that keeps clear of the hazards and stays closest to the wanted (dx, dy)
local held_back, bypass = 0, 0 -- ticks the hazards have kept him from a wanted move; ticks left of walking through them regardless
local function safe_move(h, wdx, wdy)
  if bypass > 0 then bypass = bypass - 1 return wdx, wdy end
  if h.inv > 12 or #hazards == 0 then return wdx, wdy end
  refresh_memo()
  local best, bdx, bdy
  for _, c in ipairs(CANDS) do
    local dx, dy = c[1], c[2]
    local sp = (dx ~= 0 and dy ~= 0) and SP * 0.75 or SP
    local cost = 0
    if dx ~= wdx or dy ~= wdy then cost = cost + 2 end
    local px, py = h.x, h.y
    for _, t in ipairs(HZ_T) do
      local nx, ny = h.x + dx * sp * t, h.y + dy * sp * t
      if (dx ~= 0 or dy ~= 0) and node_class(round(nx), round(ny)) == 0 then
        nx, ny = px, py
      end
      px, py = nx, ny
      local hx, hy, hw, hh = nx + 4, ny + 5, 8, 10
      for i = 1, #hazards do
        local z = hazards[i]
        if t >= z[1] - 1 and t <= z[2] + 1 and hx < z[3] + z[5] and z[3] < hx + hw and hy < z[4] + z[6] and z[4] < hy + hh then
          cost = cost + z[7]
        end
      end
    end
    if not best or cost < best then best, bdx, bdy = cost, dx, dy end
  end
  if (wdx ~= 0 or wdy ~= 0) and bdx == 0 and bdy == 0 then
    held_back = held_back + 1
    if held_back > 40 then held_back, bypass = 0, 60 end -- a stand-off with a shooter: go through it, a hit is the price
  end
  return bdx, bdy
end

-- ------------------------------------------------------------------ small helpers on the game
local function ebox(e) return e.x + (e.bx or 0), e.y + (e.by or 0), e.bw or 16, e.bh or 16 end
local function ecenter(e) local x, y, w, h = ebox(e) return x + w / 2, y + h / 2 end

local function enemies(filter)
  local out = {}
  for _, e in ipairs(E.list) do
    if not e.dead and (e.kind == "enemy" or e.kind == "boss") and e.team == "enemy" and e.id ~= "oruga_body" and (not filter or filter(e)) then
      out[#out + 1] = e
    end
  end
  return out
end

local function pala_hits(hx, hy, face, e)
  local d = DIRS[face]
  local cx, cy = hx + 8 + d[1] * 12, hy + 9 + d[2] * 12
  local bx, by, bw, bh = ebox(e)
  return U.overlap(cx - 7, cy - 7, 14, 14, bx, by, bw, bh)
end

-- would an A press at (px, py) facing `face` talk to / read / open something instead of swinging?
local function interact_blocks(px, py, face)
  local d = DIRS[face]
  local fx, fy = px + 8 + d[1] * 10, py + 11 + d[2] * 10
  for _, e in ipairs(E.list) do
    if e.interact and not e.dead then
      local bx, by = e.ix or (e.x + (e.hx or 0)), e.iy or (e.y + (e.hy or 0))
      local bw, bh = e.iw or e.hw or 16, e.ih or e.hh or 16
      if U.overlap(fx - 6, fy - 6, 12, 12, bx, by, bw, bh) then return true end
    end
  end
  return false
end

local function can_hurt(e, face)
  if e.dead or e.hidden or e.ranged_only then return false end
  if e.kind == "boss" then return e.mode == "dizzy" end
  if e.k and e.k.guard and e.k.guard(e, face) then return false end
  return true
end

local function hurtable(e)
  return can_hurt(e, "up") or can_hurt(e, "down") or can_hurt(e, "left") or can_hurt(e, "right")
end

function F_ammo() return Game.pinyoles < 4 and Game.cherries >= 8 and not Game.flags.pit_nest end

-- ------------------------------------------------------------------ dialogs
local function choice_index(s)
  local want_heal = Game.hp < Game.maxhp - 1 and Game.cherries >= 15
  local want_ammo = F_ammo()
  for i, c in ipairs(s.choices_) do
    local t = (c.text or ""):lower()
    if want_ammo and t:find("pinyoles", 1, true) then return i end
    if want_heal and t:find("zumo", 1, true) then return i end
  end
  for i, c in ipairs(s.choices_) do
    local t = (c.text or ""):lower()
    if t:find("nada", 1, true) then return i end
  end
  return 1
end

-- (a human-like bot presses what was said `delay` ticks ago: the choice cursor is judged where it WILL be, counting the presses on their way)
local dlg_delay = 0
if PT_CFG and PT_CFG.mode == "human" then dlg_delay = math.floor(30 - 25 * (PT_CFG.skill or 0.5) + 0.5) end
local dq = {}
local function dialog_intent(pt)
  local s = Dialog.story
  local out = {}
  if s and s.choices_ then
    local n = #s.choices_
    local i = choice_index(s)
    local pending = 0
    for k = pt.t - dlg_delay, pt.t - 1 do pending = pending + (dq[k] or 0) end
    local sel = (s.sel - 1 + pending) % n + 1
    if sel ~= i then
      local down = (i - sel) % n
      if pt.t % 2 == 0 then
        local step = down <= n - down and 1 or -1
        out[step == 1 and "down" or "up"] = true
        dq[pt.t] = step
      end
    else
      out.a = pt.t % 4 == 0
      if OPT.trace and pt.t % 4 == 0 then log(string.format("CZ_CHOICE t=%d want=%d sel=%d pending=%d text=%s", pt.t, i, s.sel, pending, tostring(s.choices_[s.sel] and s.choices_[s.sel].text))) end
    end
    dq[pt.t - 80] = nil
    return out
  end
  out.a = pt.t % 5 < 2
  return out
end

-- ------------------------------------------------------------------ the quest
local function F(name) return Game.flags[name] end

local function things_of(aid, kind, filter)
  local out = {}
  for _, d in ipairs(Areas[aid].things) do
    if d.kind == kind and (not filter or filter(d)) then out[#out + 1] = d end
  end
  return out
end

local function exit_to(from, to)
  for _, d in ipairs(Areas[from].things) do if d.kind == "exit" and d.to == to then return d end end
end

-- the box an A press can reach for a thing of the map (its live entity when it has one)
local function interact_box(def)
  for _, e in ipairs(E.list) do
    if not e.dead and e.interact and (e.def == def or (e.kind ~= "npc" and e.x == def.cx * 16 and e.y == def.cy * 16)) then
      return e.ix or (e.x + (e.hx or 0)), e.iy or (e.y + (e.hy or 0)), e.iw or e.hw or 16, e.ih or e.hh or 16, e
    end
  end
  if def.kind == "npc" then
    local r = def.reach or 0
    return def.cx * 16 - r, def.cy * 16 - 4 - r, 16 + 2 * r, 16 + 2 * r
  end
  if def.kind == "plant" then return def.cx * 16, def.cy * 16, def.w * 16, def.h * 16 end
  return def.cx * 16, def.cy * 16, 16, 16
end

local function front_point(px, py, face, reach)
  local d = DIRS[face]
  return px + 8 + d[1] * (reach or 10), py + 11 + d[2] * (reach or 10)
end

-- which thing an A press would answer from (px, py) facing `face`: the nearest to the point he looks at, as core/interact.lua picks it
local function interact_best(px, py, face)
  local d = DIRS[face]
  local fx, fy = px + 8 + d[1] * 10, py + 11 + d[2] * 10
  local best, bd
  for _, e in ipairs(E.list) do
    if e.interact and not e.dead then
      local bx, by = e.ix or (e.x + (e.hx or 0)), e.iy or (e.y + (e.hy or 0))
      local bw, bh = e.iw or e.hw or 16, e.ih or e.hh or 16
      if U.overlap(fx - 6, fy - 6, 12, 12, bx, by, bw, bh) then
        local dd = U.dist(fx, fy, bx + bw / 2, by + bh / 2)
        if not bd or dd < bd then best, bd = e, dd end
      end
    end
  end
  return best
end

local function T_interact(def, name)
  local bx, by, bw, bh, ent = interact_box(def)
  local t = {k = "interact", key = "int:" .. def.kind .. ":" .. def.cx .. "," .. def.cy .. ":" .. (bx // 4) .. "," .. (by // 4),
             near = {bx, by, bw, bh}, press = "a", name = name or ("talk " .. tostring(def.id or def.kind))}
  t.spot = function(px, py, face)
    local fx, fy = front_point(px, py, face, 10)
    if not U.overlap(fx - 6, fy - 6, 12, 12, bx, by, bw, bh) then return false end
    if ent then return interact_best(px, py, face) == ent end -- the thing is here: it must be the one that answers
    return true
  end
  return t
end

local function T_cell(gx, gy, mode, name) -- cut or dig a cell: stand where the pala or the dig reaches it
  local t = {k = "cell", key = "cell:" .. mode .. ":" .. gx .. "," .. gy, near = {gx * 16, gy * 16, 16, 16}, press = "a", name = name or mode}
  t.spot = function(px, py, face)
    if interact_blocks(px, py, face) then return false end -- A would read the sign / open the chest instead of using the pala
    if mode == "dig" then
      local fx, fy = front_point(px, py, face, 10)
      return math.floor(fx / 16) == gx and math.floor(fy / 16) == gy
    end
    local d = DIRS[face]
    local cx, cy = px + 8 + d[1] * 12, py + 9 + d[2] * 12
    return U.overlap(cx - 7, cy - 7, 14, 14, gx * 16 + 2, gy * 16 + 2, 12, 12)
  end
  return t
end

local function T_exit(def)
  local ex, ey = def.cx * 16, def.cy * 16
  local t = {k = "exit", key = "exit:" .. def.to .. ":" .. def.cx .. "," .. def.cy, near = {ex, ey, 16, 16}, name = "exit " .. def.to, key_dir = def.dir, exit_def = def}
  t.spot = function(px, py, face)
    return U.overlap(px + 4, py + 9, 8, 5, ex + 2, ey + 2, 12, 12) and (not def.dir or face == def.dir)
  end
  return t
end

local function T_stand(key, x, y, w, h, name) -- be somewhere in a box
  local t = {k = "stand", key = key, near = {x, y, w, h}, name = name}
  t.spot = function(px, py) return px + 8 >= x and px + 8 <= x + w and py + 11 >= y and py + 11 <= y + h end
  return t
end

local function T_shoot(def, e)
  local bx, by, bw, bh = ebox(e)
  local t = {k = "shoot", key = "shoot:" .. def.cx .. "," .. def.cy, near = {bx - 120, by - 120, bw + 240, bh + 240}, press = "b", name = "shoot nest"}
  t.spot = function(px, py, face)
    -- play the shot out the way core/shot.lua does: 3.5 px a tick, dies on a solid cell (checked before the strike), hits the nest's box
    local d = DIRS[face]
    local x, y = px + 4 + d[1] * 8, py + 4 + d[2] * 8
    for _ = 1, 80 do
      x, y = x + d[1] * 3.5, y + d[2] * 3.5
      local f = W.cell_flags(math.floor((x + 4) / 16), math.floor((y + 4) / 16))
      if not f or f.solid then return false end
      if U.overlap(x, y, 8, 8, bx, by, bw, bh) then return true end
    end
    return false
  end
  return t
end

local function pickups()
  local out = {}
  for _, e in ipairs(E.list) do if e.kind == "pickup" and not e.dead and (e.z or 0) < 1 then out[#out + 1] = e end end
  return out
end

local bad_pickups = {}
local function T_pickup(p)
  local t = {k = "pickup", key = "pick:" .. tostring(p.eid), near = {p.x, p.y, 8, 8}, name = "pickup " .. tostring(p.what)}
  t.spot = function(px, py) return U.overlap(p.x, p.y, 8, 8, px + 3, py + 5, 10, 10) end
  return t
end

local function T_touch(e, name) -- stand on a thing that is taken by touch (a key that has fallen, the heart container)
  local t = {k = "pickup", key = "touch:" .. tostring(e.eid), near = {e.x, e.y, 16, 16}, name = name}
  t.spot = function(px, py) return U.overlap(e.x + 2, e.y + 2, 12, 12, px + 4, py + 6, 8, 8) end
  return t
end

-- the cell, on the hero's screen, that a pala would cut (a bush or weeds) and is nearest
local function nearest_cuttable(h)
  local a = W.area
  local best, bd
  local hx, hy = h.x + 8, h.y + 12
  for gy = W.sy * C.SH, math.min(a.gh - 1, W.sy * C.SH + C.SH - 1) do
    for gx = W.sx * C.SW, math.min(a.gw - 1, W.sx * C.SW + C.SW - 1) do
      local f = W.cell_flags(gx, gy)
      if f and f.cut then
        local d = U.dist(hx, hy, gx * 16 + 8, gy * 16 + 8)
        if not bd or d < bd then best, bd = {gx, gy}, d end
      end
    end
  end
  return best
end

local function npc_def(aid, id) return things_of(aid, "npc", function(d) return d.id == id end)[1] end

local function go_area(target)
  if W.aid == target then return nil end
  local ex = W.aid ~= "overworld" and exit_to(W.aid, "overworld") or exit_to("overworld", target)
  return T_exit(ex)
end

local bad_cells = {}
-- cherries: the eight buried at the Mirador, the bushes of the screen, then the pests of the first screens, which come back each time
-- the screen is entered (a hunt, out to the next screen and back)
local farm_at = "A"
local hunt_idle = 0
local function farm_task(h)
  if W.aid ~= "overworld" then return go_area("overworld"), "to_ow" end
  if not F("buried_mirador") then
    local d = things_of("overworld", "buried", function(b) return b.flag == "buried_mirador" end)[1]
    local f = W.cell_flags(d.cx, d.cy)
    if f and (f.dig or f.cut) and not bad_cells["cell:" .. d.cx .. "," .. d.cy] then return T_cell(d.cx, d.cy, f.dig and "dig" or "cut", "mirador"), "farm_dig" end
  end
  local best, bd
  local hx, hy = h.x + 8, h.y + 12
  for gy = W.sy * C.SH, math.min(W.area.gh - 1, W.sy * C.SH + C.SH - 1) do
    for gx = W.sx * C.SW, math.min(W.area.gw - 1, W.sx * C.SW + C.SW - 1) do
      local f = W.cell_flags(gx, gy)
      if f and f.cut and not bad_cells[gx .. "," .. gy] then
        local d = U.dist(hx, hy, gx * 16 + 8, gy * 16 + 8)
        if not bd or d < bd then best, bd = {gx, gy}, d end
      end
    end
  end
  if best then
    local t = T_cell(best[1], best[2], "cut", "cherries")
    t.bad_key = best[1] .. "," .. best[2]
    return t, "farm"
  end
  local A, B = {7 * 16, 5 * 16}, {7 * 16, 13 * 16}
  if W.sx == 0 and W.sy == 0 then
    if #enemies() == 0 and #pickups() == 0 then farm_at = "B" end
  elseif W.sx == 0 and W.sy == 1 then
    farm_at = "A"
  end
  local gp = farm_at == "A" and A or B
  return {k = "hunt", name = "farm", goto_pos = gp}, "farm_hunt"
end

local function plan(h)
  local hurt_bad = Game.hp <= 2 and Game.maxhp >= 6
  -- pickups on the screen: hearts when hurt, cherries while farming, pinyoles when low
  for _, p in ipairs(pickups()) do
    local want = (p.what == "heart" and Game.hp < Game.maxhp) or (p.what == "cherry" and Game.cherries < 60) or (p.what == "pinyoles" and Game.pinyoles < 14)
    if want and U.dist(h.x + 8, h.y + 10, p.x + 4, p.y + 4) < 70 and p.life - p.t > 60 then return T_pickup(p), "pickup" end
  end
  if not F("yaya_met") then return nil, "intro" end
  for _, e in ipairs(E.list) do
    if e.kind == "keydrop" and e.shown and (e.z or 0) <= 0 and not e.dead then return T_touch(e, "key"), "key_drop" end
  end
  -- heal at Yaya's when low, and before going down to the cave
  local before_cave = F("seal_open") and not F("topo_dead") and W.aid ~= "raiz"
  if (W.aid == "overworld" or W.aid == "casa_yaya") and (hurt_bad or (before_cave and Game.hp < Game.maxhp - 1)) then
    if W.aid == "casa_yaya" then return T_interact(npc_def("casa_yaya", "yaya")), "heal" end
    return go_area("casa_yaya"), "heal_go"
  end
  -- the tirachinas from Bellota
  if not Game.items.tirachinas then
    if W.aid ~= "overworld" then return go_area("overworld"), "to_ow" end
    local bd = npc_def("overworld", "bellota")
    if not F("bellota_quest") then return T_interact(bd), "bellota_ask" end
    if (F("bellota_kills") or 0) < 3 then
      return {k = "hunt", name = "pulgones", only = function(e) return e.def and e.def.quest == "bellota" end, goto_pos = {7 * 16, 5 * 16}}, "bellota_hunt"
    end
    return T_interact(bd), "bellota_reward"
  end
  -- the three golden pits
  if Game.pits < 3 then
    if W.aid ~= "overworld" then return go_area("overworld"), "to_ow" end
    if not F("pit_garden") then
      local d = things_of("overworld", "buried", function(b) return b.flag == "pit_garden" end)[1]
      local f = W.cell_flags(d.cx, d.cy)
      return T_cell(d.cx, d.cy, (f and f.dig) and "dig" or "cut", "garden"), "pit_garden"
    end
    if not F("pit_nest") and Game.pinyoles < 3 then -- ammo: buy ten at Nogal's, or farm for it
      if Game.cherries >= 8 then
        if W.aid ~= "overworld" and W.aid ~= "tienda" then return go_area("overworld"), "to_ow" end
        if W.aid == "overworld" then return go_area("tienda"), "ammo_go" end
        return T_interact(npc_def("tienda", "nogal")), "ammo_buy"
      end
      if W.aid == "tienda" then return go_area("overworld"), "ammo_leave" end
      return farm_task(h)
    end
    if not F("pit_nest") then
      local nd = things_of("overworld", "nest")[1]
      local ne
      for _, e in ipairs(E.list) do if e.kind == "nest" and not e.dead then ne = e end end
      if ne then return T_shoot(nd, ne), "pit_nest" end
      return T_stand("nest_room", 32 * 16, 0, 12 * 16, 3 * 16, "mirador"), "pit_nest_go"
    end
    if not F("sardina_deal") then
      if Game.cherries < 30 then return farm_task(h) end
      return T_interact(npc_def("overworld", "sardina")), "sardina_pay"
    end
  end
  -- the seal
  if not F("seal_open") then
    if W.aid ~= "overworld" then return go_area("overworld"), "to_ow" end
    for _, d in ipairs(things_of("overworld", "socket")) do
      if not F("socket_" .. d.n) then return T_interact(d), "socket" end
    end
    return nil, "seal_wait"
  end
  -- the cave
  if not F("topo_dead") then
    if W.aid ~= "raiz" then return go_area("raiz"), "to_raiz" end
    if not F("key1") then
      local pit_cell = W.cell_flags(22, 22)
      if pit_cell and pit_cell.pit then
        local blk
        for _, e in ipairs(E.list) do if e.kind == "block" and not e.dead then blk = e end end
        if not blk then return T_stand("blockroom", 16 * 15, 18 * 16, 15 * 16, 9 * 16, "to block room"), "to_block" end
        local t = {k = "push", key = "push:" .. blk.x .. "," .. blk.y, near = {blk.x - 16, blk.y - 32, 48, 64}, name = "push block", key_dir = "down"}
        t.spot = function(px, py, face) return face == "down" and math.abs(px - blk.x) <= 4 and py >= blk.y - 16 and py <= blk.y - 15 end
        return t, "push_block"
      end
      return T_interact(things_of("raiz", "chest", function(d) return d.flag == "key1" end)[1]), "key1"
    end
    if not Game.items.linterna then
      local f = W.cell_flags(29, 22)
      if f and f.lock then return T_interact(things_of("raiz", "lock", function(d) return d.cx == 29 and d.cy == 22 end)[1]), "lock_e" end
      return {k = "hunt", name = "east room", goto_pos = {37 * 16, 22 * 16 - 4}}, "linterna"
    end
    if not F("key2") then
      return T_interact(things_of("raiz", "chest", function(d) return d.flag == "key2" end)[1]), "key2"
    end
    if not (F("got_llave_jefe") or Game.bosskeys.raiz) then
      local f = W.cell_flags(37, 9)
      if f and f.lock then return T_interact(things_of("raiz", "lock", function(d) return d.cx == 37 and d.cy == 9 end)[1]), "lock_n" end
      return {k = "hunt", name = "beetle room", goto_pos = {37 * 16, 6 * 16}}, "llave_jefe"
    end
    local fb = W.cell_flags(52, 17)
    if fb and fb.lock then return T_interact(things_of("raiz", "lock", function(d) return d.boss end)[1]), "lock_boss" end
    return {k = "boss", name = "boss"}, "boss"
  end
  -- the plaza: the cherry
  if not F("tree_bloomed") then
    for _, e in ipairs(E.list) do
      if e.kind == "pedestal" and not e.dead then return T_touch(e, "container"), "container" end
    end
    if W.aid ~= "overworld" then return go_area("overworld"), "back_ow" end
    return T_interact(things_of("overworld", "plant")[1]), "plant"
  end
  return nil, "ending"
end

-- ------------------------------------------------------------------ one tick of the perfect player
local turn_lock = nil
local mv = {px = -1, py = -1, still = 0, jig_t = 0, jig = nil, jigs = 0}
local save_seq = nil
local last_saved_n = 0
local last_task_name = ""
local fail_count = {}

-- (dx, dy) in -1..1 toward a point; never a diagonal that would jam on a corner: when both ways are wanted and the diagonal step (or one
-- of its two axes) is not free, only the axis that is free, and the longer one, is used
local function keys_toward(h, tx, ty, th)
  local ex, ey = tx - h.x, ty - h.y
  th = th or 0.8
  local dx = math.abs(ex) > th and (ex > 0 and 1 or -1) or 0
  local dy = math.abs(ey) > th and (ey > 0 and 1 or -1) or 0
  if dx ~= 0 and dy ~= 0 then
    local function ok(a, b) return node_class(round(h.x + a * 2), round(h.y + b * 2)) ~= 0 end
    if not (ok(dx, dy) and ok(dx, 0) and ok(0, dy)) then
      local okx, oky = ok(dx, 0), ok(0, dy)
      if okx and oky then
        if math.abs(ex) >= math.abs(ey) then dy = 0 else dx = 0 end
      elseif okx then dy = 0
      elseif oky then dx = 0
      else dx, dy = 0, 0 end
    end
  end
  return dx, dy
end

local function out_of(dx, dy, extra)
  local o = extra or {}
  if dx < 0 then o.left = true elseif dx > 0 then o.right = true end
  if dy < 0 then o.up = true elseif dy > 0 then o.down = true end
  return o
end

local function navigate(h, t)
  goal_exit = t.exit_def
  for _, f in ipairs(FACES) do -- already somewhere that does the job?
    if t.spot(h.x, h.y, f) then return 0, 0, true end
  end
  local field, n = field_for(t.key, function(px, py)
    for _, f in ipairs(FACES) do if t.spot(px, py, f) then return true end end
    return false
  end, t.near)
  if not field or n == 0 then return 0, 0, false, "nogoal" end
  local tx, ty, cur, cdx, cdy = follow(h, field, 3)
  if not tx then return 0, 0, false, "nofield" end
  if cur == 0 then
    local dx, dy = keys_toward(h, tx, ty, 0.5)
    if dx == 0 and dy == 0 then return 0, 0, true end
    return dx, dy, false
  end
  if cdx and cdy then -- next is a change of screen: be on the lane (the landing was checked for it), then cross in one straight line
    local main_far = (cdx ~= 0 and (tx - h.x) * cdx or (ty - h.y) * cdy) > 6 -- still well short of the lane node (not past it)
    local perp = cdx ~= 0 and (h.y - ty) or (h.x - tx)
    if main_far then
      local dx, dy = keys_toward(h, tx, ty, 1.0)
      return dx, dy, false
    end
    if math.abs(perp) > 1.5 then -- square up on the lane first
      if cdx ~= 0 then return 0, perp > 0 and -1 or 1, false end
      return perp > 0 and -1 or 1, 0, false
    end
    return cdx, cdy, false
  end
  local dx, dy = keys_toward(h, tx, ty)
  return dx, dy, false
end

-- the swing that would hit e from where the hero stands: a face, or nil
local function attack_face(h, e)
  for _, f in ipairs(FACES) do
    if can_hurt(e, f) and pala_hits(h.x, h.y, f, e) and not interact_blocks(h.x, h.y, f) then return f end
  end
end

-- fight: returns an intent table, or nil when there is nothing to fight right now
local embedded_t, embedded_n = 0, 0
local ignore_until, fight_target, at_spot_t = {}, nil, 0
local function ignore(e, ticks, why, h)
  ignore_until[e] = T + ticks
  if OPT.trace then log(string.format("CZ_IGNORE %s %s t=%d hero=%.0f,%.0f enemy=%.0f,%.0f", tostring(e.id), why, T, h and h.x or 0, h and h.y or 0, e.x, e.y)) end
end
local ftrack = {t = 0}
local function fight(h, t, pt)
  fight_target = nil
  local hunting = t and (t.k == "hunt" or t.k == "boss")
  local list = enemies(function(e)
    if e.kind == "boss" then return true end
    if t and t.only and not t.only(e) then return false end
    return true
  end)
  if #list == 0 then return nil end
  local hx, hy = h.x + 8, h.y + 10
  if embedded_t > 3 and not Hero.free(h, h.x, h.y) then
    -- wedged in a door that shut on him (a game bug): he cannot walk, but he can turn, swing and shoot. Swing at what is in reach,
    -- shoot what is in a straight line, turn toward the nearest otherwise
    for _, e in ipairs(list) do
      local f = attack_face(h, e)
      if f then
        if h.face == f then return {a = pt.t % 3 == 0, _swing = true} end
        return out_of(DIRS[f][1], DIRS[f][2], {})
      end
    end
    if Game.pinyoles > 0 then
      for _, e in ipairs(list) do
        if not e.hidden and not e.ranged_only then
          local bx, by, bw, bh = ebox(e)
          for _, f in ipairs(FACES) do
            local d = DIRS[f]
            local x, y = h.x + 4 + d[1] * 8, h.y + 4 + d[2] * 8
            local hit
            for _ = 1, 30 do
              x, y = x + d[1] * 3.5, y + d[2] * 3.5
              local c = W.cell_flags(math.floor((x + 4) / 16), math.floor((y + 4) / 16))
              if not c or c.solid then break end
              if U.overlap(x, y, 8, 8, bx, by, bw, bh) then hit = true break end
            end
            if hit and (not e.k or not e.k.guard or not e.k.guard(e, f)) then
              if h.face == f then return {b = pt.t % 8 == 0, _swing = true} end
              return out_of(d[1], d[2], {})
            end
          end
        end
      end
    end
    local e = list[1]
    if e then return out_of(U.sign(ecenter(e) - hx) , 0, {}) end
    return {}
  end
  local pick, pscore
  for _, e in ipairs(list) do
    local cx, cy = ecenter(e)
    local d = U.dist(hx, hy, cx, cy)
    local reach = hunting and 400 or 70
    if e.kind == "boss" then reach = 400 elseif e.id == "topo" and not hunting then reach = 40 elseif e.id == "moho" and not hunting then reach = 110 end
    if d < reach and not e.hidden and (ignore_until[e] or 0) <= T then
      local score = d + (hurtable(e) and 0 or 60)
      if e.kind == "boss" and e.mode ~= "dizzy" then score = d + 200 end
      if not pscore or score < pscore then pick, pscore = e, score end
    end
  end
  if not pick then
    -- only hidden moles left on a clearing: wait for them to come up, somewhere open
    return nil
  end
  local e = pick
  fight_target = e
  if ftrack.e ~= e or e.hp ~= ftrack.hp then ftrack.e, ftrack.hp, ftrack.t = e, e.hp, 0 end
  ftrack.t = ftrack.t + 1
  if ftrack.t > 700 and e.kind ~= "boss" then ignore(e, 900, 'ftrack', h) ftrack.e = nil return nil end -- no progress on this one: leave it
  if e.id == "moho" and e.cool and e.hurt_t == 0 and not attack_face(h, e) then
    -- it breathes spores down the four lines every 100 ticks of its own clock (frozen while it is hurt): go in only when there is
    -- time to walk there and land the three blows before the next breath; until then wait off the lines
    local ex, ey = ecenter(e)
    local dist = math.max(0, math.sqrt((hx - ex) ^ 2 + (hy - ey) ^ 2) - 15)
    local need = dist / SP + 24
    if need < 90 and e.cool < need then -- (too far for the timing to matter: just walk up)
      ftrack.t = ftrack.t - 1 -- waiting is not a lack of progress
      if math.abs(hx - ex) < 18 or math.abs(hy - ey) < 18 then
        local dx = (math.abs(hx - ex) < math.abs(hy - ey)) and U.sign(hx - ex) or 0
        local dy = (dx == 0) and U.sign(hy - ey) or 0
        return out_of(dx, dy, {})
      end
      return {}
    end
  end
  local f = attack_face(h, e)
  if OPT.fight and T % 10 == 0 then
    log(string.format("CZ_FIGHT t=%d hero=%.0f,%.0f face=%s target=%s at %.0f,%.0f hp=%s cool=%s attack=%s", T, h.x, h.y, h.face, tostring(e.id), e.x, e.y, tostring(e.hp), tostring(e.cool), tostring(f)))
  end
  if f then
    if h.face == f then return {a = pt.t % 3 == 0, _swing = true} end
    return out_of(DIRS[f][1], DIRS[f][2], {})
  end
  local ecx, ecy = ecenter(e)
  if e.kind == "boss" and e.mode ~= "dizzy" then
    -- wait for the daze at a distance, ready to move
    local dx, dy = hx - ecx, hy - ecy
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 56 then return out_of(U.sign(dx), U.sign(dy), {}) end
    if d > 90 then return out_of(U.sign(-dx), U.sign(-dy), {}) end
    return {}
  end
  -- the spot a swing from some side hits from
  refresh_memo()
  local best, bd
  for _, face in ipairs(FACES) do
    if can_hurt(e, face) then
      local d = DIRS[face]
      local px, py = ecx - d[1] * 15 - 8, ecy - d[2] * 15 - 9
      if node_class(round(px / STEP) * STEP, round(py / STEP) * STEP) ~= 0 and not interact_blocks(px, py, face) then
        local dd = U.dist(h.x, h.y, px, py)
        if e.id == "oruga" then -- not into its body: the side the head faces
          local fd = DIRS[e.face or "left"]
          dd = dd + ((d[1] == -fd[1] and d[2] == -fd[2]) and 0 or 40)
        end
        if not bd or dd < bd then best, bd = {px, py, face}, dd end
      end
    end
  end
  if not best then ignore(e, 600, 'nospot', h) return nil end
  local px, py = best[1], best[2]
  local dx, dy = keys_toward(h, px, py, 0.7)
  if math.abs(px - h.x) <= 0.7 and math.abs(py - h.y) <= 0.7 then
    at_spot_t = at_spot_t + 1
    if at_spot_t > 20 then ignore(e, 150, 'at_spot', h) at_spot_t = 0 return nil end -- there, and still no swing: this pest is not for now
    if h.face ~= best[3] then return out_of(DIRS[best[3]][1], DIRS[best[3]][2], {}) end
    return {}
  end
  at_spot_t = 0
  -- a straight step if it is free, else round the wall by a small field
  local nx, ny = h.x + dx * SP, h.y + dy * SP
  if (dx == 0 and dy == 0) or node_class(round(nx), round(ny)) == 0 then
    local field = build_field({{round(px / STEP), round(py / STEP)}})
    local tx, ty = follow(h, field, 3)
    if tx then dx, dy = keys_toward(h, tx, ty) end
  end
  return out_of(dx, dy, {})
end

-- the menu's save: START, up to "save", A, START
local function save_step(pt)
  local s = save_seq
  s.t = s.t + 1
  if s.step == 1 then
    if Menu.open_ then s.step, s.t = 2, 0 return {up = true} end
    if s.t > 20 + 2 * dlg_delay then save_seq = nil end
  elseif s.step == 2 then
    if s.t > 3 + dlg_delay then s.step, s.t = 3, 0 return {a = true} end
  elseif s.step == 3 then
    if s.t > 8 + dlg_delay then s.step, s.t = 4, 0 return {start = true} end
  elseif s.step == 4 then
    if not Menu.open_ or s.t > 20 + 2 * dlg_delay then save_seq = nil last_saved_n = n_reached end
  end
  return {}
end

-- A human-like bot (tools/playtest_bot.lua) presses what perfect() said `delay` ticks ago. The moves still waiting to be executed are
-- known, so the hero is planned for where he WILL be: the same bot, a player who sees ahead as a person does.
local delay = 0
if PT_CFG and PT_CFG.mode == "human" then delay = math.floor(30 - 25 * (PT_CFG.skill or 0.5) + 0.5) end
local outq = {}
local function predicted(h)
  if delay == 0 or not h or h.state ~= "walk" then return h end
  local px, py = h.x, h.y
  refresh_memo()
  for k = T - delay, T - 1 do
    local o = outq[k]
    if o and (o[1] ~= 0 or o[2] ~= 0) then
      local sp = (o[1] ~= 0 and o[2] ~= 0) and SP * 0.75 or SP
      local nx, ny = px + o[1] * sp, py + o[2] * sp
      if node_class(round(nx), round(ny)) ~= 0 then px, py = nx, ny end
    end
  end
  return setmetatable({x = px, y = py}, {__index = h})
end

local function perfect_tick(pt)
  local h = predicted(E.hero)
  if Menu.open_ then
    if save_seq then return save_step(pt) end
    return {start = pt.t % 6 == 0} -- a menu we did not mean to open
  end
  if Dialog.active or Cine.running() then return dialog_intent(pt) end
  if not h or G.state ~= "play" then return {a = pt.t % 5 < 2} end
  if h.state == "item" or h.state == "talk" then return {a = pt.t % 5 < 2} end
  if Play.slide or Play.fading or h.state ~= "walk" then return {} end

  hazards = build_hazards()
  goal_exit = nil
  -- the lantern, lit, burns the cobwebs that close some rooms: put it on B and light it when the screen has any
  if Game.items.linterna and not Game.lantern_on and not save_seq and (W.aid == "raiz") then
    local webs = false
    for gy = W.sy * C.SH, W.sy * C.SH + C.SH - 1 do
      for gx = W.sx * C.SW, W.sx * C.SW + C.SW - 1 do
        local f = W.cell_flags(gx, gy)
        if f and f.burn and f.solid then webs = true end
      end
    end
    if webs then
      if Game.b ~= "linterna" then return {c = pt.t % 8 == 0} end
      return {b = pt.t % 8 == 0}
    end
  end
  local t, why, pk = plan(h)
  if why ~= last_task_name then
    last_task_name = why
    if OPT.trace then log(string.format("CZ_TASK %s t=%d where=%s hp=%d", tostring(why), T, where(), Game.hp)) end
  end

  if save_seq then return save_step(pt) end
  if n_reached > last_saved_n and #enemies() == 0 and #hazards == 0 and why ~= "intro" and Game.hp >= Game.maxhp - 1 then -- (never save hurt: Continue gives back the hearts of the save)
    save_seq = {step = 1, t = 0}
    return {start = true}
  end

  local f_out = fight(h, t, pt)
  if f_out then
    if fight_target then hazards = build_hazards(fight_target) end
    if f_out._swing then
      local sdx, sdy = safe_move(h, 0, 0)
      return out_of(sdx, sdy, {a = f_out.a})
    end
    local wdx = (f_out.right and 1 or 0) - (f_out.left and 1 or 0)
    local wdy = (f_out.down and 1 or 0) - (f_out.up and 1 or 0)
    local sdx, sdy = safe_move(h, wdx, wdy)
    return out_of(sdx, sdy, {})
  end

  if not t then
    local sdx, sdy = safe_move(h, 0, 0)
    return out_of(sdx, sdy, {})
  end

  if t.k == "hunt" or t.k == "boss" then
    -- walk to where the enemies are; hidden moles come to us
    local gp = t.goto_pos
    local tt
    if t.k == "boss" then tt = T_stand("boss_room", 47 * 16, 19 * 16, 12 * 16, 6 * 16, "boss room")
    else tt = T_stand("hunt:" .. t.name .. gp[1] .. "," .. gp[2], gp[1] - 12, gp[2] - 12, 24, 24, t.name) end
    local dx, dy, arrived = navigate(h, tt)
    if arrived then
      dx, dy = 0, 0
      hunt_idle = hunt_idle + 1
      if hunt_idle > 90 and t.name == "farm" then farm_at = farm_at == "A" and "B" or "A" hunt_idle = 0 end -- nothing here to fight: the other screen
    else
      hunt_idle = 0
    end
    local sdx, sdy = safe_move(h, dx, dy)
    return out_of(sdx, sdy, {})
  end

  if t.k == "shoot" and turn_lock and turn_lock.key == t.key and turn_lock.n > 0 then
    -- turning to the nest nudged him off the spot that hits: go on the same way (facing it) to the next one
    turn_lock.n = turn_lock.n - 1
    if h.face == turn_lock.face then
      if t.spot(h.x, h.y, h.face) then turn_lock = nil return {b = pt.t % 6 == 0} end
      return out_of(DIRS[h.face][1], DIRS[h.face][2], {})
    end
  end
  local dx, dy, arrived, why2 = navigate(h, t)
  if why2 == "nogoal" and pk then bad_pickups[pk] = true end
  if (why2 == "nogoal" or why2 == "nofield") and t.bad_key then bad_cells[t.bad_key] = true end
  if why2 and OPT.trace and (fail_count[why2 .. t.key] or 0) < 3 then
    fail_count[why2 .. t.key] = (fail_count[why2 .. t.key] or 0) + 1
    log(string.format("CZ_NAV %s task=%s %s hero=%.0f,%.0f", why2, tostring(t.name), t.key, h.x, h.y))
  end
  if arrived then
    local face_ok
    for _, f in ipairs(FACES) do if h.face == f and t.spot(h.x, h.y, f) then face_ok = true end end
    if face_ok then
      if t.k == "exit" or t.k == "push" then
        local d = t.key_dir or h.face
        return out_of(DIRS[d][1], DIRS[d][2], {})
      elseif t.k == "stand" or t.k == "pickup" then
        return {}
      elseif t.k == "cell" then
        return {a = pt.t % 20 == 0}
      end
      return {[t.press or "a"] = pt.t % 6 == 0}
    end
    for _, f in ipairs(FACES) do
      if t.spot(h.x, h.y, f) then
        if t.k == "shoot" then turn_lock = {key = t.key, face = f, n = 16} end
        return out_of(DIRS[f][1], DIRS[f][2], {})
      end
    end
    return {}
  end
  local sdx, sdy = safe_move(h, dx, dy)
  local o = out_of(sdx, sdy, {})
  if dx ~= 0 or dy ~= 0 then -- a bush in the way: cut it
    local face = (dx ~= 0 and dy ~= 0) and h.face or U.dir_of(dx, dy)
    local fx, fy = Hero.front(h, 10)
    local f = W.cell_flags(math.floor(fx / 16), math.floor(fy / 16))
    if f and f.cut and f.solid and h.face == face and mv.still > 2 then o.a = pt.t % 5 == 0 end
  end
  return o
end

-- track whether the hero moves, and jiggle him when something holds him
local function stuck_filter(out, pt)
  local h = E.hero
  if not h or h.state ~= "walk" then mv.still = 0 return out end
  local wants = out.left or out.right or out.up or out.down
  if wants and h.x == mv.px and h.y == mv.py then mv.still = mv.still + 1 else mv.still = 0 end
  mv.px, mv.py = h.x, h.y
  if mv.jig_t > 0 then
    mv.jig_t = mv.jig_t - 1
    return out_of(mv.jig[1], mv.jig[2], {})
  end
  if mv.still > 24 + delay and not out.a then
    if fight_target then ignore(fight_target, 400, 'stuck_filter', h) end -- a pest we cannot get at (behind bushes)
    mv.jig_t = 10
    local r = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, -1}, {1, -1}, {-1, 1}}
    mv.jig = r[(pt.t // 7) % 8 + 1]
    mv.still = 0
    mv.jigs = mv.jigs + 1
  end
  return out
end

-- last net: never press toward a screen edge whose 18 px push-in would land the hero in a wall (see crossing_ok)
local function guard_crossing(h, out)
  if not h or h.state ~= "walk" or not W.area then return out end
  refresh_memo()
  local cx, cy = h.x + 8, h.y + 11
  local function landing_free(lx, ly, vertical)
    if vertical then return static_class(lx, ly) == 1 and static_class(lx - 1, ly) == 1 and static_class(lx + 1, ly) == 1 end
    return static_class(lx, ly) == 1 and static_class(lx, ly - 1) == 1 and static_class(lx, ly + 1) == 1
  end
  if out.right and W.exists(W.sx + 1, W.sy) and cx + 3 >= W.cam_x + 240 and not landing_free(W.cam_x + 250, h.y, false) then out.right = nil end
  if out.left and W.exists(W.sx - 1, W.sy) and cx - 3 < W.cam_x and not landing_free(W.cam_x - 27, h.y, false) then out.left = nil end
  if out.down and W.exists(W.sx, W.sy + 1) and cy + 3 >= W.cam_y + 144 and not landing_free(h.x, W.cam_y + 151, true) then out.down = nil end
  if out.up and W.exists(W.sx, W.sy - 1) and cy - 3 < W.cam_y and not landing_free(h.x, W.cam_y - 30, true) then out.up = nil end
  return out
end

if OPT.trace then CZ_DBG = {ignore_until = ignore_until, T_stand = T_stand, build_field = build_field, state = function() return farm_at, hunt_idle, fight_target, ftrack end, crossing_ok = crossing_ok, save_seq = function() return save_seq end, interact_blocks = interact_blocks, attack_face = attack_face, enemies = enemies, fight = fight, safe_move = safe_move, build_hazards = build_hazards, perfect_tick = perfect_tick, node_class = node_class, static_class = static_class, refresh_memo = refresh_memo, plan = plan, field_for = field_for, follow = follow, navigate = navigate} end

PLAYTEST = {
  stuck_ticks = 5400,
  playing = function() return G.state == "play" end,
  progress = function() update_milestones() return n_reached end,
  done = function()
    if G.state == "credits" then return "win" end
    if G.state == "gameover" and not Save.exists() then return "lose" end
  end,
  where = where,
  deaths = function() return deaths_n end,
  probe = function()
    local boss_hp = 0
    for _, e in ipairs(E.list) do if e.kind == "boss" and not e.dead then boss_hp = e.hp end end
    local seen = 0
    for _ in pairs(Game.seen) do seen = seen + 1 end
    return {seen = seen, cut = Game.stats.cut, dug = Game.stats.dug, talks = talks, n_hp = Game.hp, n_maxhp = Game.maxhp, cherries = Game.cherries, pinyoles = Game.pinyoles, pits = Game.pits, kills = Game.stats.kills,
            keys = Game.keys.raiz or 0, boss_hp = boss_hp, n_embedded = embedded_n}
  end,
  perfect = function(pt)
    update_milestones()
    local h = E.hero
    if h and h.state == "walk" and not Play.slide and not Play.fading and not Cine.running() and W.area then -- embedded in a wall (a door shut on him)?
      if not Hero.free(h, h.x, h.y) then
        embedded_t = embedded_t + 1
        if embedded_t == 30 then
          embedded_n = embedded_n + 1
          log(string.format("CZ_EMBEDDED where=%s hero=%.0f,%.0f t=%d", where(), h.x, h.y, T))
        end
      else
        embedded_t = 0
      end
    end
    if OPT.trace and pt.t % (OPT.every or 120) == 0 and h then
      log(string.format("CZ_POS t=%d %s hero=%.0f,%.0f face=%s st=%s task=%s hp=%d dlg=%s", pt.t, where(), h.x, h.y, h.face, h.state, last_task_name, Game.hp, tostring(Dialog.active)))
    end
    local ok, out = pcall(perfect_tick, pt)
    if not ok then
      log("CZ_ADAPTER_ERROR " .. tostring(out):sub(1, 300))
      return {}
    end
    out = guard_crossing(h, stuck_filter(out, pt))
    outq[T] = {(out.right and 1 or 0) - (out.left and 1 or 0), (out.down and 1 or 0) - (out.up and 1 or 0)}
    outq[T - 60] = nil
    return out
  end,
}
