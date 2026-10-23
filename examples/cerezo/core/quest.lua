-- quest: the few functions a story file calls with [do ...] and [if ...]: what the player has and what happened.
local Game = require("core.game")
local Q = {}

function Q.install()
  function flag(name) return Game.flags[name] end
  function setflag(name, v) Game.flags[name] = v == nil and true or v end
  function has(item) return Game.items[item] == true end
  function cherries() return Game.cherries end
  function pits() return Game.pits end
  function pay(n)
    if Game.cherries >= n then Game.add_cherries(-n) return true end
    return false
  end
  function give(item) -- after the conversation: the pose, the jingle, the message
    require("core.dialog").after(function() require("core.rewards").get(item) end)
  end
  function heal_all() Game.hp = Game.maxhp end
  function sound_(name) require("core.sound").play(name) end
  function pinyoles() return Game.pinyoles end
  function give_pinyoles(n) Game.add_pinyoles(n) end
  function hearts() return Game.maxhp // 2 end
end

return Q
