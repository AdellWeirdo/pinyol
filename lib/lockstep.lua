-- lockstep: two or more consoles playing one game in step over link (docs/lua.md, "Playing together"), the way the
-- fighting games and the RTSs did it before rollback: nobody's state is sent, only everyone's buttons, and every
-- console runs the same deterministic game with the same inputs, so they stay identical. Inputs are sampled every
-- tick but sent in frames of `step` ticks (link allows 20 messages a second: 3 ticks a frame), each message carrying
-- the last few frames again in case one was lost, and the game runs a frame only once every player's inputs for it
-- have arrived, `delay` frames after they were pressed (100 ms at the defaults: the lag everyone feels equally).
--
--   local lockstep = require("lockstep")
--   ls = lockstep.new({step = 3, delay = 2, history = 4})
--   ls:start(link.peers())                 -- the players: those heard so far and me, in id order (the same on every console)
--   in _update:
--     local inputs = ls:update(lockstep.buttons())   -- my buttons this tick (a number); nil while a player's are missing
--     if inputs then                                 -- a table: inputs[id] -> that player's buttons this tick, in step
--       for i, id in ipairs(ls.players) do move(i, inputs[id]) end
--     end
--   ls.players (ids), ls.me (my index), ls.tick (ticks run in step), ls.waiting (ticks spent waiting), ls.lag (frames behind)
--   lockstep.down(bits, "a")               -- is that button in a player's bits (up, down, left, right, a, b, c, start, menu)
local M = {}
local L = {}
L.__index = L

local NAMES = {"up", "down", "left", "right", "a", "b", "c", "start", "menu"}
local BIT = {}
for i, n in ipairs(NAMES) do BIT[n] = 1 << (i - 1) end

function M.buttons() -- my buttons this tick as bits
  local b = 0
  for i, n in ipairs(NAMES) do if btn(n) then b = b | (1 << (i - 1)) end end
  return b
end
function M.down(bits, name) return (bits & (BIT[name] or 0)) ~= 0 end

function M.new(opts)
  opts = opts or {}
  return setmetatable({step = opts.step or 3, delay = opts.delay or 2, history = opts.history or 4,
                       players = {}, me = 0, tick = 0, waiting = 0, lag = 0, frames = {}, mine = {}, local_frame = 0,
                       sub = 0, cur = nil, started = false}, L)
end

-- the players: the ids given (the peers heard) and mine, sorted, so every console numbers them the same
function L:start(peers)
  local ids = {link.id()}
  for _, p in ipairs(peers or {}) do ids[#ids + 1] = p end
  table.sort(ids)
  self.players = ids
  for i, id in ipairs(ids) do if id == link.id() then self.me = i end end
  self.frames, self.mine, self.local_frame, self.tick, self.sub, self.cur, self.started = {}, {}, 0, 0, 0, nil, true
  self.pending = {}
  -- the first `delay` frames of everyone are known to be nothing: the game can start at once
  for f = 1, self.delay do
    self.frames[f] = {}
    for _, id in ipairs(ids) do self.frames[f][id] = {} end
    for k = 1, self.step do for _, id in ipairs(ids) do self.frames[f][id][k] = 0 end end
  end
end

function L:receive() -- what the others sent: frames of inputs, the last few in every message
  for from, m in link.recv do
    if type(m) == "table" and type(m.f) == "number" and type(m.i) == "table" then
      local base = math.floor(m.f)
      for k, frame in ipairs(m.i) do -- i[1] is frame f, i[2] frame f - 1, ...
        local fn = base - (k - 1)
        if fn >= 1 and type(frame) == "table" then
          self.frames[fn] = self.frames[fn] or {}
          if not self.frames[fn][from] then
            local bits = {}
            for j = 1, self.step do bits[j] = type(frame[j]) == "number" and math.floor(frame[j]) or 0 end
            self.frames[fn][from] = bits
          end
        end
      end
    end
  end
end

function L:send_mine() -- my latest frames, the newest first
  local list = {}
  for k = 0, self.history - 1 do
    local f = self.mine[self.local_frame - k]
    if not f then break end
    list[#list + 1] = f
  end
  link.send({f = self.local_frame, i = list})
end

function L:ready(f) -- every player's inputs for frame f are here
  local fr = self.frames[f]
  if not fr then return false end
  for _, id in ipairs(self.players) do if not fr[id] then return false end end
  return true
end

-- my input this tick; returns the inputs of the tick the game should run now (or nil: waiting for someone)
function L:update(my_bits)
  if not self.started then self:start({}) end
  -- sample mine into the frame being filled, which stands for `delay` frames ahead; never more than a frame past
  -- the one the game is at: a console waiting for the other keeps its place, so its frames stay within `history`
  -- for one that starts later, and meanwhile it sends its last frames again, so the late one gets them
  local at = math.floor(self.tick / self.step) + 1
  if self.local_frame <= at then
    self.pending[#self.pending + 1] = my_bits or 0
    if #self.pending >= self.step then
      self.local_frame = self.local_frame + 1
      local f = self.local_frame + self.delay
      self.mine[f] = self.pending
      self.frames[f] = self.frames[f] or {}
      self.frames[f][link.id()] = self.pending
      self.pending = {}
      self.local_frame = f
      self:send_mine()
      self.local_frame = self.local_frame - self.delay
    end
  elseif self.waiting % 6 == 0 then
    self:send_mine()
  end
  self:receive()
  -- the frame the game is at
  if not self.cur then
    local next = math.floor(self.tick / self.step) + 1
    if not self:ready(next) then self.waiting = self.waiting + 1 return nil end
    self.cur, self.sub = next, 0
  end
  self.sub = self.sub + 1
  local inputs = {}
  for _, id in ipairs(self.players) do inputs[id] = self.frames[self.cur][id][self.sub] or 0 end
  self.tick = self.tick + 1
  self.lag = self.local_frame + self.delay - self.cur
  if self.sub >= self.step then
    self.frames[self.cur - self.history - self.delay - 2] = nil -- old frames let go
    self.cur = nil
  end
  return inputs
end

return M
