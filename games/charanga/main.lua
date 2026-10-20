-- La Charanga de Emergencia · episodio 1, «La entrevista»: a rhythm game for the touch screen. A band in red waistcoats
-- bursts out of a lift to see a nervous candidate to the interview's door; the player taps and follows its beat.
-- song.lua: the music and its clock (studio.pos); chart.lua: what to play; scene.lua: the corridor; es.lua: the texts.
-- Globals the tests read: state, notes, stats, energy, calib.
local pointer = require("pointer")
local particles = require("particles")
local song = require("song")
local chart = require("chart")
local scene = require("scene")
local T = require("es")

local R = 24                            -- a target's radius (48 px across: a fingertip, docs/ds-touch-research.md)
local COLOURS = {0x3DB55A, 0x3C7DDB, 0xD9434F, 0x9B4DD6}
local CAPTIONS = {{48, 51, "doubt"}, {76, 79, "push"}, {108, 111, "knock"}}
local ENTER_TICKS = 100                 -- the walk through the door, after the song
local FONT_BIG, FONT, FONT_SMALL = "comic_beatemup_title", "comic_beatemup_body", "comic_beatemup_small"

state, notes, stats, energy = "title", {}, {}, 0.5
local fx = particles.new()
local popups = {}      -- {x, y, text, colour, age}
local hop = 0          -- ticks the candidate jumps for joy
local last_beat = 0
local enter_t = 0
local again = {x = 180, y = 250, w = 120, h = 44}
local calib_btn = {x = 160, y = 262, w = 160, h = 40}           -- on the title: tune the timing
local level_btns = {{x = 54, y = 194, w = 120, h = 40}, {x = 180, y = 194, w = 120, h = 40}, {x = 306, y = 194, w = 120, h = 40}}
level = 2                               -- the difficulty chosen (global: the tests read it)
local resume_btn = {x = 130, y = 170, w = 100, h = 44}          -- in the pause
local quit_btn = {x = 250, y = 170, w = 100, h = 44}
local CALIB_TAPS, CALIB_WARMUP = 12, 2  -- taps measured, after the first ones (the ear finds the beat)
calib = nil                             -- {taps = {...}, result} while tuning (global: the tests read it)
local paused_bar                        -- the bar the song stopped in
local touch_in                          -- the screen the finger went down on: a touch only counts on its own screen

local function window_beats(sec) return sec / song.SEC_PER_BEAT end

local function play_beat() -- the beat as judged: the song's, less the player's offset
  local b = song.beat()
  return b and b - chart.OFFSET / song.SEC_PER_BEAT
end

local function start(lv)
  level = lv or level
  store("level", level)
  chart.use(level)
  notes = chart.notes(level)
  for i, n in ipairs(notes) do n.colour = COLOURS[(i - n.n) % #COLOURS + 1] end
  stats = {perfect = 0, good = 0, miss = 0, total = #notes}
  energy, popups, hop, enter_t, last_beat = 0.5, {}, 0, 0, 0
  song.start()
  song.set_energy(energy)
  state = "play"
end

local function cheer(n, grade)
  local good = grade ~= "miss"
  stats[grade] = stats[grade] + 1
  energy = math.max(0, math.min(1, energy + (grade == "perfect" and 0.05 or good and 0.03 or -0.07)))
  song.set_energy(energy)
  n.state, n.grade, n.age = good and "hit" or "miss", grade, 0
  popups[#popups + 1] = {x = n.x, y = n.y - 34, text = T[grade], colour = good and 0xFFF2A0 or 0xFF8A80, age = 0}
  if good then
    sfx("GOLPE", grade == "perfect" and 0.9 or 0.6)
    fx:burst(n.x, n.y, grade == "perfect" and 18 or 10, {speed = 3, colours = {0xFFFFFF, 0xFFE070, n.colour}, life = 22,
                                                          size = 3, gravity = 0.08})
    hop = 12
  else
    sfx("FALLO", 0.6)
  end
end

-- The ball of a drag at beat b: along its path, from its start (at t) to its end (at t2)
local function ball(n, b)
  local f = math.max(0, math.min(1, (b - n.t) / (n.t2 - n.t)))
  local p, total = n.path, 0
  for i = 2, #p do total = total + math.sqrt((p[i][1] - p[i - 1][1]) ^ 2 + (p[i][2] - p[i - 1][2]) ^ 2) end
  local want = f * total
  for i = 2, #p do
    local a, c = p[i - 1], p[i]
    local seg = math.sqrt((c[1] - a[1]) ^ 2 + (c[2] - a[2]) ^ 2)
    if want <= seg then return a[1] + (c[1] - a[1]) * want / seg, a[2] + (c[2] - a[2]) * want / seg end
    want = want - seg
  end
  return p[#p][1], p[#p][2]
end

local function judge_tap(b, x, y) -- a finger down at (x, y), or A (x nil): the note it plays, if any
  local good = window_beats(chart.GOOD)
  local best, bd
  for _, n in ipairs(notes) do
    if not n.state and not n.following and math.abs(n.t - b) <= good then
      local near = not x or (x - n.x) ^ 2 + (y - n.y) ^ 2 <= (R + 16) ^ 2 -- a little past the circle still counts
      if near and (not bd or math.abs(n.t - b) < bd) then best, bd = n, math.abs(n.t - b) end
    end
  end
  if not best then return end
  if best.drag then -- a drag starts with its first touch: from now on the ball is followed
    best.following, best.inside, best.samples = true, 0, 0
    return
  end
  cheer(best, bd <= window_beats(chart.PERFECT) and "perfect" or "good")
end

local function update_play()
  pointer.update()
  song.update()
  for _, n in ipairs(notes) do if n.state then n.age = n.age + 1 end end
  local b = play_beat()
  if not b then
    if song.done then state, enter_t = "enter", 0 end
    return
  end
  last_beat = b
  if pointer.began then judge_tap(b, pointer.x, pointer.y) end
  if btnp("a") then judge_tap(b) end
  local late = window_beats(chart.GOOD)
  for _, n in ipairs(notes) do
    if n.drag and n.following and not n.state then -- following: is the finger (or A, held) on the ball?
      if b >= n.t then
        local bx, by = ball(n, b)
        local on = (pointer.down and (pointer.x - bx) ^ 2 + (pointer.y - by) ^ 2 <= chart.FOLLOW ^ 2) or btn("a")
        n.samples, n.inside = n.samples + 1, n.inside + (on and 1 or 0)
      end
      if b >= n.t2 then
        local k = n.samples > 0 and n.inside / n.samples or 0
        n.x, n.y = n.path[#n.path][1], n.path[#n.path][2]
        cheer(n, k >= 0.75 and "perfect" or k >= 0.45 and "good" or "miss")
      end
    elseif not n.state and not n.following and b > n.t + late then
      cheer(n, "miss")
    end
  end
  if song.done or b >= song.BARS * 4 then song.stop(); state, enter_t = "enter", 0 end
end

-- Tests: the song from bar `bar` (0-based); the notes before it are left out of the score.
function debug_skip(bar)
  song.jump(bar)
  for _, n in ipairs(notes) do
    if not n.state and n.t < bar * 4 then n.state, n.age = "skip", 99; stats.total = stats.total - 1 end
  end
end

function _init()
  song.init()
  chart.OFFSET = stored("offset", 0)
  level = stored("level", 2)
end

local function median(t)
  local s = {}
  for i, v in ipairs(t) do s[i] = v end
  table.sort(s)
  local n = #s
  return n % 2 == 1 and s[(n + 1) // 2] or (s[n // 2] + s[n // 2 + 1]) / 2
end

local function update_calib() -- taps on the bass drum's beat: their median distance to it is the player's offset
  pointer.update()
  if calib.result then
    if pointer.began or btnp("a") or btnp("b") then studio.stop(); state = "title" end -- (a new touch: the last tap's lift is not one)
    return
  end
  if btnp("b") then studio.stop(); state = "title" return end
  if pointer.began or btnp("a") then
    local d = song.offset_now()
    if d then
      calib.seen = calib.seen + 1
      if calib.seen > CALIB_WARMUP then calib.taps[#calib.taps + 1] = d end
      sfx("GOLPE", 0.5)
    end
    if #calib.taps >= CALIB_TAPS then
      local v = math.max(-0.25, math.min(0.25, median(calib.taps)))
      calib.result, chart.OFFSET = v, v
      store("offset", v)
      studio.stop()
    end
  end
end

function _update()
  pointer.update()
  if pointer.began then touch_in = state end
  fx:update()
  for i = #popups, 1, -1 do
    popups[i].age = popups[i].age + 1
    if popups[i].age > 30 then table.remove(popups, i) end
  end
  if hop > 0 then hop = hop - 1 end
  if state == "title" then
    pointer.update()
    if (pointer.pressed(calib_btn) and touch_in == "title") or btnp("c") then
      calib, state = {taps = {}, seen = 0}, "calib"
      song.metronome()
    else -- a level's sign starts it; the cross chooses one, A starts it
      for i, b in ipairs(level_btns) do
        if pointer.pressed(b) and touch_in == "title" then return start(i) end
      end
      if btnp("left") then level = math.max(1, level - 1) end
      if btnp("right") then level = math.min(3, level + 1) end
      if btnp("a") or btnp("start") then start() end
    end
  elseif state == "calib" then
    update_calib()
  elseif state == "play" then
    if btnp("start") then -- the pause: the song stops; it comes back from the start of the bar it was in
      paused_bar, state = song.bar, "pause"
      studio.stop()
    else
      update_play()
    end
  elseif state == "pause" then
    pointer.update()
    if (pointer.pressed(resume_btn) and touch_in == "pause") or btnp("start") or btnp("a") then
      song.jump(paused_bar)
      state = "play"
    elseif (pointer.pressed(quit_btn) and touch_in == "pause") or btnp("b") then
      song.stop()
      state = "title"
    end
  elseif state == "enter" then
    enter_t = enter_t + 1
    if enter_t >= ENTER_TICKS then state = "result" end
  elseif state == "result" then
    pointer.update()
    if (pointer.pressed(again) and touch_in == "result") or btnp("a") or btnp("start") then start() end
  end
end

local function draw_note(n, b)
  local ahead = n.t - b
  if n.state then -- its answer fades out where it was
    if (n.age or 0) < 14 then circ(n.x, n.y, R + (n.age or 0), n.state == "hit" and 0xFFFFFF or 0x804040, false) end
    return
  end
  if ahead > chart.APPROACH or (n.drag and b > n.t2) then return end
  if n.drag then
    local p = n.path
    for i = 2, #p do
      for o = -3, 3 do line(p[i - 1][1], p[i - 1][2] + o, p[i][1], p[i][2] + o, 0xF2C94C) end
    end
    circ(p[#p][1], p[#p][2], 10, 0xF2C94C)
  end
  if ahead > 0 then -- the ring closes on the beat
    local r = R + math.floor(R * 2 * ahead / chart.APPROACH)
    circ(n.x, n.y, r, n.colour, false)
    circ(n.x, n.y, r + 1, 0xFFFFFF, false)
    circ(n.x, n.y, r + 2, n.colour, false)
  end
  if n.drag and b >= n.t then
    local bx, by = ball(n, b)
    circ(bx, by, 14, n.following and 0xFFE070 or 0xA08840)
    circ(bx, by, chart.FOLLOW, 0xFFFFFF, false)
  else
    circ(n.x, n.y, R, n.colour)
    circ(n.x, n.y, R, 0xFFFFFF, false)
    circ(n.x, n.y, R - 1, 0xFFFFFF, false)
    text(tostring(n.n), n.x, n.y - 13, {font = FONT_BIG, color = 0xFFFFFF, align = "center", shadow = 0x202020})
  end
end

local function draw_title()
  scene.draw(0, 0.5, 0)
  shade(0, 0, SCREEN_W, SCREEN_H)
  panel(40, 56, 400, 194)
  text(T.title, SCREEN_W // 2, 66, {font = FONT_BIG, color = 0xC0392B, align = "center"})
  text(T.episode, SCREEN_W // 2, 110, {font = FONT, color = 0x3A2A1E, align = "center"})
  text(T.how, SCREEN_W // 2, 144, {font = FONT, color = 0x5A4A3E, align = "center", width = 360})
  for i, b in ipairs(level_btns) do
    if i == level then rect(b.x - 3, b.y - 3, b.w + 6, b.h + 6, 0xF2C94C) end
    plate(b.x, b.y, b.w, b.h, ({0x3DB55A, 0xC0392B, 0x9B4DD6})[i])
    text(T.levels[i], b.x + b.w // 2, b.y + 10, {font = FONT, color = 0xFFFFFF, align = "center"})
  end
  plate(calib_btn.x, calib_btn.y, calib_btn.w, calib_btn.h, 0x3C7DDB)
  text(T.calibrate, calib_btn.x + calib_btn.w // 2, calib_btn.y + 8, {font = FONT, color = 0xFFFFFF, align = "center"})
end

local function draw_calib()
  scene.draw(0, 0.5, 0)
  shade(0, 0, SCREEN_W, SCREEN_H)
  panel(50, 60, 380, 210)
  text(T.calib_title, SCREEN_W // 2, 76, {font = FONT_BIG, color = 0x3C7DDB, align = "center"})
  if calib.result then
    text(string.format(T.calib_result, math.floor(calib.result * 1000 + 0.5)), SCREEN_W // 2, 140,
         {font = FONT, color = 0x3A2A1E, align = "center"})
    text(T.calib_done, SCREEN_W // 2, 200, {font = FONT, color = 0xC0392B, align = "center"})
    return
  end
  text(T.calib_how, SCREEN_W // 2, 124, {font = FONT, color = 0x3A2A1E, align = "center", width = 340})
  local step = studio.pos()
  local on = step and (step - 1) % 4 == 0 -- the drum's beat, lit
  circ(SCREEN_W // 2, 200, on and 26 or 20, on and 0xD9434F or 0x8A3A40)
  text(string.format(T.calib_count, #calib.taps, CALIB_TAPS), SCREEN_W // 2, 232, {font = FONT_SMALL, color = 0x5A4A3E,
                                                                                    align = "center"})
end

local function draw_pause()
  shade(0, 0, SCREEN_W, SCREEN_H)
  panel(110, 100, 260, 130)
  text(T.pause, SCREEN_W // 2, 114, {font = FONT_BIG, color = 0x3A2A1E, align = "center"})
  plate(resume_btn.x, resume_btn.y, resume_btn.w, resume_btn.h, 0x3DB55A)
  text(T.resume, resume_btn.x + resume_btn.w // 2, resume_btn.y + 10, {font = FONT, color = 0xFFFFFF, align = "center"})
  plate(quit_btn.x, quit_btn.y, quit_btn.w, quit_btn.h, 0xC0392B)
  text(T.quit, quit_btn.x + quit_btn.w // 2, quit_btn.y + 10, {font = FONT, color = 0xFFFFFF, align = "center"})
end

local function draw_result()
  local hits = stats.perfect + stats.good
  local pct = stats.total > 0 and math.floor(100 * hits / stats.total + 0.5) or 0
  local grade = pct >= 85 and 1 or pct >= 60 and 2 or 3
  panel(50, 60, 380, 240)
  text(T.result_title, SCREEN_W // 2, 76, {font = FONT_BIG, color = 0x2E7D32, align = "center"})
  text(T.level_names[level] .. " · " .. string.format(T.result_hits, hits, stats.total, pct), SCREEN_W // 2, 124,
       {font = FONT, color = 0x3A2A1E, align = "center"})
  text(T.grade[grade], SCREEN_W // 2, 160, {font = FONT, color = 0x5A4A3E, align = "center", width = 340})
  plate(again.x, again.y, again.w, again.h, 0xC0392B)
  text(T.again, again.x + again.w // 2, again.y + 10, {font = FONT, color = 0xFFFFFF, align = "center"})
end

function _draw()
  cls(0)
  if state == "title" then return draw_title() end
  if state == "calib" then return draw_calib() end
  local playing = state == "play" or state == "pause"
  local b = playing and last_beat or song.BARS * 4
  local enter = not playing and math.min(1, enter_t / ENTER_TICKS) or nil
  scene.draw(b, energy, hop, enter)
  text(T.door, scene.DOOR.x + scene.DOOR.w // 2, 52, {font = FONT_SMALL, color = 0x3A2A1E, align = "center"})
  if playing then
    for i = #notes, 1, -1 do draw_note(notes[i], b) end -- the earliest on top
    for _, c in ipairs(CAPTIONS) do
      if b >= c[1] and b < c[2] then
        text(T[c[3]], SCREEN_W // 2, 34, {font = FONT, color = 0xFFFFFF, align = "center", shadow = 0x202020})
      end
    end
  end
  fx:draw()
  for _, p in ipairs(popups) do
    text(p.text, p.x, p.y - p.age // 2, {font = FONT, color = p.colour, align = "center", shadow = 0x202020})
  end
  scene.meter(energy, T.meter)
  if state == "result" then draw_result() end
  if state == "pause" then draw_pause() end
end
