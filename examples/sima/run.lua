-- run: one descent into the chasm, by turns. The hero acts (a step, a blow against what is in the way, a rest, a potion) and then every
-- monster that has seen it acts: one distance field from the hero over the floor (grid:distances, in C) and each walks down it, the bats
-- half the time anywhere. What the hero sees is a circle of six cells cut by the walls; what it has seen stays on the map. Nothing drawn
-- here: play.lua shows what run says happened.
local D = require("dungeon")

local R = {}
R.SIGHT = 6
R.HERO_HP, R.HERO_HIT, R.POTION, R.REGEN = 20, {3, 5}, 8, 8 -- the hero's blow; a potion's heal; a point back every REGEN turns
R.KINDS = {
  rata = {hp = 4, hit = {1, 2}, name = "la rata"},
  murcielago = {hp = 3, hit = {1, 2}, name = "el murciélago", erratic = true},
  esqueleto = {hp = 9, hit = {2, 4}, name = "el esqueleto"},
}
R.DIRS = {up = {0, -1}, down = {0, 1}, left = {-1, 0}, right = {1, 0}}

local key = D.key

function R.say(r, text)
  r.log[#r.log + 1] = text
  if #r.log > 3 then table.remove(r.log, 1) end
end

-- The rays of sight, worked out once for a radius: for each cell of the circle (as an offset from the hero), the cells a straight line
-- to it crosses (Bresenham), the hero's own and the cell's left out. Measured on the console, doing that arithmetic every turn cost 8 ms
-- a look; walking the lists costs a fraction of it.
local rays = {}
local function rays_for(rad)
  if rays[rad] then return rays[rad] end
  local list = {}
  for ty = -rad, rad do
    for tx = -rad, rad do
      if tx * tx + ty * ty <= rad * rad + rad and (tx ~= 0 or ty ~= 0) then
        local between, x, y = {}, 0, 0
        local dx, dy, sx, sy = math.abs(tx), -math.abs(ty), tx > 0 and 1 or -1, ty > 0 and 1 or -1
        local err = dx + dy
        while true do
          local e2 = 2 * err
          if e2 >= dy then err = err + dy x = x + sx end
          if e2 <= dx then err = err + dx y = y + sy end
          if x == tx and y == ty then break end
          between[#between + 1] = y * D.W + x -- (as a step in the cells' array)
        end
        list[#list + 1] = {tx, ty, between}
      end
    end
  end
  rays[rad] = list
  return list
end

-- the cells seen from (hx, hy): within the circle, with no wall between (a wall itself is seen)
function R.fov(d, hx, hy, rad)
  local here = key(hx, hy)
  local vis, cells, W, H = {[here] = true}, d.cells, D.W, D.H
  for _, ray in ipairs(rays_for(rad)) do
    local x, y = hx + ray[1], hy + ray[2]
    if x >= 0 and y >= 0 and x < W and y < H then
      local clear, between = true, ray[3]
      for i = 1, #between do -- (inside the circle a crossed cell is never off the floor's edge when its target is not)
        if cells[here + between[i]] == D.WALL then clear = false break end
      end
      if clear then vis[here + ray[2] * W + ray[1]] = true end
    end
  end
  return vis
end

local function look(r)
  r.was_visible = r.visible or {}
  r.visible = R.fov(r.d, r.hero.x, r.hero.y, R.SIGHT)
  for k in pairs(r.visible) do r.seen[k] = true end
end

function R.monster_at(r, x, y)
  for _, m in ipairs(r.monsters) do if m.x == x and m.y == y then return m end end
end

function R.descend(r)
  r.floor = r.floor + 1
  local d = D.generate(r.seed, r.floor)
  r.d, r.seen, r.monsters, r.items, r.visible = d, {}, {}, {}, nil
  r.hero.x, r.hero.y = d.start[1], d.start[2]
  for _, m in ipairs(d.monsters) do
    r.monsters[#r.monsters + 1] = {kind = m.kind, x = m.x, y = m.y, hp = R.KINDS[m.kind].hp, awake = false}
  end
  for _, it in ipairs(d.items) do r.items[#r.items + 1] = {kind = it.kind, x = it.x, y = it.y} end
  r.grid = grid(D.W, D.H, 0) -- all wall, and only the open cells set (a quarter of them: on the console each call counts)
  for i, c in ipairs(d.cells) do if c ~= D.WALL then r.grid:set((i - 1) % D.W, (i - 1) // D.W, 1) end end
  look(r)
  R.say(r, "Piso " .. r.floor .. " de " .. D.FLOORS)
end

function R.new(seed)
  local r = {seed = seed, floor = 0, turns = 0, log = {}, dead = false, won = false, kills = 0,
             hero = {hp = R.HERO_HP, max = R.HERO_HP, potions = 1, gold = 0}}
  R.descend(r)
  return r
end

local function pick_up(r)
  local h = r.hero
  for i, it in ipairs(r.items) do
    if it.x == h.x and it.y == h.y then
      table.remove(r.items, i)
      if it.kind == "pocion" then
        h.potions = h.potions + 1
        R.say(r, "Una poción (B para beberla)")
      else
        local n = math.random(5, 15) + 5 * r.floor
        h.gold = h.gold + n
        R.say(r, n .. " monedas de oro")
      end
      return
    end
  end
end

-- the monsters' half of a turn (play.lua does it a tick after the hero's, so neither half takes a whole frame on the console)
function R.monsters_act(r)
  local h = r.hero
  local dist = r.grid:distances(h.x, h.y)
  for _, m in ipairs(r.monsters) do
    local kind = R.KINDS[m.kind]
    if r.visible[key(m.x, m.y)] then m.awake = true end
    if m.awake and not r.dead then
      if math.abs(m.x - h.x) + math.abs(m.y - h.y) == 1 then
        local n = math.random(kind.hit[1], kind.hit[2])
        h.hp = h.hp - n
        R.say(r, "Te muerde " .. kind.name .. " (" .. n .. ")")
        r.hurt = true
        if h.hp <= 0 then
          h.hp, r.dead = 0, true
          R.say(r, "Te ha vencido " .. kind.name .. " en el piso " .. r.floor)
        end
      else
        local dx, dy
        if kind.erratic and math.random(2) == 1 then
          local s = ({{1, 0}, {-1, 0}, {0, 1}, {0, -1}})[math.random(4)]
          dx, dy = s[1], s[2]
        else
          dx, dy = dist:descend(m.x, m.y)
        end
        local nx, ny = m.x + dx, m.y + dy
        if (dx ~= 0 or dy ~= 0) and D.open(r.d, nx, ny) and not R.monster_at(r, nx, ny) and not (nx == h.x and ny == h.y) then
          m.x, m.y = nx, ny
        end
      end
    end
  end
end

-- The hero's half of a turn: {dir = "up"...}, {rest = true} or {potion = true}. Returns what happened ("move", "hit", "rest",
-- "potion", "stairs", "won") or nil when no turn passed (a wall, no potion, the run over); after "stairs" and "won" the monsters
-- have no half.
function R.hero_acts(r, cmd)
  if r.dead or r.won then return nil end
  local h, what = r.hero, nil
  r.hurt = false
  if cmd.potion then
    if h.potions == 0 then R.say(r, "No te quedan pociones") return nil end
    h.potions, h.hp = h.potions - 1, math.min(h.max, h.hp + R.POTION)
    R.say(r, "Bebes una poción")
    what = "potion"
  elseif cmd.rest then
    what = "rest"
  elseif cmd.dir then
    local s = R.DIRS[cmd.dir]
    local nx, ny = h.x + s[1], h.y + s[2]
    local m = R.monster_at(r, nx, ny)
    if m then
      local n = math.random(R.HERO_HIT[1], R.HERO_HIT[2])
      m.hp, m.awake = m.hp - n, true
      if m.hp <= 0 then
        for i, o in ipairs(r.monsters) do if o == m then table.remove(r.monsters, i) break end end
        r.kills = r.kills + 1
        R.say(r, "Vences a " .. R.KINDS[m.kind].name)
      else
        R.say(r, "Golpeas a " .. R.KINDS[m.kind].name .. " (" .. n .. ")")
      end
      what = "hit"
    elseif D.open(r.d, nx, ny) then
      h.x, h.y = nx, ny
      what = "move"
      pick_up(r)
      local c = D.at(r.d, nx, ny)
      if c == D.STAIRS then
        return "stairs" -- (the next floor is made by R.descend: play.lua does it behind the floor's card)
      elseif c == D.AMULET then
        r.won = true
        R.say(r, "¡El amuleto de la sima!")
        return "won"
      end
    else
      return nil
    end
  else
    return nil
  end
  r.turns = r.turns + 1
  if r.turns % R.REGEN == 0 then h.hp = math.min(h.max, h.hp + 1) end
  look(r) -- (once: what the hero sees does not change while the monsters move)
  return what
end

-- a whole turn: the hero's half, then the monsters' (or, on the stairs, the next floor: "descend")
function R.act(r, cmd)
  local what = R.hero_acts(r, cmd)
  if what == "stairs" then R.descend(r) return "descend" end
  if what and what ~= "won" then R.monsters_act(r) end
  return what
end

return R
