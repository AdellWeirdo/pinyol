-- Puzle: a sliding-tile puzzle for the touch screen (docs/lua.md).
--   the 15 pieces are sprites that slide, cut from one picture;
--   BG1 is the whole picture: a faint ghost over the pieces while you hold the hint (blend), and the reveal at the
--   end (mosaic); show() turns it on and off, like the GBA's display control;
--   BG2 is the board's frame, BG3 a pattern that drifts behind; music and sounds are synthesised (tone).

local N, P = 4, 36                 -- 4x4 pieces of 36x36 world pixels
local BX, BY = 10, 8               -- the board's top-left corner
local EMPTY = N * N - 1            -- the missing piece
local SLIDE, SLIDE_FAST = 6, 2     -- frames a slide takes (the fast ones shuffle)

state = "title"                    -- title, shuffle, play, solved (globals: the tests set up boards)
board, gap, moves = {}, EMPTY, 0   -- board[cell] = piece in it (cells and pieces 0..15, row by row)
local anim = {}                    -- anim[piece] = {x, y, t, len}: where its slide started
local pieces_sheet
local ticks_play, shuffle_left, last_cell, reveal = 0, 0, -1, 0
local music_on, step, fanfare_at = true, 0, -1

local function cell_xy(c) return BX + (c % N) * P, BY + (c // N) * P end

local function drawn_xy(piece, c) -- where a piece is on screen now, mid-slide or not
  local x, y = cell_xy(c)
  local a = anim[piece]
  if not a or a.t >= a.len then return x, y end
  local k = 1 - (1 - a.t / a.len) ^ 2 -- ease out
  return a.x + (x - a.x) * k, a.y + (y - a.y) * k
end

local function solved()
  for c = 0, N * N - 2 do if board[c] ~= c then return false end end
  return true
end

local function slide(c, fast) -- the piece in cell c into the gap, which must be next to it
  local piece = board[c]
  local x, y = drawn_xy(piece, c)
  anim[piece] = {x = x, y = y, t = 0, len = fast and SLIDE_FAST or SLIDE}
  board[gap], board[c], gap = piece, EMPTY, c
end

local function neighbours(c)
  local list = {}
  if c % N > 0 then list[#list + 1] = c - 1 end
  if c % N < N - 1 then list[#list + 1] = c + 1 end
  if c >= N then list[#list + 1] = c - N end
  if c < N * (N - 1) then list[#list + 1] = c + N end
  return list
end

local function adjacent(c) return math.abs(c - gap) == N or (math.abs(c - gap) == 1 and c // N == gap // N) end

local function reset_board()
  for c = 0, N * N - 1 do board[c] = c end
  gap, moves, anim = EMPTY, 0, {}
end

local function try_move(c)
  if c < 0 or c >= N * N or not adjacent(c) then
    tone(2, 110, {wave = "noise", vol = 0.25, decay = 0.04}) -- a bump: that piece cannot move
    return
  end
  slide(c)
  moves = moves + 1
  tone(2, 700 + (board[gap] or 0) * 15, {wave = "square", duty = 0.125, vol = 0.22, decay = 0.05, slide = -900})
  if solved() then
    state, reveal, fanfare_at = "solved", 0, ticks()
    local best = stored("best_ticks")
    if not best or ticks_play < best then store("best_ticks", ticks_play) end
    local fewest = stored("best_moves")
    if not fewest or moves < fewest then store("best_moves", moves) end
  end
end

function _init()
  pieces_sheet = sheet("PIECES")
  palette("OBJ", true)
  bg(3, {map = "PATTERN", prio = 3})                  -- wraps: it drifts forever
  bg(2, {map = "FRAME", prio = 2, wrap = false})
  bg(1, {map = "PICTURE", prio = 0, wrap = false, mosaic = true, x = -BX, y = -BY})
  backdrop(rgb(36, 28, 48))
  music_on = stored("music", true)
  reset_board()
end

-- music: a 16th-note step every 9 ticks (100 bpm); an arpeggio on voice 0, a bass on voice 1
local CHORDS = {{"A3", "C4", "E4", "A4"}, {"F3", "A3", "C4", "F4"}, {"C4", "E4", "G4", "C5"}, {"G3", "B3", "D4", "G4"}}
local BASS = {"A2", "F2", "C3", "G2"}
local ARP = {1, 2, 3, 4, 3, 2, 3, 4}
local FANFARE = {"C5", "E5", "G5", "C6"}

local function music()
  if ticks() % 9 ~= 0 then return end
  step = step + 1
  local chord, s = (step // 16) % 4 + 1, step % 16
  if s % 2 == 0 then tone(0, CHORDS[chord][ARP[s // 2 + 1]], {wave = "triangle", vol = 0.25, decay = 0.2}) end
  if s % 4 == 0 then tone(1, BASS[chord], {wave = "square", duty = 0.25, vol = 0.1, decay = 0.35}) end
end

local function cell_at(wx, wy) -- the board cell under a world pixel, or -1
  local cx, cy = (wx - BX) // P, (wy - BY) // P
  if wx < BX or wy < BY or cx >= N or cy >= N then return -1 end
  return cy * N + cx
end

local function hint_touched() -- the "Pista" plate on the right, held down
  local x, y, down = touch()
  return down and x >= 168 and x < 232 and y >= 129 and y < 146
end

function _update()
  for _, a in pairs(anim) do if a.t < a.len then a.t = a.t + 1 end end
  if music_on and state ~= "title" then music() end
  if btnp("start") then
    music_on = not music_on
    store("music", music_on)
    if not music_on then tone(0) tone(1) end
  end
  if fanfare_at >= 0 then -- the solved fanfare, one note every 7 ticks
    local k = (ticks() - fanfare_at) // 7
    if (ticks() - fanfare_at) % 7 == 0 and FANFARE[k + 1] then
      tone(3, FANFARE[k + 1], {wave = "square", duty = 0.5, vol = 0.3, decay = k == 3 and 0.6 or 0.15})
    end
  end

  local _, _, _, tapped = touch()
  if state == "title" or state == "solved" then
    reveal = reveal + 1
    if (btnp("a") or tapped) and (state == "title" or reveal > 40) then
      reset_board()
      state, shuffle_left, last_cell = "shuffle", 60, -1
    end
  elseif state == "shuffle" then
    if ticks() % SLIDE_FAST == 0 then -- a random move, never straight back
      local options = {}
      for _, c in ipairs(neighbours(gap)) do if c ~= last_cell then options[#options + 1] = c end end
      local c = options[math.random(#options)]
      last_cell = gap
      slide(c, true)
      shuffle_left = shuffle_left - 1
      if shuffle_left <= 0 and not solved() then state, ticks_play, moves = "play", 0, 0 end
    end
  elseif state == "play" then
    ticks_play = ticks_play + 1
    -- the d-pad pushes a piece into the gap: LEFT moves the one on the gap's right, and so on
    if btnp("left") and gap % N < N - 1 then try_move(gap + 1)
    elseif btnp("right") and gap % N > 0 then try_move(gap - 1)
    elseif btnp("up") and gap < N * (N - 1) then try_move(gap + N)
    elseif btnp("down") and gap >= N then try_move(gap - N)
    elseif tapped then
      local x, y = touch()
      local c = cell_at(x, y)
      if c >= 0 then try_move(c) end
    end
  end
end

local function clock(t) return string.format("%d:%02d", t // 3600, t // 60 % 60) end

function _draw()
  scroll(3, ticks() / 4, ticks() / 6)
  local hint = state == "play" and (btn("c") or hint_touched())
  if state == "solved" then -- the whole picture, coming out of big blocks
    show(ALL & ~OBJ)
    local m = math.max(1, 10 - reveal // 3)
    mosaic(m, m)
    fx_off()
  elseif hint then -- the picture as a ghost over the pieces
    show(ALL)
    mosaic(1, 1)
    blend(BG1, OBJ | BG2 | BACK, 6, 10)
  else
    show(ALL & ~BG1)
    fx_off()
  end

  spr_clear()
  for c = 0, N * N - 1 do
    local piece = board[c]
    if piece ~= EMPTY then
      local x, y = drawn_xy(piece, c)
      spr(piece, pieces_sheet, piece, x, y, prio(1))
    end
  end

  -- the panel on the right, at full resolution
  -- its own look: dot-matrix letters (fonts/dots.fnt) and soft rounded frames (FR_SUAVE), made by art.py
  text("PUZLE", 400, 10, {font = "dots", scale = 2, align = "center", color = 0xFFE8B0, shadow = 0x3A3060})
  local best, fewest = stored("best_ticks"), stored("best_moves")
  local function card(y, label, value, ink)
    frame("FR_SUAVE", 336, y, 128, 60, 2)
    text(label, 400, y + 9, 0x7080A8, "dots", "center")
    text(value, 400, y + 31, ink, "dots", "center")
  end
  card(66, "Jugadas", tostring(moves), 0x2A3A5A)
  card(130, "Tiempo", clock(ticks_play), 0x2A3A5A)
  card(194, "Récord", best and string.format("%s · %d", clock(best), fewest) or "—", 0x5A3A7A)
  frame("FR_SUAVE", 336, 258, 128, 36, 2)
  text("Pista (C)", 400, 268, hint and 0xC06020 or 0x5A6A8A, "dots", "center")

  if state == "title" then
    frame("FR_SUAVE", 26, 106, 280, 118, 2)
    text("Ordena la imagen", 166, 122, {font = "dots", align = "center", color = 0x2A3A5A, shadow = 0xC0CCF0})
    text("Desliza piezas al hueco", 166, 158, 0x506080, "main", "center")
    text("A o toca para empezar", 166, 188, 0xC04060, "dots", "center")
  elseif state == "solved" and reveal > 40 then
    frame("FR_SUAVE", 36, 196, 260, 102, 2)
    text("¡Resuelto!", 166, 208, {font = "dots", scale = 2, align = "center", color = 0x5A3A7A, shadow = 0xC0CCF0})
    text(string.format("%d %s · %s", moves, moves == 1 and "jugada" or "jugadas", clock(ticks_play)), 166, 248, 0x506080,
         "main", "center")
    text("A: otra vez", 166, 272, 0xC04060, "dots", "center")
  end
  text(music_on and "START: música sí" or "START: música no", 472, 298, 0x8A90A0, "main", "right")
end
