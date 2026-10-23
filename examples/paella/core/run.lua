-- run: what has happened in the mission being played (it starts again with each try): the score, the people freed, the food eaten...
local R = {}

function R.reset(chef)
  R.chef = chef
  R.score = 0
  R.pows = 0
  R.pows_total = 0
  R.foods = {}
  R.food_n = 0
  R.kills = 0
  R.tractor_kills = 0
  R.deaths = 0
  R.t = 0
  R.continues = 0
  R.boss_dead = false
  R.grenade_kills = 0
end

function R.add(n) R.score = R.score + n end

R.reset("estrella")

return R
