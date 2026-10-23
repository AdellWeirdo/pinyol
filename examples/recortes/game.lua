-- game: the rules of the rhythm. Time is counted in ticks from the first bar (negative in the intro). The teacher's notes happen by themselves; the
-- player's turn has notes with a time and a button, and a press is judged by how near in time and whether it was the right button. The mood meter
-- rises and falls with the judgements and sets the rank (the music and the dolls follow it). Nothing here draws or sounds: it calls hook(event, ...).
local Song = require("song")
local G = {}

local COOL, GOOD, BAD, NEAR = 3, 7, 12, 16 -- ticks either side of a note: cool, good, bad; the furthest a press still means that note
local DELTA = {cool = 0.075, good = 0.04, bad = -0.035, awful = -0.09, miss = -0.07}
G.RANKS = {"awful", "bad", "good", "cool"}

function G.rank_of(m) return m < 0.2 and "awful" or m < 0.45 and "bad" or m < 0.78 and "good" or "cool" end

function G.start(id)
  local s = Song.songs[id]
  G.id, G.song = id, s
  G.step_t = 900 / s.bpm        -- ticks a sixteenth note
  G.bar_t = G.step_t * 16
  G.t = -s.intro * G.bar_t
  G.meter, G.rank, G.combo, G.best_combo = 0.5, "good", 0, 0
  G.count = {cool = 0, good = 0, bad = 0, awful = 0, miss = 0}
  G.done, G.result = false, nil
  G.notes, G.sing = {}, {}
  for k, bar in ipairs(s.bars) do
    local t0 = (k - 1) * G.bar_t
    for _, nt in ipairs(Song.phrases[bar.phrase]) do
      local note = {t = t0 + nt.step * G.step_t, button = nt.button, syl = nt.syl, bar = k, step = nt.step, state = "pending"}
      if bar.who == "teacher" then G.sing[#G.sing + 1] = note else G.notes[#G.notes + 1] = note end
    end
  end
  G.total = #G.notes
  G.length = (#s.bars + s.outro) * G.bar_t
  G.hook = G.hook or function() end
  G.last = nil -- the last judgement: {kind, button, t}
end

-- which bar is it, and whose turn: bar number (1..), who ("intro", "teacher", "player", "outro"), the position inside the bar in steps (0..16)
function G.where()
  local k = math.floor(G.t / G.bar_t) + 1
  local step = (G.t - (k - 1) * G.bar_t) / G.step_t
  if k < 1 then return k, "intro", step end
  if k > #G.song.bars then return k, "outro", step end
  return k, G.song.bars[k].who, step
end

local function judge(note, kind)
  note.state = kind
  G.count[kind] = G.count[kind] + 1
  G.meter = math.max(0, math.min(1, G.meter + DELTA[kind]))
  if kind == "cool" or kind == "good" then
    G.combo = G.combo + 1
    G.best_combo = math.max(G.best_combo, G.combo)
  else
    G.combo = 0
  end
  G.last = {kind = kind, button = note.button, t = G.t, note = note}
  G.hook("judge", kind, note)
  local r = G.rank_of(G.meter)
  if r ~= G.rank then G.rank = r G.hook("rank", r) end
end

-- inp = {a = pressed, b = pressed, left = pressed, right = pressed}
function G.update(inp)
  if G.done then return end
  G.t = G.t + 1
  for _, nt in ipairs(G.sing) do -- the teacher sings by itself
    if nt.state == "pending" and G.t >= nt.t then nt.state = "sung" G.hook("sing", nt) end
  end
  for _, b in ipairs({"a", "b", "left", "right"}) do
    if inp and inp[b] then
      local best
      for _, nt in ipairs(G.notes) do
        if nt.state == "pending" and math.abs(nt.t - G.t) <= NEAR and (not best or math.abs(nt.t - G.t) < math.abs(best.t - G.t)) then best = nt end
      end
      if not best then G.hook("stray", b)
      elseif best.button ~= b then judge(best, "awful")
      else
        local d = math.abs(best.t - G.t)
        judge(best, d <= COOL and "cool" or d <= GOOD and "good" or "bad")
      end
      G.hook("press", b, best)
    end
  end
  for _, nt in ipairs(G.notes) do -- a note the player let pass
    if nt.state == "pending" and G.t > nt.t + BAD then judge(nt, "miss") end
  end
  if G.t >= G.length then
    G.done = true
    local c = G.count
    local acc = G.total > 0 and (c.cool + c.good * 0.75 + c.bad * 0.35) / G.total or 0
    G.result = {accuracy = acc, rank = G.rank, clean = c.bad + c.awful + c.miss == 0, best_combo = G.best_combo, count = c, total = G.total}
    G.hook("done", G.result)
  end
end

-- the notes' windows, for the picture and the tests
G.COOL, G.GOOD, G.BAD, G.NEAR = COOL, GOOD, BAD, NEAR

return G
