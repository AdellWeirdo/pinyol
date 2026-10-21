-- brain: what a creature does next, decided by scores (utility AI, as Dave Mark and Kevin Dill explained at GDC 2010):
-- each action has a score from the facts of the moment (how hurt am I, how near is he, do I see food), the best one
-- is done, and the creature keeps doing it unless another beats it by a margin, so it does not flicker between two.
-- Cheap: it thinks every few ticks, not every one; the actions' enter/update/exit run every tick it is theirs.
--
--   local brain = require("brain")
--   b = brain.new({
--     flee   = {score = function(e) return e.hp < 3 and 1 or 0 end, enter = function(e) e.anim:play("run") end},
--     attack = {score = function(e) return e.near and 0.8 or 0 end, update = function(e) e:hit() end},
--     wander = {score = 0.1, exit = function(e) end},
--   }, {every = 10, stick = 0.15})
--   in the creature's tick: b:update(e)       -- thinks when it is time, runs the chosen action's update(e)
--   b.current, b.since                         -- the action's name and the ticks it has been doing it
--   b:think(e)                                 -- the best action's name now, without doing anything
--   b:force("flee")                            -- the creature is made to (a cutscene, a hit)
--
-- A score is a number or function(e) -> number; `curve = "quad"`, "sqrt" or a function shapes it (a quadratic curve
-- makes an action that is almost not worth it worth even less).
local M = {}
local B = {}
B.__index = B

local CURVES = {
  linear = function(x) return x end,
  quad = function(x) return x * x end,
  sqrt = function(x) return x < 0 and 0 or math.sqrt(x) end,
}

function M.new(actions, opts)
  opts = opts or {}
  local b = setmetatable({actions = actions, every = opts.every or 6, stick = opts.stick or 0.1, t = 0, since = 0,
                          current = nil}, B)
  return b
end

function B:score(name, e)
  local a = self.actions[name]
  local s = type(a.score) == "function" and a.score(e) or a.score or 0
  if a.curve then s = (type(a.curve) == "function" and a.curve or CURVES[a.curve] or CURVES.linear)(s) end
  return s
end

function B:think(e)
  local best, best_s = nil, -math.huge
  for name in pairs(self.actions) do
    local s = self:score(name, e)
    if s > best_s then best, best_s = name, s end
  end
  if self.current and best ~= self.current then -- the one being done keeps its place unless beaten by the margin
    if best_s - self:score(self.current, e) < self.stick then return self.current end
  end
  return best
end

function B:switch(name, e)
  if self.current and self.actions[self.current].exit then self.actions[self.current].exit(e) end
  self.current, self.since = name, 0
  if name and self.actions[name].enter then self.actions[name].enter(e) end
end

function B:force(name, e)
  assert(self.actions[name], "brain: no action called " .. tostring(name))
  self:switch(name, e)
  self.t = 0
end

function B:update(e)
  self.t = self.t - 1
  if self.t <= 0 or not self.current then
    self.t = self.every
    local want = self:think(e)
    if want ~= self.current then self:switch(want, e) end
  end
  self.since = self.since + 1
  local a = self.current and self.actions[self.current]
  if a and a.update then a.update(e, self.since) end
  return self.current
end

return M
