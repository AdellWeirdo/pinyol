-- run: the game around the microgames: the title, the interlude (lives, score, what comes next), one microgame played for its few
-- seconds with a bar of time that shortens as the speed goes up, the verdict, and the end. Each change of scene is scene.go with
-- {clean = true}: what a microgame did to the picture and the sound (fade, windows, mosaic, line tables, a note, the LED) is gone before the next.
local scene = require("scene")
local hud = require("hud")
local ui = require("ui")
local pad = require("pad")

local M = {}
local GAMES = {"g_pulsa", "g_esquiva", "g_cuenta", "g_machaca", "g_busca", "g_gira", "g_quieto"}
local BOSS = "g_jefe"
local TOTAL, EVERY, LIVES, FASTER = 12, 4, 4, 0.15 -- games before the boss, games to a faster speed, lives, speed gained

M.games = {}
for _, id in ipairs(GAMES) do M.games[#M.games + 1] = require(id) end
M.boss = require(BOSS)

-- a new run: the order of the games (the seven shuffled, over and over, then the boss)
function M.new(bot, bot_lose)
  local order, deck = {}, {}
  while #order < TOTAL do
    if #deck == 0 then
      for i = 1, #M.games do deck[i] = i end
      for i = #deck, 2, -1 do local j = math.random(1, i); deck[i], deck[j] = deck[j], deck[i] end
    end
    order[#order + 1] = M.games[table.remove(deck)]
  end
  order[#order + 1] = M.boss
  pad.bot = bot or false
  return {lives = LIVES, score = 0, played = 0, order = order, level = 1, speed = 1, bot = bot or false, bot_lose = bot_lose or false, faster = false}
end

local function advance(r) -- after a game
  r.played = r.played + 1
  local level = 1 + r.played // EVERY
  r.faster = level > r.level
  r.level, r.speed = level, 1 + FASTER * (level - 1)
end

local function go(s, args) scene.go(s, args, {clean = true}) end

-- ------------------------------------------------------------------ title
local Title = {}
local choice
function Title.enter() choice = 1 bg(0) bg(1) bg(2) bg(3, {map = "BG1", prio = 3, wrap = false}) palette("WORLD") backdrop(0) end
function Title.update()
  if btnp("up") or btnp("down") then choice = choice % 2 + 1 end
  if btnp("a") or btnp("start") then
    run = M.new(choice == 2)
    go(M.interlude)
  end
end
function Title.draw()
  shade(70, 40, 340, 220)
  text("MICROJUEGOS", 240, 66, {font = "large_bold", scale = 2, align = "center", color = ui.SEL})
  text("cinco segundos, cuatro vidas", 240, 116, {font = "main", align = "center", color = ui.INK})
  for i, name in ipairs({"Jugar", "Demostración"}) do
    text((i == choice and "> " or "  ") .. name, 240, 160 + (i - 1) * 28, {font = "bold", align = "center", color = i == choice and ui.SEL or ui.INK})
  end
  local best = stored("best", 0)
  text("Mejor: " .. best, 240, 262, {font = "main", align = "center", color = ui.SUB})
end
M.title = Title

-- ------------------------------------------------------------------ the interlude
local Inter = {}
local it
function Inter.enter()
  it = 0
  palette("WORLD")
  bg(3, {map = "BG" .. ((run.played % 3) + 1), prio = 3, wrap = false})
  backdrop(0)
end
function Inter.update()
  it = it + 1
  if it >= 55 then go(M.play, {game = run.order[run.played + 1]}) end
end
function Inter.draw()
  shade(60, 90, 360, 150)
  hud.hearts(190, 104, run.lives, LIVES, {size = 20, gap = 8})
  text(string.format("Puntos  %d", run.score), 240, 150, {font = "bold", align = "center", color = ui.INK})
  local g = run.order[run.played + 1]
  text(run.faster and "¡MÁS RÁPIDO!" or (g.boss and "¡EL JEFE!" or "preparado..."), 240, 182, {font = "main", align = "center", color = run.faster and 0xFF8060 or ui.SUB})
  text(string.format("%d/%d", run.played + 1, TOTAL + 1), 240, 206, {font = "main", align = "center", color = ui.DIM})
end
M.interlude = Inter

-- ------------------------------------------------------------------ one microgame
local Play = {}
local g, t, limit, result, rt
function Play.enter(args)
  g, t, result, rt = args.game, 0, nil, 0
  palette("WORLD")
  palette("OBJ", true)
  bg(3, {map = g.bg, prio = 3, wrap = false})
  backdrop(0)
  g.enter(run.level, run.speed)
  limit = g.time and math.floor(g.time * 60 / run.speed) or nil
  M.current = g
end

local function verdict(r)
  result, rt = r, 0
  run.last = r
  run.log = run.log or {}
  run.log[#run.log + 1] = r -- (the tests read these)
  if r == "win" then sfx("WIN") else sfx("LOSE") end
end

function Play.update()
  t = t + 1
  if result then
    rt = rt + 1
    if rt >= 42 then
      if result == "win" then run.score = run.score + 100 * run.level else run.lives = run.lives - 1 end
      advance(run)
      if run.lives == 0 or (g.boss and result == "win") or run.played > TOTAL then
        go(M.over, {won = g.boss and result == "win"})
      else
        go(M.interlude)
      end
    end
    return
  end
  if run.bot then pad.bot_input(g.bot(run.bot_lose)) end
  local r = g.update()
  if not r and limit and t >= limit then r = g.timeout end
  if r then verdict(r) end
  if limit and not r and (limit - t) % 30 == 0 and limit - t <= 90 then sfx("TICK") end
end

function Play.draw()
  g.draw()
  if limit then
    local k = math.max(0, 1 - t / limit)
    rect(60, 10, 360, 12, 0x101830)
    rect(60, 10, math.floor(360 * k), 12, k > 0.3 and 0xFFE070 or 0xFF6040)
  end
  if t < 36 and not result then
    text(g.verb, 240, 100, {font = "large_bold", scale = 2, align = "center", color = 0xFFFFFF})
  end
  if result then
    text(result == "win" and "¡BIEN!" or "¡AY!", 240, 130, {font = "large_bold", scale = 2, align = "center", color = result == "win" and 0x80FF90 or 0xFF8080})
  end
end
M.play = Play

-- ------------------------------------------------------------------ the end
local Over = {}
local ot, won
function Over.enter(args)
  ot, won = 0, args.won
  bg(3, {map = "BG3", prio = 3, wrap = false})
  palette("WORLD")
  backdrop(0)
  if run.score > stored("best", 0) then store("best", run.score) end
end
function Over.update()
  ot = ot + 1
  if ot > 50 and (btnp("a") or btnp("start") or run.bot) then
    pad.bot = false
    scene.go(M.title, nil, {clean = true, fade = 0.4})
  end
end
function Over.draw()
  shade(80, 90, 320, 150)
  text(won and "¡VICTORIA!" or "FIN DEL JUEGO", 240, 110, {font = "large_bold", align = "center", color = ui.SEL})
  text(string.format("%d puntos", run.score), 240, 160, {font = "bold", align = "center", color = ui.INK})
end
M.over = Over

return M
