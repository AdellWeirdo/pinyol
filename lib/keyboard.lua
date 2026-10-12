-- keyboard: writing with the d-pad or a finger: a name for a record, a message to another console, a password.
--
--   local keyboard = require("keyboard")
--   local kb = keyboard.new({title = "¿Cómo te llamas?", text = "", max = 12})
--   in _update: local done = kb:update()   -- "ok" or "cancel" when the player finishes, nil while writing
--   in _draw:   kb:draw()                   -- kb.text is what is written
--
-- Cross: move between keys; A: that key; B: rub out; START: done. A finger presses keys directly.
-- Options: title, text, max (letters), y (where the keyboard starts), font, and colours {back, key, lit, ink,
-- lit_ink} to match the game.
local M = {}
local KB = {}
KB.__index = KB

local ROWS = {
  {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0"},
  {"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"},
  {"A", "S", "D", "F", "G", "H", "J", "K", "L", "Ñ"},
  {"Z", "X", "C", "V", "B", "N", "M", ".", "-", "!"},
  {"abc", "space", "del", "ok"},
}
local LOWER = {["Ñ"] = "ñ"}
local KEY_W, KEY_H, GAP = 40, 30, 4

function M.new(o)
  o = o or {}
  local c = o.colours or {}
  return setmetatable({
    title = o.title, text = o.text or "", max = o.max or 16, y = o.y or 130, font = o.font or "bold",
    colours = {back = c.back or 0x202838, key = c.key or 0x3A4660, lit = c.lit or 0xF2B233, ink = c.ink or 0xF0F0F0,
               lit_ink = c.lit_ink or 0x202838},
    row = 2, col = 1, lower = false,
  }, KB)
end

local function width(k) return (k == "space" and 4 or (utf8.len(k) > 1 and 2 or 1)) * (KEY_W + GAP) - GAP end

function KB:keys() -- every key with where it is: {label, x, y, w, row, col}
  local out = {}
  for r, row in ipairs(ROWS) do
    local total = 0
    for _, k in ipairs(row) do total = total + width(k) + GAP end
    local x = (SCREEN_W - total + GAP) // 2
    for c, k in ipairs(row) do
      out[#out + 1] = {label = k, x = x, y = self.y + (r - 1) * (KEY_H + GAP), w = width(k), row = r, col = c}
      x = x + width(k) + GAP
    end
  end
  return out
end

function KB:press(k)
  if k == "del" then self.text = self.text:sub(1, utf8.offset(self.text, -1) and utf8.offset(self.text, -1) - 1 or 0)
  elseif k == "ok" then return "ok"
  elseif k == "abc" then self.lower = not self.lower
  elseif utf8.len(self.text) < self.max then
    local ch = k == "space" and " " or k
    if self.lower then ch = LOWER[ch] or ch:lower() end
    self.text = self.text .. ch
  end
end

function KB:update()
  if btnp("start") then return "ok" end
  if btnp("b") then
    if self.text == "" then return "cancel" end
    self:press("del")
  end
  local row = ROWS[self.row]
  if btnp("left") then self.col = (self.col - 2) % #row + 1 end
  if btnp("right") then self.col = self.col % #row + 1 end
  if btnp("up") or btnp("down") then -- the key above or below: the nearest one by position
    local here
    for _, k in ipairs(self:keys()) do if k.row == self.row and k.col == self.col then here = k end end
    self.row = (self.row + (btnp("up") and -2 or 0)) % #ROWS + 1
    local best, dist = 1, 1e9
    for _, k in ipairs(self:keys()) do
      local d = math.abs(k.x + k.w / 2 - (here.x + here.w / 2))
      if k.row == self.row and d < dist then best, dist = k.col, d end
    end
    self.col = best
  end
  if btnp("a") then
    local done = self:press(ROWS[self.row][self.col])
    if done then return done end
  end
  local tx, ty, _, tap = touch()
  if tap then
    for _, k in ipairs(self:keys()) do
      if tx * 2 >= k.x and tx * 2 < k.x + k.w and ty * 2 >= k.y and ty * 2 < k.y + KEY_H then
        self.row, self.col = k.row, k.col
        local done = self:press(k.label)
        if done then return done end
      end
    end
  end
end

local NAMES = {space = "espacio", del = "borrar", ok = "OK"}

function KB:draw()
  local c = self.colours
  rect(0, self.y - 70, SCREEN_W, SCREEN_H - self.y + 70, c.back)
  if self.title then text(self.title, SCREEN_W // 2, self.y - 64, c.ink, "main", "center") end
  local shown = self.text .. ((ticks() // 20) % 2 == 0 and "_" or " ")
  text(shown, SCREEN_W // 2, self.y - 38, c.lit, self.font, "center")
  for _, k in ipairs(self:keys()) do
    local lit = k.row == self.row and k.col == self.col
    rect(k.x, k.y, k.w, KEY_H, lit and c.lit or c.key)
    local label = NAMES[k.label] or k.label
    if k.label == "abc" then label = self.lower and "ABC" or "abc"
    elseif self.lower and utf8.len(k.label) == 1 then label = LOWER[k.label] or k.label:lower() end
    text(label, k.x + k.w // 2, k.y + 4, lit and c.lit_ink or c.ink, "main", "center")
  end
end

return M
