-- Tumba: a sliding puzzle the way a PICO-8 cart did it. A 128x128 screen (the 16x16 map of the level, tiles of 8x8) in PICO-8's sixteen colours,
-- carved margins at the sides with the numbers, four chiptune channels, pixel particles, screen shake and palette fades done with pal().
-- The explorer slides until something stops him: collect every gem, avoid the spikes, reach the exit. Each level has a par, the fewest moves.
--   Arrows: slide.   B: undo the last move.   A: start the level again.   The console's menu has "Cómo funciona".
-- (gen/ makes the art, the levels (found and checked by a solver) and uses the tunes of tunes.lua)
local Rules, V, F, Mu = require("core.rules"), require("core.view"), require("core.fx"), require("core.music")
local Sfx = require("core.sfx")
local Explain = require("core.explain")
local Levels = require("levels")
local Frames = require("data.frames")
local lang = require("lang")

state = "title" -- title | select | play | clear | dead | win | demo | explain (global: tests/tumba.script)
GAME = {level = 1, moves = 0, deaths = 0, par_count = 0, unlocked = 1, best = {}}
local g = GAME
local t = 0
local lv, st, vst, hist = nil, nil, nil, {}
local hero_sh, small_sh
local hx, hy, pose, pose_t, hidden = 0, 0, "idle", 0, false
local phase_t = 0 -- ticks in the clear and dead states
local cursor, demo_t, demo_wait = 1, 0, 0
local anim = nil
local toast_text, toast_t = nil, 0
local fade_target, fade_cb = nil, nil
local PX, PY = V.PX, V.PY
local OX2, OY2 = PX * 2, PY * 2          -- the cart's corner in overlay pixels
local FONT = {title = "pico8_title", body = "pico8_body", small = "pico8_small"}

local function toast(s) toast_text, toast_t = s, 160 end
local function earn(id) if achieve(id) then toast(lang.tr("ach_" .. id)) Sfx.play("SFX_TOAST") end end

local function menu()
  menuitem()
  menuitem(lang.tr("how"), function()
    if state == "play" or state == "title" or state == "select" then Explain.enter(lv, st, hist) state = "explain" end
  end)
end

local function save_progress()
  store("unlocked", g.unlocked)
  for n, m in pairs(g.best) do store("best_" .. n, m) end
end

local function par_total()
  local n = 0
  for i = 1, #Levels do if g.best[i] and g.best[i] <= Levels[i].par then n = n + 1 end end
  return n
end

-- ------------------------------------------------------------------ levels

local function pixel(c) return c * 8 end

local function load_level(n, quick)
  g.level = n
  lv = Rules.new(Levels[n].rows)
  st = Rules.initial(lv)
  vst = Rules.copy(st)
  hist, g.moves = {}, 0
  anim, hidden = nil, false
  hx, hy = pixel(lv.start[1]), pixel(lv.start[2])
  pose, pose_t = "idle", 0
  V.margins()
  V.draw_all(lv, vst, t)
  F.clear()
  Mu.play("tumba_" .. ((n - 1) // 4 + 1))
end

local function fade_to(level, cb)
  fade_target, fade_cb = level, cb
end

local function update_fade()
  if not fade_target then return end
  if F.level == fade_target then
    local cb = fade_cb
    fade_target, fade_cb = nil, nil
    if cb then cb() end
    return
  end
  if t % 2 == 0 then F.fade(F.level + (fade_target > F.level and 1 or -1)) end
end

-- ------------------------------------------------------------------ a move

local function apply_event(e)
  local kind, x, y = e[1], e[2], e[3]
  local k = y * 16 + x
  if kind == "gem" then vst.gems = vst.gems | (1 << lv.gem_index[k])
  elseif kind == "key" then vst.keys = vst.keys | (1 << lv.key_index[k]) vst.keys_held = vst.keys_held + 1
  elseif kind == "door" then vst.doors = vst.doors | (1 << lv.door_index[k]) vst.keys_held = vst.keys_held - 1
  elseif kind == "crack" then vst.cracks = vst.cracks | (1 << lv.crack_index[k]) end
end

local function fire(e)
  local kind, x, y = e[1], e[2], e[3]
  local cx, cy = x * 8 + 4, y * 8 + 4
  if kind == "gem" then
    apply_event(e) V.cell(lv, vst, x, y, t)
    F.burst(cx, cy, 10, {12, 14, 7}, 0.9, 20) Sfx.play("SFX_GEM")
    V.draw_all(lv, vst, t) -- the exit may have opened
  elseif kind == "key" then
    apply_event(e) V.cell(lv, vst, x, y, t)
    F.burst(cx, cy, 10, {10, 9, 7}, 0.9, 22) Sfx.play("SFX_KEY")
  elseif kind == "door" then
    apply_event(e) V.cell(lv, vst, x, y, t)
    F.burst(cx, cy, 14, {4, 9, 15}, 1.1, 22) F.shake(2, 8) Sfx.play("SFX_DOOR")
  elseif kind == "crack" then
    apply_event(e) V.cell(lv, vst, x, y, t)
    F.burst(cx, cy, 14, {5, 6, 13, 7}, 1.2, 22) F.shake(3, 8) Sfx.play("SFX_CRACK")
  elseif kind == "mud" then
    F.burst(cx, cy, 6, {4, 9, 15}, 0.5, 16) Sfx.play("SFX_MUD")
  elseif kind == "tele" then
    F.burst(cx, cy, 10, {12, 7, 14}, 1.0, 18) Sfx.play("SFX_TELE")
  elseif kind == "gate" then
    F.burst(cx, cy, 4, {6, 7}, 0.6, 12)
  end
end

local function try_move(d)
  if anim or state == "clear" or state == "dead" then return end
  local result, ns, steps, ev = Rules.slide(lv, st, d)
  if result == "none" then
    pose, pose_t = "bump", 6
    F.shake(1, 4) Sfx.play("SFX_BUMP")
    return
  end
  hist[#hist + 1] = Rules.copy(st)
  anim = {path = steps, i = 0, ev = ev, result = result, ns = ns, d = d, px = hx, py = hy}
  pose, pose_t = d, 0
  Sfx.play("SFX_SLIDE")
  -- a puff behind him as he sets off
  local dx, dy = Rules.DIRS[d][1], Rules.DIRS[d][2]
  F.burst(hx + 4 - dx * 3, hy + 6 - dy * 3, 5, {13, 6}, 0.5, 12)
end

local function restart()
  Sfx.play("SFX_UNDO")
  load_level(g.level)
end

local function undo()
  if anim or #hist == 0 or state ~= "play" then return end
  st = table.remove(hist)
  vst = Rules.copy(st)
  g.moves = math.max(0, g.moves - 1)
  hx, hy = pixel(st.x), pixel(st.y)
  pose, pose_t = "idle", 0
  V.draw_all(lv, vst, t)
  Sfx.play("SFX_UNDO")
end

local function finish_move()
  local a = anim
  anim = nil
  st = a.ns
  if a.result == "dead" then
    state, phase_t = "dead", 0
    Mu.stop()
    Sfx.play("SFX_DEAD")
    F.shake(4, 14)
    F.burst(hx + 4, hy + 4, 24, {8, 14, 7, 2}, 1.6, 28)
    return
  end
  g.moves = g.moves + 1
  if state == "demo" and a.result == "win" then -- the demo does not keep anything: it waits a moment and goes on to another level
    F.burst(hx + 4, hy + 4, 24, {10, 9, 7, 12, 14}, 1.4, 30)
    Sfx.play("SFX_OK")
    demo_wait, g.demo_moves = 100, #Levels[g.level].solution + 1
    return
  end
  if a.result == "win" then
    state, phase_t = "clear", 0
    Mu.play("nivel")
    local n = g.level
    local best = g.best[n]
    if not best or g.moves < best then g.best[n] = g.moves end
    if g.moves <= Levels[n].par then g.par_made = true else g.par_made = false end
    if n == g.unlocked and n < #Levels then g.unlocked = n + 1 end
    save_progress()
    earn("primer_nivel")
    if g.par_made then earn("en_par") end
    if par_total() >= 10 then earn("diez_pares") end
    F.burst(hx + 4, hy + 4, 30, {10, 9, 7, 12, 14}, 1.5, 34)
    return
  end
  pose, pose_t = "bump", 6
  F.shake(1, 4) Sfx.play("SFX_BUMP")
  local dx, dy = Rules.DIRS[a.d][1], Rules.DIRS[a.d][2]
  F.burst(hx + 4 + dx * 4, hy + 4 + dy * 4, 5, {13, 6}, 0.6, 10)
end

local SPEED = 4
local function update_anim()
  local a = anim
  if not a then return end
  -- events at the start of the move (a crack broken at the first step)
  if a.i == 0 then
    local rest = {}
    for _, e in ipairs(a.ev) do
      if (e[4] or 0) == 0 then fire(e) else rest[#rest + 1] = e end
    end
    a.ev = rest
  end
  local target = a.path[a.i + 1]
  if not target then finish_move() return end
  if target.teleport then
    hidden = true
    hx, hy = pixel(target[1]), pixel(target[2])
    a.i = a.i + 1
    for _, e in ipairs(a.ev) do if (e[4] or 0) == a.i then fire(e) end end
    hidden = false
    return
  end
  local tx, ty = pixel(target[1]), pixel(target[2])
  local dx, dy = tx - hx, ty - hy
  local step = math.min(SPEED, math.abs(dx) + math.abs(dy))
  if dx ~= 0 then hx = hx + (dx > 0 and step or -step) elseif dy ~= 0 then hy = hy + (dy > 0 and step or -step) end
  F.add(hx + 4, hy + 6, 0, 0, 9, 13)
  if hx == tx and hy == ty then
    a.i = a.i + 1
    for _, e in ipairs(a.ev) do if (e[4] or 0) == a.i and e[1] ~= "dead" then fire(e) end end
  end
  -- the first cell of a teleport pair: the next step is the other pad
  if a.i >= #a.path then finish_move() end
end

-- ------------------------------------------------------------------ title, select, demo

local function title_scene()
  V.margins()
  for my = 1, 16 do for mx = V.OX, V.OX + 15 do V.put(mx, my, "floor_a") end end
  for r = 0, 3 do for c = 0, 14 do V.put(V.OX + c, 4 + r, "logo_" .. r .. "_" .. c) end end
end

local function enter_title()
  state, t = "title", 0
  title_scene()
  F.fade(0) F.unswap()
  Mu.play("titulo")
end

local function enter_select()
  state = "select"
  title_scene()
  for my = 1, 16 do for mx = V.OX, V.OX + 15 do V.put(mx, my, "floor_a") end end
  cursor = math.min(g.unlocked, #Levels)
end

local function start_level(n)
  fade_to(5, function()
    state = "play"
    load_level(n)
    fade_to(0)
  end)
end

local function demo_start()
  state, demo_t, demo_wait = "demo", 0, 40
  g.level = 1 + (g.demo_i or 0) % #Levels
  g.demo_i = (g.demo_i or 0) + 3
  load_level(g.level)
  Mu.play("titulo")
  g.demo_moves = 1
end

-- ------------------------------------------------------------------ init and update

function _init()
  lang.load()
  Sfx.init()
  V.init()
  F.apply()
  hero_sh, small_sh = sheet("HERO"), sheet("SMALL")
  palette("OBJ", true)
  g.unlocked = stored("unlocked", 1)
  for n = 1, #Levels do local b = stored("best_" .. n, 0) if b > 0 then g.best[n] = b end end
  Explain.hook = earn
  show(ALL)
  menu()
  enter_title()
end

function _resume() lang.load() menu() end

local function update_play()
  if anim then update_anim() return end
  if btnp("left") then try_move("L") elseif btnp("right") then try_move("R")
  elseif btnp("up") then try_move("U") elseif btnp("down") then try_move("D")
  elseif btnp("b") then undo() elseif btnp("a") then restart() end
end

local function after_clear()
  if g.level >= #Levels then
    fade_to(5, function() state = "win" t = 0 title_scene() Mu.play("fin") earn("tumba") fade_to(0) end)
  else
    start_level(g.level + 1)
  end
end

function _update()
  t = t + 1
  F.update()
  Mu.update()
  update_fade()
  if toast_t > 0 then toast_t = toast_t - 1 end
  if pose_t > 0 then pose_t = pose_t - 1 if pose_t == 0 and not anim and state == "play" then pose = "idle" end end
  if fade_target then return end
  if state == "title" then
    if btnp("a") or btnp("start") then Sfx.play("SFX_OK") enter_select()
    elseif t > 900 then demo_start() end
    if t % 6 == 0 then
      for c = 0, 2 do end
    end
  elseif state == "select" then
    if btnp("left") then cursor = math.max(1, cursor - 1) Sfx.play("SFX_SELECT") end
    if btnp("right") then cursor = math.min(math.min(g.unlocked, #Levels), cursor + 1) Sfx.play("SFX_SELECT") end
    if btnp("up") then cursor = math.max(1, cursor - 4) Sfx.play("SFX_SELECT") end
    if btnp("down") then cursor = math.min(math.min(g.unlocked, #Levels), cursor + 4) Sfx.play("SFX_SELECT") end
    if btnp("a") then Sfx.play("SFX_OK") start_level(cursor) end
    if btnp("b") then enter_title() end
  elseif state == "demo" then
    if btnp("a") or btnp("b") or btnp("start") then F.clear() enter_title() return end
    if anim then update_anim() else
      demo_wait = demo_wait - 1
      if demo_wait <= 0 then
        local sol = Levels[g.level].solution
        local i = (g.demo_moves or 1)
        if i > #sol then
          demo_start() -- the next level
        else
          try_move(sol:sub(i, i))
          g.demo_moves = i + 1
          demo_wait = 30
        end
      end
    end
    if state == "demo" and st and anim == nil and (g.demo_moves or 1) > #Levels[g.level].solution + 0 then end
  elseif state == "play" then
    update_play()
    if t % 6 == 0 and lv then V.animate(lv, vst, t) end
  elseif state == "clear" then
    pose = "win_" .. (t // 10) % 2
    if t % 6 == 0 then V.animate(lv, vst, t) end
    phase_t = phase_t + 1
    if phase_t > 90 and Mu.done() then after_clear() end
    if phase_t > 40 and (btnp("a") or btnp("start")) then after_clear() end
  elseif state == "dead" then
    phase_t = phase_t + 1
    if phase_t > 60 then
      state = "play"
      load_level(g.level)
    end
  elseif state == "win" then
    if t > 120 and btnp("a") then fade_to(5, function() enter_title() fade_to(0) end) end
  elseif state == "explain" then
    if Explain.update() then Explain.leave() state = "play" load_level(g.level) end
  end
end

-- ------------------------------------------------------------------ drawing

local function hero_frame()
  if state == "dead" then return "dead_" .. math.min(3, phase_t // 10) end
  if state == "clear" then return pose end
  if pose == "U" then return "up" elseif pose == "D" then return "down" elseif pose == "L" then return "left" elseif pose == "R" then return "right"
  elseif pose == "bump" then return "bump" end
  return ((t // 90) % 4 == 3 and t % 90 < 8) and "idle_1" or ((t // 24) % 2 == 0 and "idle_0" or "idle_1")
end

local function draw_hero()
  spr_clear()
  if hidden then return end
  if state == "title" or state == "select" or state == "win" or state == "explain" then return end
  spr(0, hero_sh, Frames.HERO[hero_frame()], PX + hx + F.sx, PY + hy + F.sy, prio(0))
end

local function say(s, x, y, font, colour, align)
  text(s, x, y, {font = font or FONT.body, color = colour or F.P8[7], align = align})
end

local function wrap(str, n) -- the words in lines of at most n letters
  local lines, line = {}, ""
  for word in str:gmatch("%S+") do
    if #line + #word + 1 > n and line ~= "" then lines[#lines + 1] = line line = word else line = line == "" and word or (line .. " " .. word) end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

local function hud()
  -- the margins: the left one the level, the gems, the moves; the right one its name and what the buttons do
  local n = g.level
  say(lang.tr("level"), 10, 40, FONT.body, F.P8[13])
  text(string.format("%02d", n), 10, 56, {font = FONT.body, color = F.P8[10], scale = 3})
  say(lang.tr("gems"), 10, 110, FONT.body, F.P8[13])
  local gems = 0
  for i = 0, #lv.gems - 1 do if (vst.gems >> i) & 1 == 1 then gems = gems + 1 end end
  text(gems .. "/" .. #lv.gems, 10, 126, {font = FONT.body, color = F.P8[12], scale = 2})
  say(lang.tr("moves"), 10, 170, FONT.body, F.P8[13])
  text(g.moves .. "/" .. Levels[n].par, 10, 186, {font = FONT.body, color = g.moves <= Levels[n].par and F.P8[11] or F.P8[8], scale = 2})
  if vst.keys_held > 0 then say("KEY", 10, 230, FONT.body, F.P8[10]) end
  for i, line in ipairs(wrap(lang.tr("name_" .. n), 12)) do say(line, 392, 40 + (i - 1) * 14, FONT.body, F.P8[6]) end
  say(lang.tr("move"), 392, 200, FONT.small, F.P8[13])
  say(lang.tr("undo"), 392, 216, FONT.small, F.P8[13])
  say(lang.tr("restart"), 392, 232, FONT.small, F.P8[13])
end

function _draw()
  local sx, sy = F.sx, F.sy
  backdrop(F.P8[0])
  scroll(1, V.OX * 8 - V.PX - sx, V.OY * 8 - V.PY - sy)
  if state == "explain" then Explain.draw(lv, vst) return end
  draw_hero()
    if state == "title" then
    say(lang.tr("press"), 240, 190, FONT.title, F.P8[7 + (t // 8) % 9], "center")
    say("PICO-8", 240, 296, FONT.small, F.P8[5], "center")
    say(lang.tr("high") .. " " .. par_total() .. "/" .. #Levels, 240, 150, FONT.body, F.P8[13], "center")
    return
  end
  if state == "select" then
    say(lang.tr("levels"), 240, 40, FONT.title, F.P8[10], "center")
    for i = 1, #Levels do
      local col, row = (i - 1) % 4, (i - 1) // 4
      local x, y = 140 + col * 52, 70 + row * 52
      local open = i <= g.unlocked
      rect(x, y, 44, 44, open and F.P8[1] or F.P8[0])
      rect(x, y, 44, 2, open and F.P8[13] or F.P8[5]) rect(x, y + 42, 44, 2, F.P8[0])
      say(string.format("%02d", i), x + 22, y + 10, FONT.title, open and F.P8[7] or F.P8[5], "center")
      local b = g.best[i]
      if b then say(b <= Levels[i].par and "*" or tostring(b), x + 22, y + 30, FONT.small, b <= Levels[i].par and F.P8[10] or F.P8[13], "center") end
      if i == cursor then
        local c = F.P8[10 - (t // 6) % 2 * 0]
        rect(x - 3, y - 3, 50, 2, c) rect(x - 3, y + 45, 50, 2, c) rect(x - 3, y - 3, 2, 50, c) rect(x + 47, y - 3, 2, 50, c)
      end
    end
    say(lang.tr("name_" .. cursor), 240, 290, FONT.small, F.P8[6], "center")
    return
  end
  if state == "win" then
    say(lang.tr("win_1"), 240, 140, FONT.title, F.P8[10], "center")
    say(lang.tr("win_2"), 240, 170, FONT.body, F.P8[7], "center")
    say(lang.tr("high") .. " " .. par_total() .. "/" .. #Levels, 240, 200, FONT.body, F.P8[12], "center")
    return
  end
  F.draw(OX2, OY2)
  hud()
  if state == "demo" then
    if (t // 30) % 2 == 0 then say(lang.tr("demo") .. " · " .. lang.tr("press"), 240, 6, FONT.small, F.P8[7], "center") end
  end
  if state == "clear" then
    say(lang.tr("done"), 240, 120, FONT.title, F.P8[10], "center")
    if g.par_made then say(lang.tr("par_made"), 240, 150, FONT.body, F.P8[11], "center") end
  end
  if toast_t > 0 then
    rect(120, 4, 240, 14, F.P8[0])
    say(toast_text, 240, 6, FONT.small, F.P8[10], "center")
  end
end
