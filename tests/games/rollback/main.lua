-- lib/rollback over link, the other console played by the test (tests/rollback.script): the game never waits; a late
-- frame that differs from the guess puts the state back and runs the ticks again
rollback = require("rollback")
pos, started, ran = {}, false, 0
rb = rollback.new({
  step = 3, delay = 1, history = 12,
  save = function() local s = {} for id, p in pairs(pos) do s[id] = p end return s end,
  load = function(s) pos = {} for id, p in pairs(s) do pos[id] = p end end,
  run = function(inputs)
    ran = ran + 1
    for _, id in ipairs(rb.players) do
      pos[id] = (pos[id] or 0) + (rollback.down(inputs[id], "right") and 1 or 0) - (rollback.down(inputs[id], "left") and 1 or 0)
    end
  end,
})
function _init() end
function _update()
  if not started then
    if rawlen(link.peers()) > 0 then rb:start(link.peers()) started = true else return end
  end
  rb:update(rollback.buttons())
end
function _draw() cls(0) end
