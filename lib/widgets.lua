-- widgets: buttons, sliders and scrolling lists that a finger and the d-pad both work, with one focus.
--
--   local widgets = require("widgets")
--   local ui = widgets.new({colours = {back, ink, lit, lit_ink}, font = "bold"})
--   ui:button({x = 20, y = 20, w = 120, h = 36, label = "Jugar", on = function() ... end})
--   ui:slider({x = 20, y = 70, w = 200, h = 28, min = 0, max = 10, step = 1, value = 5, on = function(v) ... end})
--   ui:list({x = 20, y = 110, w = 200, h = 120, items = {"a", "b", ...}, on = function(i, item) ... end})
--   in _update (after pointer.update(), see lib/pointer.lua):  ui:update()
--   in _draw:                                                  ui:draw()
--
-- Finger: a tap on a button presses it or on a list item picks it; a slider follows a finger that went down on it; a
-- list scrolls as a finger drags it. D-pad: up and down move the focus between widgets (in a list, between its items
-- first); A presses the focused button or picks the list's item; left and right move a slider by its step. The focus
-- ring shows only after the d-pad was used, and goes when a finger touches. Not here: momentum after a flick.
local pointer = require("pointer")
local M = {}
local UI = {}
UI.__index = UI

function M.new(o)
  o = o or {}
  local c = o.colours or {}
  return setmetatable({
    items = {}, focus = 1, grab = nil, pad = false, font = o.font or "bold",
    colours = {back = c.back or 0x3A4660, ink = c.ink or 0xF0F0F0, lit = c.lit or 0xF2B233, lit_ink = c.lit_ink or 0x202838},
  }, UI)
end

local function add(self, kind, w)
  w.kind = kind
  if kind == "list" then w.scroll, w.sel, w.row_h = 0, w.sel or 1, w.row_h or 28 end
  if kind == "slider" then w.step, w.min, w.max, w.value = w.step or 1, w.min or 0, w.max or 10, w.value or w.min or 0 end
  self.items[#self.items + 1] = w
  return w
end

function UI:button(w) return add(self, "button", w) end
function UI:slider(w) return add(self, "slider", w) end
function UI:list(w) return add(self, "list", w) end

local function inside(w, x, y) return x >= w.x and x < w.x + w.w and y >= w.y and y < w.y + w.h end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function max_scroll(w) return math.max(0, #w.items * w.row_h - w.h) end

local function set_slider(w, v)
  v = clamp(math.floor((v - w.min) / w.step + 0.5) * w.step + w.min, w.min, w.max)
  if v ~= w.value then
    w.value = v
    if w.on then w.on(v) end
  end
end

local function press(w, x, y) -- a tap that ended on w, or A on it
  if w.kind == "button" then
    if w.on then w.on() end
  elseif w.kind == "list" and x then
    local i = math.floor((y - w.y + w.scroll) / w.row_h) + 1
    if w.items[i] then w.sel = i end
    if w.items[i] and w.on then w.on(i, w.items[i]) end
  elseif w.kind == "list" and w.items[w.sel] and w.on then
    w.on(w.sel, w.items[w.sel])
  end
end

local function show_sel(w) -- scroll so the d-pad's choice is in view
  local top, bottom = (w.sel - 1) * w.row_h, w.sel * w.row_h
  if top < w.scroll then w.scroll = top elseif bottom > w.scroll + w.h then w.scroll = bottom - w.h end
  w.scroll = clamp(w.scroll, 0, max_scroll(w))
end

function UI:update()
  if pointer.began then -- a finger went down: the widget under it is grabbed, and has the focus
    self.pad = false
    for i = #self.items, 1, -1 do
      local w = self.items[i]
      if inside(w, pointer.x, pointer.y) then
        self.grab, self.focus, self.moved = w, i, 0
        break
      end
    end
  end
  local g = self.grab
  if g and pointer.down then
    if g.kind == "slider" then set_slider(g, g.min + (pointer.x - g.x) / g.w * (g.max - g.min)) end
    if g.kind == "list" then
      self.moved = self.moved + math.abs(pointer.dy)
      g.scroll = clamp(g.scroll - pointer.dy, 0, max_scroll(g))
    end
  end
  if pointer.released and g then
    local clicked = pointer.tapped or (g.kind == "list" and self.moved < pointer.SLOP) -- (a list is picked by a slow tap too)
    if clicked and inside(g, pointer.x, pointer.y) then press(g, pointer.x, pointer.y) end
    if g.kind == "slider" then set_slider(g, g.min + (pointer.x - g.x) / g.w * (g.max - g.min)) end
    self.grab = nil
  end
  if not pointer.down and not self.grab then self:pad_keys() end
end

function UI:pad_keys()
  local w = self.items[self.focus]
  if not w then return end
  local up, down = btnp("up"), btnp("down")
  if up or down then
    self.pad = true
    if w.kind == "list" then -- inside the list first, out of it at its ends
      local to = w.sel + (down and 1 or -1)
      if to >= 1 and to <= #w.items then
        w.sel = to
        show_sel(w)
        up, down = false, false
      end
    end
    if up then self.focus = (self.focus - 2) % #self.items + 1 end
    if down then self.focus = self.focus % #self.items + 1 end
  end
  if btnp("left") or btnp("right") then
    self.pad = true
    if w.kind == "slider" then set_slider(w, w.value + (btnp("right") and w.step or -w.step)) end
  end
  if btnp("a") then
    self.pad = true
    press(w)
  end
end

function UI:draw()
  local c = self.colours
  for i, w in ipairs(self.items) do
    local down = self.grab == w and pointer.down and w.kind == "button" and inside(w, pointer.x, pointer.y)
    rect(w.x, w.y, w.w, w.h, down and c.lit or c.back)
    if w.kind == "button" then
      local _, th = textw(w.label, self.font)
      text(w.label, w.x + w.w // 2, w.y + (w.h - th) // 2, down and c.lit_ink or c.ink, self.font, "center")
    elseif w.kind == "slider" then
      local k = (w.value - w.min) / math.max(w.max - w.min, 1)
      rect(w.x + 8, w.y + w.h // 2 - 2, w.w - 16, 4, c.ink)
      circ(w.x + 8 + math.floor(k * (w.w - 16)), w.y + w.h // 2, w.h // 2 - 3, c.lit, true)
    else
      clip(w.x, w.y, w.w, w.h)
      for n, item in ipairs(w.items) do
        local y = w.y + (n - 1) * w.row_h - w.scroll
        if y + w.row_h > w.y and y < w.y + w.h then
          if n == w.sel then rect(w.x, y, w.w, w.row_h, c.lit) end
          local _, th = textw(item, self.font)
          text(item, w.x + 8, y + (w.row_h - th) // 2, n == w.sel and c.lit_ink or c.ink, self.font)
        end
      end
      clip()
    end
    if self.pad and i == self.focus then box(w.x - 2, w.y - 2, w.w + 4, w.h + 4, c.lit) end
  end
end

return M
