-- rollback: two consoles playing one game over link without waiting for each other, the way GGPO and the fighting
-- games of today do it: each runs ahead, guessing that the other keeps pressing what it pressed last; when the
-- other's buttons arrive and differ, the game is put back to the saved state of that tick and run again from there
-- with the truth, within the same tick, so the picture never waits. The game must be deterministic and give its
-- state to be kept and put back (a table of its own, copied: no pointers to things the engine holds).
--
--   local rollback = require("rollback")
--   rb = rollback.new({
--     step = 3, delay = 1, history = 12,            -- ticks a frame, frames of local delay, frames of saved states kept
--     save = function() return {x = x, y = y} end,  -- the whole game state, as a new table
--     load = function(s) x, y = s.x, s.y end,
--     run = function(inputs, tick) move(inputs) end, -- one tick of the game with everyone's buttons (inputs[id] -> bits)
--   })
--   rb:start(link.peers())
--   in _update: rb:update(rollback.buttons())        -- runs this tick (predicting what has not arrived), rolling back when needed
--   rb.tick (ticks run), rb.rolled (ticks run again on the last rollback), rb.rollbacks (times), rb.players, rb.me
--   rollback.buttons(), rollback.down(bits, "a")     -- as lockstep's
--
-- The transport is lockstep's: frames of `step` ticks, each message carrying the last `history` frames again, so a
-- lost message costs nothing; `delay` frames of local delay (0 is allowed: my buttons act at once, the other side
-- rolls back more). A player's buttons for a tick not yet heard are taken as their last known ones.
local lockstep = require("lockstep")
local M = {}
local R = {}
R.__index = R

M.buttons, M.down = lockstep.buttons, lockstep.down

function M.new(opts)
  assert(opts and opts.save and opts.load and opts.run, "rollback.new: save, load and run are needed")
  local step, delay, history = opts.step or 3, opts.delay or 1, opts.history or 12
  return setmetatable({ls = lockstep.new({step = step, delay = delay, history = history}), step = step, delay = delay,
                       history = history, save = opts.save, load = opts.load, run = opts.run,
                       players = {}, me = 0, tick = 0, rolled = 0, rollbacks = 0, saves = {}, used = {}, last = {},
                       started = false}, R)
end

function R:start(peers)
  self.ls:start(peers)
  self.players, self.me = self.ls.players, self.ls.me
  self.tick, self.saves, self.used, self.last, self.started = 0, {}, {}, {}, true
  for _, id in ipairs(self.players) do self.last[id] = 0 end
end

-- a player's buttons at a tick: the frame's if it is here, else the last known (and whether it was known)
function R:input_at(id, tick)
  local f = math.floor(tick / self.step) + 1
  local fr = self.ls.frames[f]
  if fr and fr[id] then return fr[id][tick % self.step + 1] or 0, true end
  return self.last[id], false
end

-- the inputs of a tick, as known now; `known` false when any was a guess
function R:inputs_at(tick)
  local inputs, all = {}, true
  for _, id in ipairs(self.players) do
    local bits, known = self:input_at(id, tick)
    inputs[id] = bits
    if known then self.last[id] = bits else all = false end
  end
  return inputs, all
end

function R:run_tick(tick)
  local inputs, known = self:inputs_at(tick)
  self.saves[tick] = self.save()
  self.used[tick] = {inputs = inputs, known = known}
  self.run(inputs, tick)
end

-- the first tick already run whose guessed inputs the frames now contradict
function R:first_wrong()
  local oldest = self.tick - self.history * self.step
  for t = math.max(0, oldest), self.tick - 1 do
    local u = self.used[t]
    if u and not u.known then
      for _, id in ipairs(self.players) do
        local bits, known = self:input_at(id, t)
        if known and bits ~= u.inputs[id] then return t end
      end
    end
  end
  return nil
end

function R:update(my_bits)
  if not self.started then self:start({}) end
  local ls = self.ls
  -- mine, sampled into the frame being filled and sent as lockstep does; the others' received
  ls.pending[#ls.pending + 1] = my_bits or 0
  if #ls.pending >= self.step then
    local f = ls.local_frame + 1 + self.delay
    ls.mine[f] = ls.pending
    ls.frames[f] = ls.frames[f] or {}
    ls.frames[f][link.id()] = ls.pending
    ls.pending = {}
    ls.local_frame = f
    ls:send_mine()
    ls.local_frame = ls.local_frame - self.delay
  end
  ls:receive()
  -- a frame that proves a guess wrong: back to that tick's state, and the ticks since run again with the truth
  local wrong = self:first_wrong()
  if wrong then
    self.load(self.saves[wrong])
    self.rollbacks, self.rolled = self.rollbacks + 1, self.tick - wrong
    for t = wrong, self.tick - 1 do self:run_tick(t) end
  end
  self:run_tick(self.tick)
  self.tick = self.tick + 1
  local old = self.tick - self.history * self.step - 1
  self.saves[old], self.used[old] = nil, nil
  local of = math.floor(old / self.step) - 1
  if of >= 1 then ls.frames[of] = nil end
end

return M
