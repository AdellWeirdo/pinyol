-- games: the minigames' boards, a port of the board's platforms/esp32s3/game_screens.py: Palito con plumas and
-- Quita nudos on boards of their own, the Trile, Audrey dice, the laser and the brush over the room. They draw the
-- core's board view (snapshot "game"); the core plays them. Board pixels become this screen's by K (her art) or by
-- hud.sc (the room). The cross is the board's A and C, A its B.
local ui = require("ui")
local hud = require("hud")
local anim = require("anim")
local actor = require("actor")
local strings = require("strings")
local CROPS = require("crops")
local ENDS = require("ends") -- the Game Boy knot's ends, if it has been redrawn
local T = ui.T
local S = strings.T
local K = actor.K
local M = {}

local PLUME_SWING = {0, 1, 2, 3, 4, 5, 4, 3, 2, 1}
local KNOT_ENDS = {{23, 80, 137}, {27, 76, 132}, {16, 81, 144}, {18, 80, 142}, {20, 80, 139}, {19, 79, 140}}
local KNOT_PAW_X = 84
local BOX_X = {42, 120, 198}
local BOX_WAVE_MS, BOX_STEP_MS = 450, 110
local LASER_X0, LASER_STEP = 60, 30
local LASER_POUNCE_MS, LASER_HOP = 900, 18
local SIMON_FEET = 34
local BRUSH_AT = {{0.5, 0.22}, {0.58, 0.45}, {0.9, 0.42}, {0.32, 0.9}, {0.5, 0.72}}
local JUMP_HOLD, LO_TENGO_STEPS = 2, 6
local INTRO_STEP_MS = 600
local INTRO_PRESSES = {feather = {0, 2, 1, 1}, knots = {0, 2, 1, 1}, boxes = {0, 2, 1, 1}, simon = {0, 1, 2, false},
                       laser = {0, 2, 1, 1}, brush = {0, 2, 1, 1}}

local G = {t = 0, gt = 0, focus = {}, jump_seq = nil, jump_at = 0, knot_seq = nil, knot_at = 0}

local function sprite(name, frame, cx, bottom) -- a set's frame, its canvas's bottom centre at (cx, bottom)
  local id = "A_" .. name:upper()
  local w, h, n = imgsize(id)
  if not w then return nil end
  local x, y = math.floor(cx - w), math.floor(bottom - h * 2)
  img(id, x, y, {frame = frame % n, scale = 2})
  return x, y, w * 2, h * 2
end

local function frames(name) local _, _, n = imgsize("A_" .. name:upper()) return n or 0 end
local function has(name) return anim.has(name) end
local function scene_y(board_screen_y) return 2 * (board_screen_y - 24 - 76) end -- the board's screen y here

local function title(words, hearts, rounds)
  local w = (utf8.len(words) + 2) * 16
  ui.box(4, hud.TOP_H + 2, w, 36)
  ui.text(words, 20, hud.TOP_H + 12, T[4])
  if rounds then -- the Trile: its rounds as little boxes, found ticked, empty crossed
    for i = 0, rounds[3] - 1 do
      local bx = 448 - (rounds[3] - 1 - i) * 34
      local by = hud.TOP_H + 8
      rect(bx, by, 26, 24, T[4]) rect(bx + 2, by + 2, 22, 20, T[2])
      if i < rounds[2] then line(bx + 5, by + 12, bx + 10, by + 18, T[4]) line(bx + 10, by + 18, bx + 21, by + 5, T[4])
      elseif i < rounds[1] then line(bx + 5, by + 5, bx + 20, by + 19, T[4]) line(bx + 20, by + 5, bx + 5, by + 19, T[4]) end
    end
    return
  end
  for i = 0, 2 do
    local cx = 456 - i * 32
    if i < (hearts or 0) then actor.icon("IC_FX_HEART", cx, hud.TOP_H + 20)
    else circ(cx, hud.TOP_H + 20, 8, T[3], false) end
  end
end

local function say(words)
  if not words or words == "" then return end
  local w = (utf8.len(words) + 2) * 16
  ui.box(4, hud.TOP_H + 40, w, 34)
  ui.text(words, 20, hud.TOP_H + 49, T[4])
end

-- the three moves (the cross's left, A, the cross's right) along the bottom, and a score under the title
local function moves(labels, score, all_three)
  ui.box(0, hud.MENU_Y, 480, 40)
  local marks = {"<", "A", ">"}
  for i = 1, 3 do
    local cx = 80 + (i - 1) * 160
    local l = labels[i] or ""
    local txt = i == 1 and (marks[1] .. " " .. l) or i == 3 and (l .. " " .. marks[3]) or ("A " .. l)
    if l == "" then txt = marks[i] end
    if i == 2 and not all_three then rect(cx - 72, hud.MENU_Y + 6, 144, 28, T[2]) end
    ui.text(txt, cx, hud.MENU_Y + 12, T[4], "center")
  end
  if score then say(score) end -- under the title
end

local function room(snap) -- the room, a tone lighter (the board darkened it): the game's pieces stand out
  local r = tostring(snap.background or "bg_living"):match("^bg_([^.]+)")
  local id = "BG_" .. r:upper()
  if snap.dark and imgsize(id .. "_NOCHE") then id = id .. "_NOCHE" end
  if imgsize(id .. "_PALE") then id = id .. "_PALE" end
  img(id, 0, hud.ROOM_Y, {scale = 2})
end

local function intro(kind, now)
  local k = (now // INTRO_STEP_MS) % 4
  local bob = (now // 150) % 2 * 6
  if #G.focus > 0 then
    local p = G.focus[k % #G.focus + 1]
    local px, py = p[1], p[2] - bob
    tri(px - 16, py - 36, px + 16, py - 36, px, py - 8, T[4])
    tri(px - 10, py - 33, px + 10, py - 33, px, py - 14, T[1])
  end
  local press = INTRO_PRESSES[kind] and INTRO_PRESSES[kind][k + 1]
  if press then
    local cx = 80 + press * 160
    box(cx - 76, hud.MENU_Y + 2, 152, 36, T[4])
    box(cx - 74, hud.MENU_Y + 4, 148, 32, T[4])
  end
end

-- ------------------------------------------------------------------ Palito con plumas

local FB = {x0 = 24, x1 = 456, top = 84, bottom = 236}

local function holds_feather(g, pup)
  if pup or g.result ~= "catch" or g.row ~= 1 or g.landed == nil or g.result_seq ~= G.jump_seq or not has("lo_tengo") then
    return false
  end
  return (G.gt - G.jump_at) // JUMP_HOLD >= frames("salto")
end

local function feather(snap, g)
  room({background = "bg_rasca", dark = snap.dark})
  local cols, rows = g.cols, g.rows
  local cw = (FB.x1 - FB.x0) // cols
  local row_h = (FB.bottom - FB.top) // rows
  local function spot(col, row) return FB.x0 + col * cw + cw // 2, FB.top + (rows - row) * row_h + row_h // 2 end
  for i = 1, cols - 1 do
    for y = FB.top, FB.bottom, 12 do rect(FB.x0 + i * cw, y, 2, 6, T[1]) end
  end
  for n, col in ipairs(g.hint or {}) do -- where it goes next: a ghost of the feather
    local hx, hy = spot(col, g.row - n)
    circ(hx, hy, 10, T[3], false) circ(hx, hy, 9, T[1], false)
  end
  local pup = anim.puppy(snap)
  local fx, fy = spot(g.col, g.row)
  G.focus = {{fx, fy - 16}, {spot(g.cat, 1), hud.FLOOR - 72}}
  if not holds_feather(g, pup) then -- the wand: the tuft swinging from the stick's tip
    local tw, th, tn = imgsize("A_PLUMA")
    if tw and tn == 1 then -- the Game Boy toy: the tuft hanging from the wand's tip, the wand up to the right
      local sway = ({0, 2, 4, 2, 0, -2, -4, -2})[G.gt % 8 + 1]
      local tx, ty = fx - tw + sway, fy - th
      local vw, vh = imgsize("A_VARITA")
      if vw then img("A_VARITA", tx + tw * 2 - 8, ty - vh * 2 + 12, {scale = 2}) end
      img("A_PLUMA", tx, ty, {scale = 2})
    elseif tw then
      local swing = PLUME_SWING[G.gt % #PLUME_SWING + 1] % tn
      local tx, ty = fx - tw, fy - th
      img("A_PLUMA", tx, ty, {frame = swing, scale = 2})
      local kx, ky = tx + 24 * K, ty + 1 * K
      local vw = imgsize("A_VARITA")
      if vw then img("A_VARITA", math.floor(kx - 3 * K), math.floor(ky - 109 * K), {scale = 2}) end
    end
  end
  if g.sway and g.sway ~= 0 then -- hard: only its sway shows
    for _, d in ipairs({0, 12}) do
      local ax = fx + g.sway * (36 + d)
      line(ax, fy - 10, ax + g.sway * 8, fy, T[4]) line(ax + g.sway * 8, fy, ax, fy + 10, T[4])
    end
  end
  for i = 0, cols - 1 do -- the columns, marked on the floor
    local mx = spot(i, 1)
    rect(mx - cw // 2 + 8, 270, cw - 16, 6, i == g.cat and T[4] or T[2])
  end
  -- her, from behind, under her column; after a landing her jump there, catching it or not
  local jump = pup and "cachorro_salto" or "salto"
  if g.result_seq ~= G.jump_seq then G.jump_seq, G.jump_at = g.result_seq, G.gt end
  local step = (G.gt - G.jump_at) // JUMP_HOLD
  local name, col, frame = "salto", g.cat, 0
  if pup then name, frame = "cachorro_pluma", 2 end
  local jumped = frames(jump)
  if (g.result_seq or 0) > 0 and g.landed ~= nil and step < jumped then
    name = g.result == "catch" and jump or (jump .. "_falla")
    col, frame = g.landed, step
  elseif g.result == "catch" and not pup and g.landed ~= nil and has("lo_tengo")
      and (step < jumped + LO_TENGO_STEPS or g.row == 1) then
    name, col, frame = "lo_tengo", g.landed, math.max(0, (step - jumped) // 2)
  end
  local cx = math.max(100, math.min(380, (spot(col, 1))))
  local w, h, n = imgsize("A_" .. name:upper())
  if w then img("A_" .. name:upper(), cx - w, hud.MENU_Y - h * 2, {frame = math.min(frame, n - 1), scale = 2}) end
  title(S.feather_title, g.hearts)
  local level = S.levels[math.max(0, math.min(2, g.level or 0)) + 1]
  moves(S.feather_moves, S.feather_score:format(g.caught or 0, g.goal or 2) .. " " .. level)
end

-- ------------------------------------------------------------------ Quita nudos

local function knots(snap, g)
  if #ENDS > 0 then room({background = "bg_rasca", dark = snap.dark}) -- the Game Boy knot: in her play room
  else img(imgsize("BG_NUDOS_PALE") and "BG_NUDOS_PALE" or "BG_NUDOS", 0, hud.ROOM_Y, {scale = 2}) end
  if g.result_seq ~= G.knot_seq then G.knot_seq, G.knot_at = g.result_seq, G.gt end
  local since = (g.result_seq or 0) > 0 and (G.gt - G.knot_at) or 99
  local kw, kh = imgsize("A_NUDOS")
  local redrawn = #ENDS > 0 -- the Game Boy knot: up over her, and her below it, pulling its ends
  local bottom = redrawn and 176 or 236
  local kx = 240 - kw
  local idx = (g.knot and g.knot > 0) and g.knot - 1 or 0
  local function end_x(i)
    if redrawn then return kx + ENDS[math.min(idx + 1, #ENDS)][i + 1] * 2 end
    return kx + KNOT_ENDS[idx + 1][i + 1] * K
  end
  local end_y = bottom - 8
  G.focus = {{end_x(g.good), end_y - 16}}
  local after_b = (g.knot or 0) > 0 and g.pulled ~= nil
  local reaching = after_b and since == 0 and has("patas_alcanza")
  local pulling = after_b and since >= 1 and since < 3 and has("patas_tira")
  if (g.knot or 0) > 0 and not pulling then
    local frame, shake = idx, 0
    if (g.result == "miss" or g.result == "lost") and since >= 3 and since < 9 then
      frame, shake = math.min(idx + 1, frames("nudos") - 1), (since % 2 == 0) and -4 or 4
    end
    img("A_NUDOS", kx + shake, bottom - kh * 2, {frame = frame, scale = 2})
    local glow = ({true, G.gt % 2 == 0, G.gt % 6 == 0})[math.max(0, math.min(2, g.level or 0)) + 1]
    if glow and g.result ~= "free" and g.result ~= "lost" then actor.icon("IC_FX_SPARKLE", end_x(g.good), end_y + 18) end
    local sx = end_x(g.sel) -- the end picked
    circ(sx, end_y, 14, T[4], false) circ(sx, end_y, 13, T[4], false)
  end
  if (g.knot or 0) == 0 and has("nudo_libre") then -- freed
    local fw, fh = imgsize("A_NUDO_LIBRE")
    img("A_NUDO_LIBRE", 240 - fw, (redrawn and bottom or hud.MENU_Y) - fh * 2, {scale = 2})
    for _, sp in ipairs({{80, 80}, {400, 60}, {240, 40}}) do
      if (G.gt + sp[1]) % 3 ~= 0 then actor.icon("IC_FX_SPARKLE", sp[1], sp[2]) end
    end
  end
  if redrawn then -- her, below the knot: resting, a paw out to the end picked, pulling
    local name, frame = "patas", G.gt % 2
    if reaching then name, frame = "patas_alcanza", g.pulled == 2 and 1 or 0
    elseif pulling then name, frame = "patas_tira", g.result == "ok" and 0 or 1 end
    local shake = pulling and (g.result == "miss" or g.result == "lost") and (since == 1 and -6 or 6) or 0
    local w, h = imgsize("A_" .. name:upper())
    if w then img("A_" .. name:upper(), 240 - w + shake, hud.MENU_Y - h * 2, {frame = frame, scale = 2}) end
  else
    local pw, ph = imgsize("A_PATAS")
    if reaching then
      local right = g.pulled == 2 and 1 or 0
      local aw, ah = imgsize("A_PATAS_ALCANZA")
      local px = right == 1 and (aw * 2 - KNOT_PAW_X * K) or KNOT_PAW_X * K
      img("A_PATAS_ALCANZA", math.floor(end_x(g.pulled) - px), hud.MENU_Y - ah * 2, {frame = right, scale = 2})
    elseif pulling then
      local tw, th = imgsize("A_PATAS_TIRA")
      local shake = (g.result == "miss" or g.result == "lost") and (since == 1 and -6 or 6) or 0
      img("A_PATAS_TIRA", 240 - tw + shake, hud.MENU_Y - th * 2, {frame = g.result == "ok" and 0 or 1, scale = 2})
    elseif pw and (g.knot or 0) > 0 then
      img("A_PATAS", 240 - pw, hud.MENU_Y - ph * 2, {frame = G.gt % 2, scale = 2})
    end
  end
  title(S.knots_title, g.hearts)
  local level = S.levels[math.max(0, math.min(2, g.level or 0)) + 1]
  moves(S.knots_moves, S.knots_score:format(math.min((g.step or 0) + 1, g.steps or 3), g.steps or 3) .. " " .. level)
end

-- ------------------------------------------------------------------ Trile de cajas

local function boxes(snap, g, now)
  room(snap)
  local floor = scene_y(24 + 220 - 14)
  title(S.game_boxes, 0, {g.round or 0, g.found or 0, g.rounds or 3})
  local phase = g.intro and "intro" or g.phase
  local xs = {BOX_X[1] * 2, BOX_X[2] * 2, BOX_X[3] * 2}
  G.focus = {{xs[1], floor - 88}, {xs[2], floor - 88}, {xs[3], floor - 88}}
  local lifts = {0, 0, 0}
  if phase == "shuffle" and g.swaps and #g.swaps > 0 then
    local k = math.max(0, math.min(#g.swaps - 1, (now - g.phase_at) // g.swap_ms))
    local p = ((now - g.phase_at) % g.swap_ms) / g.swap_ms
    local a, b = g.swaps[k + 1][1] + 1, g.swaps[k + 1][2] + 1
    local xa, xb = xs[a], xs[b]
    xs[a], xs[b] = math.floor(xa + (xb - xa) * p), math.floor(xb + (xa - xb) * p)
    lifts[a] = math.floor(32 * 4 * p * (1 - p))
  end
  if phase == "pick" then lifts[g.sel + 1] = 10 + 6 * (G.gt % 2) end
  local since = now - (g.phase_at or now)
  for i = 1, 3 do
    local b = i - 1
    local name, frame = "caja", 0
    if phase == "show" and b == g.cat then
      local step = (since - BOX_WAVE_MS) // BOX_STEP_MS
      if since < BOX_WAVE_MS then name, frame = "caja_audrey", 4
      elseif step < 4 then name, frame = "caja_audrey", 3 - step end
    elseif phase == "result" and b == g.where then name, frame = "caja_audrey", math.min(4, since // BOX_STEP_MS)
    elseif phase == "result" and b == g.picked then name, frame = "caja_audrey", 0 end
    sprite(name, frame, xs[i], floor - (name == "caja" and lifts[i] or 0))
  end
  if phase == "pick" then -- a big arrow up at the one pointed
    local px = xs[g.sel + 1]
    tri(px - 16, floor + 20, px + 16, floor + 20, px, floor + 4, T[4])
  end
  local words = ({intro = "boxes_show", show = "boxes_show", shuffle = "boxes_shuffle", pick = "boxes_pick"})[phase]
  if phase == "result" then words = g.result == "found" and "boxes_found" or "boxes_empty" end
  say(S[words])
  moves(S.btn_boxes)
end

-- ------------------------------------------------------------------ Audrey dice

local function simon(snap, g)
  room(snap)
  local pose = g.intro and "idle" or ({show = "encontrada", input = "pedir"})[g.phase]
    or ((g.result == "round" or g.result == "won") and "happy_wiggle" or "molesta")
  sprite(has(pose) and pose or "idle", G.gt, 240, scene_y(24 + 220 - SIMON_FEET))
  local lit = (not g.intro) and g.lit or nil
  local pad_bottom = scene_y(24 + 220 - 12)
  local pw, ph = imgsize("A_SIMON_PAD")
  G.focus = {}
  for i = 0, 2 do
    local px = (50 + i * 70) * 2
    if pw then img("A_SIMON_PAD", px - pw, pad_bottom - ph * 2, {frame = 2 * i + (lit == i and 1 or 0), scale = 2}) end
    if lit == i then -- lit: rays round it, as plain as a light can be in four tones
      for _, d in ipairs({{-1, -1}, {1, -1}, {-1, 1}, {1, 1}}) do
        line(px + d[1] * 40, pad_bottom - 36 + d[2] * 26, px + d[1] * 52, pad_bottom - 36 + d[2] * 34, T[4])
      end
    end
    G.focus[#G.focus + 1] = {px, pad_bottom - 80}
  end
  for i = 0, (g.run_len or 0) - 1 do -- how far into the run you are
    local on = g.phase == "input" and i < (g.got or 0)
    rect((120 - g.run_len * 6 + i * 12) * 2, pad_bottom + 4, 16, 8, on and T[4] or T[2])
  end
  title(S.game_simon:format(snap.name or "Audrey"), g.hearts)
  local words = ({show = "simon_show", input = "simon_turn"})[g.phase]
  if g.phase == "result" then words = (g.result == "miss" or g.result == "lost") and "simon_miss" or "simon_good" end
  say(S[words])
  moves(S.btn_simon, nil, true)
end

-- ------------------------------------------------------------------ Puntero láser

local function laser(snap, g, now)
  room(snap)
  local floor = scene_y(24 + 220 - 8)
  title(S.game_laser, g.hearts)
  for i = 0, (g.spots or 5) - 1 do rect((LASER_X0 + i * LASER_STEP) * 2 - 2, floor - 2, 6, 6, T[2]) end
  local ax = (LASER_X0 + g.aim * LASER_STEP) * 2
  local dx = (LASER_X0 + g.dot * LASER_STEP) * 2
  G.focus = {{dx, floor - 16}, {ax, floor - 140}}
  local ready = g.aim == g.dot
  circ(ax, floor - 6, 26, ready and T[4] or T[3], false) circ(ax, floor - 6, 27, ready and T[4] or T[3], false)
  local since = now - (g.at or 0)
  local fresh = (g.result_seq or 0) > 0 and (since < 900 or g.result == "won" or g.result == "lost")
  local name = fresh and (({catch = "happy_wiggle", won = "happy_wiggle"})[g.result] or "juzgando") or "idle"
  local frame, hop = G.gt, 0
  if fresh and (g.cause == "catch" or g.cause == "miss") and since < LASER_POUNCE_MS then
    local step = since * 5 // LASER_POUNCE_MS
    if has("caza_laser") and (g.cause == "catch" or step < 3) then
      name, frame = "caza_laser", step
      if step == 2 then hop = LASER_HOP * 2 end
    end
  end
  if anim.puppy(snap) then name = anim.puppy_once(name) or "cachorro" end
  sprite(name, frame, ax, floor - 12 - hop)
  local pulse = G.gt % 2 * 2 -- the dot, glowing: dark round a light heart
  circ(dx, floor - 8, 14 + pulse, T[4]) circ(dx, floor - 8, 8, T[2]) circ(dx, floor - 8, 3, T[1])
  say(S[fresh and g.cause and ("laser_" .. g.cause) or "laser_aim"])
  moves(S.btn_laser)
end

-- ------------------------------------------------------------------ Cepillarla

local function brush(snap, g, now)
  room(snap)
  title(S.game_brush, g.patience)
  local fresh = (g.result_seq or 0) > 0 and (now - (g.at or 0) < 900 or g.result == "won" or g.result == "lost")
  local name = fresh and (({swat = "molesta", knot = "mimos", won = "happy_wiggle"})[g.result] or "idle") or "idle"
  local pup = anim.puppy(snap)
  if pup then name = anim.puppy_once(name) or "cachorro" end
  local bottom = scene_y(24 + 220 - 10)
  if fresh and g.result == "lost" then -- had enough: she walks off, out to the left
    local walk = pup and "cachorro_anda_izq" or "anda_izq"
    local gone = (now - g.at) * 480 // 1300
    sprite(has(walk) and walk or name, G.gt, 240 - gone, bottom)
    say(S.brush_lost)
    moves(S.btn_brush)
    return
  end
  local x, y = sprite(name, G.gt, 240, bottom)
  G.focus = {}
  if x then
    local c = CROPS[anim.pick(name)] or {0, 0, 0, 0}
    local sx, sy, sw, sh = x + c[1] * 2, y + c[2] * 2, c[3] * 2, c[4] * 2 -- her drawing, not her canvas
    for i, f in ipairs(BRUSH_AT) do
      local zx, zy = sx + math.floor(sw * f[1]), sy + math.floor(sh * f[2])
      for k = 0, (g.knots[i] or 0) - 1 do sprite("nudo_pelo", 0, zx - 12 + k % 3 * 12, zy + k // 3 * 8 + 8) end
      if i - 1 == g.sel then sprite("cepillo", (G.gt // 3) % 2, zx, zy - 12) end
      if (g.knots[i] or 0) > 0 and i < #BRUSH_AT and #G.focus == 0 then G.focus[1] = {zx, zy} end
    end
    if fresh and g.result == "knot" then
      local f = BRUSH_AT[g.sel + 1]
      actor.icon("IC_FX_SPARKLE", sx + sw * f[1], sy + sh * f[2] - 40)
    end
    if g.sel == #BRUSH_AT - 1 and not fresh then -- her belly: careful, she may swat
      local f = BRUSH_AT[#BRUSH_AT]
      local wx, wy = sx + math.floor(sw * f[1]) + 36, sy + math.floor(sh * f[2]) - 36
      circ(wx, wy, 16, T[4]) circ(wx, wy, 14, T[1])
      rect(wx - 2, wy - 10, 4, 12, T[4]) rect(wx - 2, wy + 6, 4, 4, T[4])
    end
  end
  local words = fresh and ({swat = "brush_swat", smooth = "brush_smooth", won = "brush_won", lost = "brush_lost"})[g.result]
  if words then say(S[words]) else say(S.brush_zones[g.sel + 1]) end
  moves(S.btn_brush)
end

-- ------------------------------------------------------------------

function M.update() G.t = G.t + 1 G.gt = G.t // 9 end -- ~150 ms a step, the board's game pace

function M.draw(snap, now)
  local g = snap.game or {}
  G.focus = {}
  local kind = g.kind
  if kind == "feather" then feather(snap, g)
  elseif kind == "knots" then knots(snap, g)
  elseif kind == "boxes" then boxes(snap, g, now)
  elseif kind == "simon" then simon(snap, g)
  elseif kind == "laser" then laser(snap, g, now)
  elseif kind == "brush" then brush(snap, g, now)
  else
    room(snap)
    ui.box(40, 120, 400, 60)
    ui.text(tostring(snap.minigame_label or ""), 240, 140, T[4], "center")
  end
  hud.topbar(snap, G.t)
  if g.intro then intro(kind, now) end
end

return M
