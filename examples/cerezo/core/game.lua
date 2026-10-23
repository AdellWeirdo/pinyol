-- game: what the player has and what has happened: hearts, money, items, quest flags. It is all one table that is
-- saved whole; nothing else in the game remembers anything between sessions.
local Game = {}

local DEFAULT = {
  hp = 6, maxhp = 6,          -- in halves of a heart: 6 is three hearts
  cherries = 0, pinyoles = 0, max_pinyoles = 20,
  items = {pala = true},      -- what he carries
  b = nil,                    -- the item on B
  flags = {},                 -- quest flags and things done once (a chest opened, an enemy beaten for good)
  keys = {},                  -- small keys held, by dungeon
  bosskeys = {},              -- the boss key, by dungeon
  maps = {},                  -- a dungeon's map and compass, by dungeon
  seen = {},                  -- screens visited: "area:sx,sy"
  pits = 0,                   -- golden pits found
  pieces = 0,                 -- pieces of heart (four make a heart)
  time = 0,                   -- ticks played
  deaths = 0,
  area = "overworld", cx = 7, cy = 5, face = "down",  -- where the last save was
  changes = {},               -- cells changed in each area (cut, dug, opened)
  stats = {cut = 0, kills = 0, dug = 0},
}

local function deep(t)
  local out = {}
  for k, v in pairs(t) do out[k] = type(v) == "table" and deep(v) or v end
  return out
end

function Game.reset()
  for k in pairs(Game) do if type(Game[k]) ~= "function" then Game[k] = nil end end
  for k, v in pairs(deep(DEFAULT)) do Game[k] = v end
end

function Game.has(item) return Game.items[item] == true end

function Game.give(item)
  Game.items[item] = true
  if item == "tirachinas" and not Game.b then Game.b = "tirachinas" end
  if item == "linterna" and not Game.b then Game.b = "linterna" end
end

function Game.flag(name) return Game.flags[name] end
function Game.setflag(name, v) Game.flags[name] = v == nil and true or v end

function Game.heal(n) Game.hp = math.min(Game.maxhp, Game.hp + n) end
function Game.hurt(n) Game.hp = math.max(0, Game.hp - n) end
function Game.add_cherries(n)
  Game.cherries = math.max(0, math.min(999, Game.cherries + n))
  if Game.cherries >= 100 then achieve("ahorrador") end
end
function Game.add_pinyoles(n) Game.pinyoles = math.max(0, math.min(Game.max_pinyoles, Game.pinyoles + n)) end

-- what is kept: everything but the functions
function Game.snapshot()
  local out = {}
  for k, v in pairs(Game) do
    if type(v) ~= "function" then out[k] = type(v) == "table" and deep(v) or v end
  end
  return out
end

function Game.restore(s)
  Game.reset()
  for k, v in pairs(s) do Game[k] = type(v) == "table" and deep(v) or v end
end

Game.reset()
return Game
