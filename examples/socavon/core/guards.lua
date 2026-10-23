-- guards: the guardians of a room, each a pest with its own way of moving, drawn from the ENEMY sheet. They are ink only like every sprite:
-- they take the ink of the block they are over (the clash). A guardian kills by touching the miner's inner box.
local R = require("core.room")
local G = {}

G.list = {}
local HURT_W, HURT_H = 10, 11  -- the guardian's inner box, in pixels, and where it sits in the 16x16

-- kind -> frames, how it moves, whether it kills
local KINDS = {
  robot = {frames = {"robot_0", "robot_1"}, axis = "x", step = 8},
  rata = {frames = {"rata_0", "rata_1"}, axis = "x", step = 5},
  vagoneta = {frames = {"vagoneta_0", "vagoneta_1"}, axis = "x", step = 4},
  murcielago = {frames = {"murcielago_0", "murcielago_1", "murcielago_2", "murcielago_1"}, axis = "x", step = 5},
  arana = {frames = {"arana_0", "arana_1"}, axis = "y", step = 10},
  llama = {frames = {"llama_0", "llama_1", "llama_2", "llama_1"}, axis = "y", step = 5},
  ojo = {frames = {"ojo_0", "ojo_1"}, axis = "still"},
}

function G.load(rm)
  G.list = {}
  for _, d in ipairs(rm.guards or {}) do
    local k = KINDS[d.kind]
    local g = {kind = d.kind, k = k, x = d.x * 8, y = d.y * 8, dir = 1, speed = d.speed or 0.6, t = 0, wave = d.wave or 0,
               cx0 = d.x * 8, cy0 = d.y * 8}
    if k.axis == "x" then g.min, g.max = d.min * 8, d.max * 8 else g.min, g.max = d.min * 8, d.max * 8 end
    G.list[#G.list + 1] = g
  end
end

function G.update()
  for _, g in ipairs(G.list) do
    g.t = g.t + 1
    local k = g.k
    if k.axis == "x" then
      g.x = g.x + g.dir * g.speed
      if g.x < g.min then g.x, g.dir = g.min, 1 elseif g.x > g.max then g.x, g.dir = g.max, -1 end
      if g.wave > 0 then g.y = g.cy0 + math.sin(g.t / 22) * g.wave end
    elseif k.axis == "y" then
      g.y = g.y + g.dir * g.speed
      if g.y < g.min then g.y, g.dir = g.min, 1 elseif g.y > g.max then g.y, g.dir = g.max, -1 end
    end
  end
end

-- the eye hurts only when it is open
local function dangerous(g) return g.kind ~= "ojo" or (g.t // 60) % 2 == 1 end

function G.hits(mx, my)
  for _, g in ipairs(G.list) do
    if dangerous(g) and math.abs(g.x - mx) < HURT_W and math.abs(g.y - my) < HURT_H + 2 then return true end
  end
  return false
end

function G.frame(g)
  local k = g.k
  if g.kind == "ojo" then return (g.t // 60) % 2 == 1 and "ojo_1" or "ojo_0" end
  return k.frames[(g.t // k.step) % #k.frames + 1]
end

return G
