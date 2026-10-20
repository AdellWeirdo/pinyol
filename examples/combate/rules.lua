-- rules: the battle's numbers, with no drawing and nothing kept: the enemies, the party, how hard a hit is, who goes first,
-- what a victory gives. Every function takes what it needs and returns a new table, so main.lua's scenes and the tests use it alike.
local M = {}

M.ENEMIES = {
  slime = {name = "Limo", frame = 0, hp = 18, atk = 5, def = 1, spd = 3, xp = 6},
  bat = {name = "Murciélago", frame = 1, hp = 14, atk = 6, def = 0, spd = 8, xp = 7},
  golem = {name = "Gólem", frame = 2, hp = 40, atk = 9, def = 3, spd = 2, xp = 20},
}
M.ZONES = { -- what the grass of each side of the meadow hides
  west = {"slime", "slime", "bat"},
  east = {"bat", "golem", "slime", "bat"},
}
M.SPELLS = {
  tajo = {name = "Tajo", mp = 3, power = 2.0, magic = false},
  chispa = {name = "Chispa", mp = 4, power = 2.2, magic = true},
}
M.POTION = 15
M.MAX_ENEMIES = 3

function M.new_party()
  return {
    {name = "Aldo", hp = 30, maxhp = 30, mp = 6, maxmp = 6, atk = 8, def = 2, spd = 5, lv = 1, xp = 0, spell = "tajo", sprite = 0},
    {name = "Mara", hp = 22, maxhp = 22, mp = 14, maxmp = 14, atk = 5, def = 1, spd = 6, lv = 1, xp = 0, spell = "chispa", sprite = 1},
  }
end

-- the enemies of one fight: one to three of the zone's kinds, each at full life
function M.encounter(zone, rnd)
  rnd = rnd or math.random
  local kinds, out = M.ZONES[zone] or M.ZONES.west, {}
  for i = 1, rnd(1, M.MAX_ENEMIES) do
    local id = kinds[rnd(1, #kinds)]
    local e = M.ENEMIES[id]
    out[i] = {id = id, name = e.name, frame = e.frame, hp = e.hp, maxhp = e.hp, atk = e.atk, def = e.def, spd = e.spd, xp = e.xp}
  end
  return out
end

-- one hit: attack times the move's power, less the defence (a spell goes through it), a point either way, one at least
function M.damage(atk, def, power, magic, rnd)
  rnd = rnd or math.random
  local base = atk * power - (magic and 0 or def)
  return math.max(1, math.floor(base + rnd(-1, 1)))
end

-- who acts first: faster ones, and the party before the enemies when they are as fast
function M.order(actions)
  local sorted = {table.unpack(actions)}
  table.sort(sorted, function(a, b)
    if a.spd ~= b.spd then return a.spd > b.spd end
    if a.side ~= b.side then return a.side == "party" end
    return a.i < b.i
  end)
  return sorted
end

function M.xp_needed(lv) return 8 * lv end

-- a member after earning xp: the same member, new, with the levels it climbed (their numbers grow)
function M.award(member, xp)
  local m = {}
  for k, v in pairs(member) do m[k] = v end
  m.xp = m.xp + xp
  local gained = 0
  while m.xp >= M.xp_needed(m.lv) do
    m.xp, m.lv, gained = m.xp - M.xp_needed(m.lv), m.lv + 1, gained + 1
    m.maxhp, m.maxmp, m.atk, m.def, m.spd = m.maxhp + 5, m.maxmp + 2, m.atk + 2, m.def + 1, m.spd + 1
    m.hp, m.mp = m.maxhp, m.maxmp -- a level is a night's rest
  end
  return m, gained
end

-- the chance of getting away: a fast party does better than a heavy enemy
function M.flee_chance(party_spd, enemy_spd) return math.max(0.2, math.min(0.9, 0.5 + 0.05 * (party_spd - enemy_spd))) end

return M
