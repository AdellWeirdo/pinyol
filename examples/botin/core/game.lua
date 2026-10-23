-- game: what the player has done over the whole adventure: for each level whether it is done, which pieces of the jewel were found, the best coins and the crown.
-- Kept with `store` (one slot).
local G = {}

G.levels = {}
G.boss_done = false
G.coins_total = 0
G.stats = {kills = 0, broken = 0, deaths = 0}

local function blank()
  return {done = false, jewels = {false, false, false, false}, best = 0, crown = 0}
end

function G.reset()
  G.levels = {}
  for i = 1, 4 do G.levels[i] = blank() end
  G.boss_done = false
  G.coins_total = 0
  G.stats = {kills = 0, broken = 0, deaths = 0}
end

function G.jewel_total()
  local n = 0
  for i = 1, 4 do
    for j = 1, 4 do if G.levels[i].jewels[j] then n = n + 1 end end
  end
  return n
end

-- how many pieces open the boss's door
G.BOSS_NEEDS = 10
function G.boss_open() return G.jewel_total() >= G.BOSS_NEEDS end

-- unlocked: level i is open when the one before is done
function G.open(i) return i == 1 or G.levels[i - 1].done end

function G.finish_level(i, run, crown)
  local L = G.levels[i]
  L.done = true
  for j = 1, 4 do if run.jewels[j] then L.jewels[j] = true end end
  if run.coins > L.best then G.coins_total = G.coins_total + (run.coins - L.best) L.best = run.coins end
  if crown > L.crown then L.crown = crown end
end

function G.snapshot()
  return {levels = G.levels, boss_done = G.boss_done, coins_total = G.coins_total, stats = G.stats}
end

function G.restore(s)
  G.reset()
  if not s then return end
  for i = 1, 4 do
    local l = s.levels and s.levels[i]
    if l then
      G.levels[i] = {done = l.done and true or false, jewels = {l.jewels[1] and true or false, l.jewels[2] and true or false, l.jewels[3] and true or false, l.jewels[4] and true or false},
                     best = l.best or 0, crown = l.crown or 0}
    end
  end
  G.boss_done = s.boss_done and true or false
  G.coins_total = s.coins_total or 0
  G.stats = s.stats or G.stats
end

function G.save() store("save", G.snapshot()) end
function G.exists() return stored("save") ~= nil end
function G.load() G.restore(stored("save")) return stored("save") ~= nil end

G.reset()

return G
