-- hud: the little things an adventure or action game keeps on its screen: a gauge that fills in steps and eases to its
-- value (a stress, a miseria, a boss's life), hearts, a counter with its icon, an objective panel, a portrait, and
-- messages that appear and go (a toast). All drawn at the screen's 480x320 with rect, box and text, or with the
-- game's own pictures where it gives them, so a look is a few colours and a frame.
--
--   local hud = require("hud")
--   local miseria = hud.meter({x = 340, y = 12, w = 128, h = 14, label = "MISERIA", segments = 10,
--                              color = 0xE0B030, danger = 0.7, danger_color = 0xE03030})
--   miseria:set(0.35)                          -- 0 to 1: the gauge eases there
--   hud.update()   miseria:update()  ...       -- each tick (hud.update moves the toasts)
--   miseria:draw()                             -- m:value() is the shown value, m.target the asked one
--   hud.hearts(16, 16, 3, 4, {size = 12})      -- 3 of 4 full
--   hud.counter(16, 40, "ICO_MONEDA", 37)      -- a picture (or nil) and a number
--   hud.portrait(8, 8, "FACE_YURI", {size = 40, frame = "FRAME_SLOT"})
--   hud.objective(332, 40, 140, "DETIENE EL CORAZON", {"Cierra las valvulas (2/3)", "Llega al nucleo"}, {done = {true, false}})
--   hud.toast("Has cogido la llave")           -- then hud.update() each tick and hud.draw_toasts(x, y, {w = 200})
local hud = {}

-- how big a font's letters are: its line height, so what is drawn around text fits whichever font the game uses
local function line_h(font) local _, h = textw("Ag", font or "main") return h end

-- ------------------------------------------------------------------ meter
local meter = {}
meter.__index = meter

function hud.meter(o)
  local self = setmetatable({}, meter)
  self.o = o
  self.target, self.shown = o.value or 0, o.value or 0
  return self
end

function meter:set(v) self.target = math.max(0, math.min(1, v)) end
function meter:value() return self.shown end

function meter:update()
  local speed = self.o.speed or 0.03
  local d = self.target - self.shown
  if math.abs(d) <= speed then self.shown = self.target else self.shown = self.shown + (d > 0 and speed or -speed) end
end

function meter:draw()
  local o = self.o
  local x, y, w, h = o.x, o.y, o.w or 100, o.h or 12
  local segs = o.segments or 10
  local border, back = o.border or 0xE8D8B0, o.back or 0x201418
  local lit = self.shown >= (o.danger or 2) and (o.danger_color or o.color) or o.color or 0xE0B030
  rect(x - 2, y - 2, w + 4, h + 4, back)
  box(x - 2, y - 2, w + 4, h + 4, border)
  local gap = 2
  local sw = (w - gap * (segs - 1)) // segs
  local full = self.shown * segs
  for i = 1, segs do
    local sx = x + (i - 1) * (sw + gap)
    rect(sx, y, sw, h, o.empty or 0x3A2A2A)
    if full >= i then rect(sx, y, sw, h, lit)
    elseif full > i - 1 then rect(sx, y, math.floor(sw * (full - (i - 1))), h, lit) end -- the segment filling
  end
  if o.label then text(o.label, x, y - line_h(o.font) - 4, o.label_color or 0xFFFFFF, o.font or "main") end
end

-- ------------------------------------------------------------------ small widgets
-- hearts: n full of max, each size pixels wide; two circles and a point, no picture needed (or `full`/`empty` pictures)
function hud.hearts(x, y, n, max, o)
  o = o or {}
  local size, gap = o.size or 12, o.gap or 3
  for i = 1, max do
    local hx = x + (i - 1) * (size + gap)
    if o.full and o.empty then
      img(i <= n and o.full or o.empty, hx, y)
    else
      local c = i <= n and (o.color or 0xE04050) or (o.empty_color or 0x40202A)
      local r = size // 4
      circ(hx + r + 1, y + r + 1, r + 1, c, true)
      circ(hx + size - r - 2, y + r + 1, r + 1, c, true)
      tri(hx, y + r + 2, hx + size - 1, y + r + 2, hx + size // 2, y + size, c, true)
    end
  end
end

function hud.counter(x, y, icon, value, o)
  o = o or {}
  local tx = x
  if icon then
    local w, h = imgsize(icon)
    if w then img(icon, x, y) tx = x + w + 4 end
  end
  text(tostring(value), tx, y + 2, o.color or 0xFFFFFF, o.font or "main")
end

function hud.portrait(x, y, pic, o)
  o = o or {}
  local size = o.size or 40
  if o.frame then frame(o.frame, x - 4, y - 4, size + 8, size + 8) else
    rect(x - 2, y - 2, size + 4, size + 4, o.back or 0x101820)
    box(x - 2, y - 2, size + 4, size + 4, o.border or 0xE8D8B0)
  end
  local w, h = imgsize(pic)
  if w then img(pic, x + (size - w) // 2, y + (size - h) // 2) end
end

-- an objective: a title and what is left to do, each line struck through (a tick) when done. w nil: as wide as its words.
function hud.objective(x, y, w, title, lines, o)
  o = o or {}
  local font = o.font or "main"
  local lh = line_h(font) + 4
  if not w then
    w = textw(title, font)
    for _, l in ipairs(lines) do w = math.max(w, (textw(l, font)) + 18) end
    w = w + 16
  end
  local h = 14 + lh * (#lines + 1)
  if o.frame then frame(o.frame, x, y, w, h) else
    rect(x, y, w, h, o.back or 0x101820)
    box(x, y, w, h, o.border or 0xE8D8B0)
  end
  text(title, x + 8, y + 6, o.title_color or 0xFFE070, font)
  for i, l in ipairs(lines) do
    local done = o.done and o.done[i]
    local ly = y + 6 + i * lh
    circ(x + 12, ly + lh // 2 - 2, 3, done and 0x60D060 or 0x707080, done)
    text(l, x + 22, ly, done and 0x80A080 or 0xE0E0E0, font)
  end
  return w, h
end

-- ------------------------------------------------------------------ toasts: messages that come and go
local toasts = {}

function hud.toast(str, ticks) toasts[#toasts + 1] = {text = str, left = ticks or 150, age = 0} end

function hud.update()
  for i = #toasts, 1, -1 do
    local t = toasts[i]
    t.age, t.left = t.age + 1, t.left - 1
    if t.left <= 0 then table.remove(toasts, i) end
  end
end

function hud.draw_toasts(x, y, o)
  o = o or {}
  local font = o.font or "main"
  local lh = line_h(font)
  for i, t in ipairs(toasts) do
    local rise = math.min(1, t.age / 8) -- slides in
    local fade = t.left < 10 and t.left / 10 or 1
    if fade > 0.4 then
      local w = o.w or (textw(t.text, font) + 16)
      local ty = y + (i - 1) * (lh + 10) - math.floor((1 - rise) * 10)
      rect(x, ty, w, lh + 6, o.back or 0x101820)
      box(x, ty, w, lh + 6, o.border or 0xE8D8B0)
      text(t.text, x + 8, ty + 3, o.color or 0xFFFFFF, font)
    end
  end
end

function hud.clear_toasts() toasts = {} end
function hud.toasts() return #toasts end

return hud
