-- hud: what sits over the room, the board's way in Game Boy tones (platforms/esp32s3/renderer.py): the five status
-- bars across the top, the day badge, her words, and the menu along the bottom, icons in a row. Screen pixels;
-- everything lands on the 2x2 grid of the 240x160 world.
local ui = require("ui")
local strings = require("strings")
local T = ui.T
local M = {}

-- The room's picture (240x144 world, the board's scene less its top 76 rows) is drawn from the screen's top: a
-- board scene point (x, y) is screen (2x, 2(y - 76)), so her floor (the board's 214) sits just over the menu.
M.TOP_H = 28       -- the status bar, over the room's top
M.ROOM_Y = 0
M.CONTENT_Y = 34   -- the first row under the status bar
M.MENU_Y = 280     -- the menu's strip, under her floor
M.FLOOR = 276      -- Audrey's canvas bottom (the board's scene y 214)
-- a board scene point on this screen: the converted rooms are the board's scene less its top 76 rows; the Game Boy
-- rooms (240x160, design/gb/rooms) were redrawn from the picture's lower two thirds, its top 60 scene rows gone
local room_top
function M.sc(x, y)
  if not room_top then
    local _, h = imgsize("BG_LIVING")
    room_top = h == 160 and 60 or 76
  end
  return 2 * x, 2 * (y - room_top)
end

-- (icon, indicator, as the board's STATUS_BARS): hunger, health, affection, hygiene, energy
local BARS = {{"IC_BAR_HUNGER", "H"}, {"IC_BAR_HEALTH", "S"}, {"IC_BAR_AFFECTION", "F"},
              {"IC_BAR_HYGIENE", "clean"}, {"IC_BAR_ENERGY", "E"}}
local LOW_BELOW = 25
local MENU_ICON = {Feed = "IC_MENU_FEED", Play = "IC_MENU_PLAY", Cuddle = "IC_MENU_CUDDLE", Bath = "IC_MENU_BATH",
                   Sleep = "IC_MENU_SLEEP", Heal = "IC_MENU_HEAL", Status = "IC_MENU_STATUS",
                   Settings = "IC_MENU_SETTINGS", Sitter = "IC_MENU_SITTER", Album = "IC_MENU_ALBUM",
                   Friends = "IC_MENU_AMIGOS"}
-- a care that worked: the sound that marks it and the bar it raised, flashing a moment
M.BOOSTS = {come = "H", mimos = "F", bano = "clean", gana = "F", curar = "S"}

local function icon_at(id, x, y) -- top-left, world scale
  local w, h = imgsize(id)
  if w then img(id, x, y, {scale = 2}) return w * 2, h * 2 end
  return 0, 0
end
M.icon_at = icon_at

function M.menu_icon(label, ui_)
  if label == "Fiesta" then return "IC_MENU_FIESTA_" .. tostring(ui_.holiday):upper() end
  return MENU_ICON[label]
end

function M.topbar(ui_, t, boost)
  rect(0, 0, 480, M.TOP_H, T[1])
  rect(0, M.TOP_H - 2, 480, 2, T[4])
  local v = {}
  for k, x in pairs(ui_.indicators or {}) do v[k] = x end
  v.clean = 100 - ((ui_.stats or {})["Suciedad"] or 0)
  for i, b in ipairs(BARS) do
    local x = (i - 1) * 96
    local iw = icon_at(b[1], x + 4, 4)
    local bx, bw = x + 4 + iw + 4, 96 - iw - 16
    local value = math.max(0, math.min(100, v[b[2]] or 0))
    local blink = value < LOW_BELOW and (t // 20) % 2 == 0
    local flash = boost == b[2] and (t // 8) % 2 == 0
    rect(bx, 8, bw, 12, T[4])
    rect(bx + 2, 10, bw - 4, 8, flash and T[4] or T[1])
    local segs = 6 -- a Game Boy bar: whole blocks
    local seg_w = (bw - 4) // segs
    local on = (value * segs + 50) // 100
    if value > 0 and on == 0 then on = 1 end
    for s = 0, on - 1 do
      if not blink then rect(bx + 2 + s * seg_w, 10, seg_w - 2, 8, flash and T[1] or T[3]) end
    end
  end
end

function M.badge(ui_, clock) -- day, hour and phase on a little window, top right of the room
  local lt = clock:localtime()
  local x, y, w, h = 336, M.CONTENT_Y, 140, 52
  ui.box(x, y, w, h)
  ui.text(string.format("%02d:%02d", lt.tm_hour, lt.tm_min), x + w - 14, y + 10, T[4], "right")
  ui.text(string.format(strings.T.day, ui_.day or 1), x + w - 14, y + 30, T[3], "right")
  if ui_.night then icon_at("IC_MOON", x + 8, y + 8) end
  return x
end

-- her words: the core's overlay while it lasts, else her last interaction, in the room's top left
function M.popup(ui_, right)
  local msg = ui_.overlay
  if msg == nil or msg == "" then msg = strings.said(ui_) end
  if not msg then return end
  local warn = ui_.in_critical or ui_.sick
  local line = (warn and "! " or "") .. msg
  local x, y = 4, M.CONTENT_Y
  local w = right - x - 4
  local lines = ui.wrap(line, (w - 28) // 16)
  local h = 20 + #lines * 20
  ui.box(x, y, w, h)
  for i, l in ipairs(lines) do ui.text(l, x + 14, y + 12 + (i - 1) * 20, T[4]) end
end

-- the menu along the bottom: its icons in a row, the picked one framed, its name shown a moment after a move;
-- her need's button blinks a "!" (core: need), the Play button sparkles while a game waits unplayed
function M.menu(ui_, t, label_until, unpicked)
  local labels = ui_.menu_labels or {}
  local n = #labels
  if n == 0 then return end
  ui.box(0, M.MENU_Y, 480, 320 - M.MENU_Y)
  local cell = math.min(48, (480 - 16) // n)
  cell = cell - cell % 2
  local x0 = (480 - cell * n) // 2
  local sel = unpicked and -1 or (ui_.selected_index or 0) + 1
  for i, label in ipairs(labels) do
    local cx = x0 + (i - 1) * cell + cell // 2
    if i == sel then
      rect(cx - cell // 2 + 2, M.MENU_Y + 4, cell - 4, 32, T[4])
      rect(cx - cell // 2 + 4, M.MENU_Y + 6, cell - 8, 28, T[2])
    end
    local id = M.menu_icon(label, ui_)
    local w, h = imgsize(id or "")
    if w then img(id, cx - w, M.MENU_Y + 20 - h, {scale = 2})
    else ui.text(strings.label(label, ui_.name):sub(1, 2), cx, M.MENU_Y + 16, T[4], "center") end
    if label == ui_.need and (t // 15) % 2 == 0 then
      rect(cx + cell // 2 - 10, M.MENU_Y - 10, 8, 12, T[4]) -- a "!" over it
      rect(cx + cell // 2 - 10, M.MENU_Y + 4, 8, 4, T[4])
    end
    if label == "Play" and ui_.new_games and #ui_.new_games > 0 and (t // 10) % 2 == 0 then
      pset(cx + cell // 2 - 8, M.MENU_Y + 10, T[1])
      rect(cx + cell // 2 - 10, M.MENU_Y + 8, 6, 6, T[1])
    end
  end
  if t < label_until then
    local name = strings.label(labels[sel], ui_.name)
    local cx = x0 + (sel - 1) * cell + cell // 2
    local w = (utf8.len(name) + 2) * 16
    local x = math.max(0, math.min(480 - w, cx - w // 2))
    ui.box(x, M.MENU_Y - 40, w, 40)
    ui.text(name, x + w // 2, M.MENU_Y - 28, T[4], "center")
  end
end

-- a line along the bottom instead of the menu (with Sancho, a message)
function M.strip(lines)
  ui.box(0, M.MENU_Y - 20 * (#lines - 1), 480, 320 - M.MENU_Y + 20 * (#lines - 1))
  for i, l in ipairs(lines) do ui.text(l, 240, M.MENU_Y + 14 - 20 * (#lines - 1) + (i - 1) * 20, T[4], "center") end
end

return M
