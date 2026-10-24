-- items: what lies in the street to pick up: the four exo-parts (hammer fist, spring legs, wrench arm, boiler chest), an oil can that mends, a pocket watch for points.
local C = require("core.const")
local S = require("core.spr")
local Run = require("core.run")
local Sound = require("core.sound")
local Fx = require("core.fx")
local I = {}

I.list = {}
local KINDS = {part_hammer = "hammer", part_springs = "springs", part_wrench = "wrench", part_boiler = "boiler"}
I.PART_NAMES = {"hammer", "springs", "wrench", "boiler"}

function I.clear() for i = #I.list, 1, -1 do I.list[i] = nil end end

function I.add(kind, x, y)
  I.list[#I.list + 1] = {kind = kind, x = x, y = y, z = 40, vz = 3, t = 0}
end

function I.add_part(x, y, which)
  I.add("part_" .. (which or I.PART_NAMES[math.random(#I.PART_NAMES)]), x, y)
end

function I.update(hero, cam)
  for i = #I.list, 1, -1 do
    local it = I.list[i]
    it.t = it.t + 1
    if it.z > 0 or it.vz > 0 then
      it.vz = it.vz - 0.4
      it.z = math.max(0, it.z + it.vz)
      if it.z == 0 then it.vz = 0 end
    end
    local taken = false
    if hero.st ~= "dead" and hero.st ~= "down" and math.abs(hero.x - it.x) < 28 and math.abs(hero.y - it.y) < 18 and hero.z < 30 then
      if KINDS[it.kind] then hero:take_part(KINDS[it.kind]) taken = true
      elseif it.kind == "oil" and hero.hp < hero.max_hp then
        hero.hp = math.min(hero.max_hp, hero.hp + math.floor(hero.max_hp * 0.4))
        Sound.play("oil")
        taken = true
      elseif it.kind == "watch" then Run.add(1000) Sound.play("coin") taken = true end
    end
    if taken then Fx.add("steam", it.x, it.y, 40) table.remove(I.list, i)
    elseif it.t > 1100 or it.x < cam - 150 then table.remove(I.list, i) end
  end
end

function I.collect(out, cam)
  for _, it in ipairs(I.list) do
    out[#out + 1] = {y = it.y, draw = function()
      if it.t > 900 and (it.t // 5) % 2 == 0 then return end
      local bob = it.z > 0 and 0 or math.sin(it.t / 12) * 3
      S.draw("parts", it.kind, it.x - cam, it.y - it.z - 8 - bob, {})
    end}
  end
end

return I
