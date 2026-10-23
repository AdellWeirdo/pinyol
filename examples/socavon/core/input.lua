-- input: the buttons the miner reads. Normally the player's; the title's demo feeds its own (a miner that walks to and fro and jumps),
-- so the same physics play it.
local I = {}

I.feed = nil -- when set, a function(tick) returning a table of the buttons held this tick
local cur, prev = {}, {}
local n = 0

function I.step()
  if not I.feed then return end
  prev, cur = cur, I.feed(n)
  n = n + 1
end

function I.reset() cur, prev, n = {}, {}, 0 end

function I.btn(name)
  if I.feed then return cur[name] or false end
  return btn(name)
end

function I.btnp(name)
  if I.feed then return (cur[name] and not prev[name]) or false end
  return btnp(name)
end

return I
