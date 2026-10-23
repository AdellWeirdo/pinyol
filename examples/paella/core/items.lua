-- items: what lies on the ground: weapon crates (a spread, a faster rate, a bigger shot), grenades, a shield, an extra life, and the food that is the score of the kitchen. They bob,
-- the chef takes them by walking over them. Enemies and props may leave food.
local C = require("core.const")
local S = require("core.spr")
local Fx = require("core.fx")
local Sound = require("core.sound")
local Run = require("core.run")
local Chef = require("core.chef")
local It = {}

It.list = {}
local FOODS = {"jamon", "cheese", "paella", "tortilla", "melon", "sardine", "orange", "bread", "olive_can", "wine_skin", "churro", "ensaimada"}
local FOOD_SCORE = {jamon = 1000, cheese = 500, paella = 2000, tortilla = 800, melon = 300, sardine = 200, orange = 200, bread = 200, olive_can = 300, wine_skin = 500, churro = 400, ensaimada = 600}

function It.clear() for i = #It.list, 1, -1 do It.list[i] = nil end end

function It.add(kind, x, y, extra)
  local it = {kind = kind, x = x, y = y or C.FLOOR, vy = 0, t = math.random(30), wait = 10, ground = y == nil}
  if extra then for k, v in pairs(extra) do it[k] = v end end
  It.list[#It.list + 1] = it
  return it
end

-- a crate from a freed prisoner: its kind says which upgrade
function It.crate(kind, x) return It.add("crate_" .. kind, x, C.FLOOR - 120, {vy = -2}) end

function It.drop(x, y, from)
  local r = math.random(100)
  if from == "prop" then
    if r < 55 then It.add("food", x, y - 20, {food = FOODS[math.random(#FOODS)], vy = -4}) elseif r < 75 then It.add("ammo", x, y - 20, {vy = -4}) end
  elseif from == "crab" then
    It.add("heart", x, y - 30, {vy = -4})
    It.add("food", x + 30, y - 30, {food = "paella", vy = -5})
  elseif r < 14 then
    It.add("food", x, y - 30, {food = FOODS[math.random(#FOODS)], vy = -4})
  elseif r < 20 then
    It.add("ammo", x, y - 30, {vy = -4})
  end
end

function It.update(chef)
  for i = #It.list, 1, -1 do
    local it = It.list[i]
    it.t = it.t + 1
    if it.wait > 0 then it.wait = it.wait - 1 end
    if it.vy and not it.rest then
      it.vy = it.vy + 0.3
      it.y = it.y + it.vy
      if it.y >= C.FLOOR - 4 then it.y, it.vy, it.rest = C.FLOOR - 4, 0, true end
    end
    if chef.state == "play" and it.wait == 0 and not chef.vehicle then
      local bx, by, bw, bh = Chef.hit_box()
      if it.x > bx - 18 and it.x < bx + bw + 18 and it.y > by - 10 and it.y < by + bh + 20 then
        local k = it.kind
        if k:sub(1, 6) == "crate_" then Chef.pickup_weapon(chef, k:sub(7)) Run.add(300)
        elseif k == "ammo" then chef.grenades = math.min(30, chef.grenades + 10) Sound.play("pickup")
        elseif k == "heart" then chef.lives = chef.lives + 1 Sound.play("pickup") Run.add(500)
        elseif k == "shield" then chef.shield = 1 Sound.play("pickup")
        elseif k == "food" then
          Run.add(FOOD_SCORE[it.food])
          if not Run.foods[it.food] then Run.foods[it.food] = true Run.food_n = Run.food_n + 1 end
          Run.food_eaten = (Run.food_eaten or 0) + 1
          Sound.play("food")
        end
        Fx.add("hit", it.x, it.y - 10)
        table.remove(It.list, i)
      end
    end
    if it.x < (It.cam or 0) - 200 then table.remove(It.list, i) end
  end
end

function It.draw(cam)
  for _, it in ipairs(It.list) do
    local sx = it.x - cam
    if sx > -40 and sx < C.W + 40 then
      local bob = it.rest and math.floor(math.sin(it.t / 10) * 2) or 0
      local k = it.kind
      local frame
      if k == "food" then frame = "food_" .. it.food else frame = k end
      if not S.has("items", frame) then frame = frame .. "_" .. (it.t // 8) % math.max(1, S.n("items", frame)) end
      S.draw("items", frame, sx, it.y + bob, {})
    end
  end
end

return It
