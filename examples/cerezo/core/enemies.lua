-- enemies: the pests of the island, one definition each. `update` runs each tick (and says where the pest goes),
-- `frame` gives the picture, `drops` what it may leave. They are registered in core.enemy.
local U = require("core.util")
local E = require("core.ents")
local Enemy = require("core.enemy")
local Kinds = Enemy.kinds

-- Pulgón: an aphid. It wanders in short hops in a direction it picks now and then, and nibbles whoever is close.
Kinds.pulgon = {
  hp = 2, dmg = 1, drops = {{"cherry", 35}, {"heart", 8}},
  init = function(e) e.hop, e.vx, e.vy = 0, 0, 0 end,
  update = function(e)
    e.hop = e.hop - 1
    if e.hop <= 0 then
      e.hop = 30 + math.random(40)
      if math.random(3) == 1 then
        local h = E.hero
        local dx, dy = h.x - e.x, h.y - e.y
        local len = math.max(1, math.sqrt(dx * dx + dy * dy))
        e.vx, e.vy = dx / len * 0.6, dy / len * 0.6
      else
        local a = math.random() * 6.2832
        e.vx, e.vy = math.cos(a) * 0.5, math.sin(a) * 0.5
      end
    end
    if e.hop > 30 then e.vx, e.vy = 0, 0 end
    Enemy.move(e, e.vx, e.vy)
  end,
  frame = function(e)
    if e.hop > 30 then return "pulgon_0", false end
    return (e.t // 6) % 2 == 0 and "pulgon_1" or "pulgon_2", e.vx > 0
  end,
}

local Proj = require("core.proj")
local W = require("core.world")
local C = require("core.const")

local function toward(e, speed)
  local h = E.hero
  local dx, dy = h.x - e.x, h.y - e.y
  local len = math.max(1, math.sqrt(dx * dx + dy * dy))
  return dx / len * speed, dy / len * speed
end

local function dist_hero(e)
  local h = E.hero
  return U.dist(h.x, h.y, e.x, e.y)
end

-- Caracol: a snail. It crawls along its line (horizontal or vertical, as it was placed), turns at a wall, and its shell
-- turns blows aimed at its front: hit it from the side or the back.
Kinds.caracol = {
  hp = 3, dmg = 1, drops = {{"cherry", 40}, {"pinyoles", 12}, {"heart", 8}},
  init = function(e) e.axis = (e.def.axis == "v") and "v" or "h" e.dir = -1 e.dir_f = e.axis == "h" and "left" or "up" end,
  update = function(e)
    local sp = 0.28
    local dx, dy = 0, 0
    if e.axis == "h" then dx = e.dir * sp else dy = e.dir * sp end
    if not Enemy.move(e, dx, dy) then e.dir = -e.dir end
    if e.axis == "h" then e.dir_f = e.dir < 0 and "left" or "right" else e.dir_f = e.dir < 0 and "up" or "down" end
  end,
  guard = function(e, hit_dir) return U.OPPOSITE[hit_dir] == e.dir_f end,
  frame = function(e) return (e.t // 16) % 2 == 0 and "caracol_0" or "caracol_1", e.dir_f == "right" end,
}

-- Cuervo: a crow. It circles near where it was, and when the hero is close swoops at him, flies on, and comes back.
Kinds.cuervo = {
  hp = 1, dmg = 1, flying = true, drops = {{"cherry", 40}, {"heart", 10}}, mx = 3, my = 3, mw = 10, mh = 10, sort = 25,
  init = function(e) e.ax, e.ay, e.mode, e.mt, e.vx, e.vy = e.x, e.y, "perch", 0, 0, 0 end,
  update = function(e)
    e.mt = e.mt + 1
    if e.mode == "perch" then
      local a = e.t / 40
      local tx, ty = e.ax + math.cos(a) * 20, e.ay + math.sin(a * 1.3) * 10
      Enemy.move(e, (tx - e.x) * 0.05, (ty - e.y) * 0.05)
      if dist_hero(e) < 70 and e.mt > 50 then e.mode, e.mt = "wind", 0 end
    elseif e.mode == "wind" then -- a beat before it dives: it sinks a little
      Enemy.move(e, 0, 0.3)
      if e.mt > 16 then e.mode, e.mt = "dive", 0 e.vx, e.vy = toward(e, 2.1) end
    elseif e.mode == "dive" then
      Enemy.move(e, e.vx, e.vy)
      if e.mt > 46 then e.mode, e.mt = "back", 0 end
    else
      local dx, dy = e.ax - e.x, e.ay - e.y
      local len = math.max(1, math.sqrt(dx * dx + dy * dy))
      Enemy.move(e, dx / len * 1.2, dy / len * 1.2)
      if len < 4 then e.mode, e.mt = "perch", 0 end
    end
  end,
  frame = function(e)
    if e.mode == "dive" then return "cuervo_swoop", e.vx > 0 end
    return (e.t // 7) % 2 == 0 and "cuervo_0" or "cuervo_1", E.hero.x > e.x
  end,
}

-- Avispa: a wasp. Zigzags toward the hero and from afar spits a stinger down the line of his row or column.
Kinds.avispa = {
  hp = 1, dmg = 1, flying = true, drops = {{"cherry", 30}, {"pinyoles", 15}, {"heart", 8}}, mx = 3, my = 3, mw = 10, mh = 10, sort = 25,
  init = function(e) e.phase, e.cool = math.random() * 6, 80 end,
  update = function(e)
    e.cool = e.cool - 1
    local vx, vy = toward(e, 0.55)
    e.phase = e.phase + 0.12
    Enemy.move(e, vx + math.cos(e.phase) * 0.5, vy + math.sin(e.phase) * 0.5)
    local h = E.hero
    if e.cool <= 0 and dist_hero(e) < 90 then
      e.cool = 110
      local dx, dy = h.x - e.x, h.y - e.y
      local d = U.dir_of(dx, dy)
      local v = U.DIRS[d]
      Proj.new({x = e.x + 4, y = e.y + 4, vx = v[1] * 1.6, vy = v[2] * 1.6, frames = {"avispa_2"}, size = 6, through = false})
    end
  end,
  frame = function(e) return (e.t // 3) % 2 == 0 and "avispa_0" or "avispa_1", E.hero.x > e.x end,
}

-- Moho: a mould that does not move. Every second and a half it breathes out spores in the four ways.
Kinds.moho = {
  hp = 3, dmg = 1, drops = {{"cherry", 40}, {"heart", 15}}, 
  init = function(e) e.cool = 60 + math.random(60) end,
  update = function(e)
    e.cool = e.cool - 1
    if e.cool <= 0 then
      e.cool = 100
      for _, d in pairs(U.DIRS) do
        Proj.new({x = e.x + 4, y = e.y + 4, vx = d[1] * 1.1, vy = d[2] * 1.1, frames = {"moho_2"}, size = 6, life = 70})
      end
    end
  end,
  frame = function(e)
    if e.cool < 16 then return "moho_1", false end
    return "moho_0", false
  end,
}

-- Escarabajo: a beetle with a hard shell. When the hero is in its row or column it charges; hit the wall and it is stunned
-- (that is when it can be hurt from any side). Otherwise only its back and sides are soft.
Kinds.escarabajo = {
  hp = 3, dmg = 1, drops = {{"cherry", 45}, {"heart", 10}},
  init = function(e) e.mode, e.mt, e.face = "walk", 0, "down" e.vx, e.vy = 0, 0 end,
  update = function(e)
    e.mt = e.mt + 1
    local h = E.hero
    if e.mode == "walk" then
      if e.mt % 50 == 1 then e.face = ({"up", "down", "left", "right"})[math.random(4)] end
      local d = U.DIRS[e.face]
      if not Enemy.move(e, d[1] * 0.35, d[2] * 0.35) then e.face = ({"up", "down", "left", "right"})[math.random(4)] end
      local dx, dy = h.x - e.x, h.y - e.y
      if (math.abs(dx) < 10 or math.abs(dy) < 10) and dist_hero(e) < 100 and e.mt > 30 then
        e.face = math.abs(dx) < 10 and (dy < 0 and "up" or "down") or (dx < 0 and "left" or "right")
        e.mode, e.mt = "ready", 0
      end
    elseif e.mode == "ready" then
      if e.mt > 22 then e.mode, e.mt = "charge", 0 end
    elseif e.mode == "charge" then
      local d = U.DIRS[e.face]
      if not Enemy.move(e, d[1] * 2.6, d[2] * 2.6) then
        e.mode, e.mt = "stun", 0
        require("core.fx").shake(2, 6)
      end
    elseif e.mode == "stun" then
      if e.mt > 70 then e.mode, e.mt = "walk", 0 end
    end
  end,
  guard = function(e, hit_dir) return e.mode ~= "stun" and U.OPPOSITE[hit_dir] == e.face end,
  frame = function(e)
    if e.mode == "stun" then return "escarabajo_shell", false end
    return (e.t // 8) % 2 == 0 and "escarabajo_0" or "escarabajo_1", e.face == "right"
  end,
}

-- Gran escarabajo: the beetle of the third room, as big as two. It charges along a row or column like its small kin; when it
-- hits a wall it is stunned and soft from every side, and the harder it is hurt the faster it charges.
Kinds.gran_escarabajo = {
  hp = 8, dmg = 1, sheet = "BOSS", sort = 20, bx = 2, by = 4, bw = 28, bh = 26, mx = 3, my = 12, mw = 26, mh = 18,
  drops = {{"heart", 60}},
  init = function(e) e.mode, e.mt, e.face = "walk", 0, "down" end,
  update = function(e)
    e.mt = e.mt + 1
    local h = E.hero
    local rage = (8 - e.hp) * 0.12
    if e.mode == "walk" then
      if e.mt % 60 == 1 then e.face = ({"up", "down", "left", "right"})[math.random(4)] end
      local d = U.DIRS[e.face]
      if not Enemy.move(e, d[1] * 0.4, d[2] * 0.4) then e.face = ({"up", "down", "left", "right"})[math.random(4)] end
      local dx, dy = h.x - e.x, h.y - e.y
      if (math.abs(dx) < 14 or math.abs(dy) < 14) and e.mt > 40 then
        e.face = math.abs(dx) < 14 and (dy < 0 and "up" or "down") or (dx < 0 and "left" or "right")
        e.mode, e.mt = "ready", 0
      end
    elseif e.mode == "ready" then
      if e.mt > 28 - math.floor(rage * 20) then e.mode, e.mt = "charge", 0 end
    elseif e.mode == "charge" then
      local d = U.DIRS[e.face]
      if not Enemy.move(e, d[1] * (2.4 + rage), d[2] * (2.4 + rage)) then
        e.mode, e.mt = "stun", 0
        require("core.fx").shake(3, 10)
      end
    elseif e.mode == "stun" then
      if e.mt > 80 then e.mode, e.mt = "walk", 0 end
    end
  end,
  guard = function(e, hit_dir) return e.mode ~= "stun" and U.OPPOSITE[hit_dir] == e.face end,
  frame = function(e)
    if e.hurt_t > 0 then return "gesc_hurt", false end
    if e.mode == "stun" then return (e.t // 16) % 2 == 0 and "gesc_stun_0" or "gesc_stun_1", false end
    if e.mode == "charge" or e.mode == "ready" then return (e.t // 4) % 2 == 0 and "gesc_charge_0" or "gesc_charge_1", e.face == "right" end
    return (e.t // 10) % 2 == 0 and "gesc_0" or "gesc_1", e.face == "right"
  end,
}

-- Murciélago: a bat. Erratic and quick, it lives in the dark rooms.
Kinds.murcielago = {
  hp = 1, dmg = 1, flying = true, drops = {{"cherry", 30}, {"heart", 10}}, mx = 3, my = 3, mw = 10, mh = 10, sort = 25,
  init = function(e) e.a, e.sp, e.turn = math.random() * 6.28, 0.9, 0 end,
  update = function(e)
    e.turn = e.turn - 1
    if e.turn <= 0 then
      e.turn = 20 + math.random(30)
      local h = E.hero
      local tx = math.atan(h.y - e.y, h.x - e.x)
      e.a = (math.random(3) == 1) and (math.random() * 6.28) or (tx + (math.random() - 0.5) * 1.5)
    end
    Enemy.move(e, math.cos(e.a) * e.sp, math.sin(e.a) * e.sp)
  end,
  frame = function(e) return "murcielago_" .. (e.t // 4) % 3, math.cos(e.a) > 0 end,
}

-- Topo: a mole. It tunnels towards the hero out of sight, pops up beside him, throws a clod of earth in an arc, and digs
-- in again. Only while it is out can it be hurt.
Kinds.topo = {
  hp = 2, dmg = 0, drops = {{"cherry", 50}, {"heart", 10}, {"pinyoles", 15}},
  init = function(e) e.mode, e.mt, e.hidden = "dig", 0, true e.bx, e.by, e.bw, e.bh = 3, 4, 10, 12 end,
  update = function(e)
    e.mt = e.mt + 1
    local h = E.hero
    if e.mode == "dig" then
      e.hidden = true
      local vx, vy = toward(e, 0.8)
      Enemy.move(e, vx, vy)
      if e.mt > 90 and dist_hero(e) < 56 then e.mode, e.mt, e.hidden = "up", 0, false end
    elseif e.mode == "up" then
      if e.mt > 22 then e.mode, e.mt = "throw", 0 end
    elseif e.mode == "throw" then
      if e.mt == 8 then
        local dx, dy = h.x - e.x, h.y - e.y
        local len = math.max(1, math.sqrt(dx * dx + dy * dy))
        Proj.new({x = e.x + 4, y = e.y + 4, vx = dx / len * 1.4, vy = dy / len * 1.4, frames = {"topo_throw"}, gravity = 0.18, vz = 2.4,
                  z = 6, size = 8, life = 60})
      end
      if e.mt > 36 then e.mode, e.mt = "down", 0 end
    elseif e.mode == "down" then
      if e.mt > 14 then e.mode, e.mt, e.hidden = "dig", 0, true end
    end
  end,
  frame = function(e)
    if e.mode == "dig" then return "topo_mound", false end
    if e.mode == "up" or e.mode == "down" then return "topo_up_0", false end
    return "topo_up_1", false
  end,
  draw_hidden = true,
}

-- Oruga: a caterpillar, a head and four round segments in a line. The head crawls along its corridors and turns where it
-- must; the segments follow its path. Only the head can be hurt (the segments turn every blow); all of it dies with it.
Kinds.oruga = {
  hp = 3, dmg = 1, drops = {{"cherry", 50}, {"heart", 12}}, mx = 3, my = 3, mw = 10, mh = 10,
  init = function(e)
    e.face, e.trail, e.turn = e.def.face or "left", {}, 0
    e.segs = {}
    for i = 1, 4 do
      local seg = Enemy.spawn_raw({id = "oruga_body", x = e.x, y = e.y, def_ignore = true})
      seg.head, seg.lag = e, i * 7
      e.segs[i] = seg
    end
  end,
  update = function(e)
    e.turn = e.turn - 1
    local d = U.DIRS[e.face]
    local ok = Enemy.move(e, d[1] * 0.55, d[2] * 0.55)
    if not ok or e.turn <= 0 then
      local opts = {"up", "down", "left", "right"}
      local tries = 0
      repeat
        e.face = opts[math.random(4)]
        tries = tries + 1
        local nd = U.DIRS[e.face]
        local f = W.blocked(e.x + 3 + nd[1] * 6, e.y + 3 + nd[2] * 6, 10, 10)
      until not f or tries > 6
      e.turn = 30 + math.random(40)
    end
    table.insert(e.trail, 1, {e.x, e.y})
    if #e.trail > 40 then e.trail[#e.trail] = nil end
  end,
  on_die = function(e) for _, seg in ipairs(e.segs) do seg.dead = true require("core.fx").poof(seg.x + 8, seg.y + 8) end end,
  frame = function(e) return (e.t // 8) % 2 == 0 and "oruga_head_0" or "oruga_head_1", e.face == "right" end,
}

Kinds.oruga_body = {
  hp = 99, dmg = 1,
  guard = function() return true end,
  update = function(e)
    local h = e.head
    if h.dead then e.dead = true return end
    local p = h.trail[e.lag]
    if p then e.x, e.y = p[1], p[2] end
  end,
  frame = function(e) return (e.t // 8) % 2 == 0 and "oruga_body_0" or "oruga_body_1", false end,
}

return Kinds
