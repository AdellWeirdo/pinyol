-- run: what has happened in the game being played (it starts again with each try): the score, the stage, the parts taken...
local R = {}

function R.reset(hero)
  R.hero = hero
  R.alt = R.alt or false
  R.score = 0
  R.stage = 1
  R.kills = 0
  R.parts = 0
  R.parts_kinds = {}
  R.specials = 0
  R.throws = 0
  R.props = 0
  R.deaths = 0
  R.continues = 0
  R.t = 0
  R.boss_dead = false
end

function R.add(n) R.score = R.score + n end

R.reset("vera")

return R
