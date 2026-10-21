-- lib/lockstep over link, the other console played by the test (tests/lockstep.script): the game runs a tick only when
-- everyone's buttons for it are in; mine are sent in frames with the last few again
lockstep = require("lockstep")
ls = lockstep.new({step = 3, delay = 2, history = 4})
started, ran, got, pos = false, 0, {}, {}
function _init() end
function _update()
  if not started then
    if rawlen(link.peers()) > 0 then ls:start(link.peers()) started = true else return end
  end
  local inputs = ls:update(lockstep.buttons())
  if inputs then
    ran = ran + 1
    got = inputs
    for _, id in ipairs(ls.players) do
      pos[id] = (pos[id] or 0) + (lockstep.down(inputs[id], "right") and 1 or 0) - (lockstep.down(inputs[id], "left") and 1 or 0)
    end
  end
end
function _draw() cls(0) end
