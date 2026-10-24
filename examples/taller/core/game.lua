-- game: what is kept between sessions: the best score, which heroes have finished the game, and the last one chosen.
local G = {}

G.best = 0
G.won = {}
G.last = 1

function G.load()
  G.best = stored("best") or 0
  G.won = stored("won") or {}
  G.last = stored("last") or 1
end

function G.won_count()
  local n = 0
  for _ in pairs(G.won) do n = n + 1 end
  return n
end

function G.save_best(score)
  if score > G.best then G.best = score store("best", score) end
end

function G.finish(hero)
  G.won[hero] = true
  store("won", G.won)
end

function G.choose(i) G.last = i store("last", i) end

return G
