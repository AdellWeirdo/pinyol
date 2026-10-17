-- ui: the Game Boy's windows, in screen pixels (480x320; one world pixel is 2x2): a framed box, a menu with a
-- cursor, and the dialogue box that types its text letter by letter and waits for A, as Pokémon's did.
local M = {}
M.T = {0xE0F8D0, 0x88C070, 0x346856, 0x081820} -- the four tones, lightest to darkest (art.py's TONES)
local T = M.T
local CH, LINE = 16, 24 -- a letter of the gb font, and a line, in screen pixels

function M.box(x, y, w, h) -- the window: a dark frame, a light gap, a mid line, the paper
  rect(x, y, w, h, T[4])
  rect(x + 2, y + 2, w - 4, h - 4, T[1])
  rect(x + 4, y + 4, w - 8, h - 8, T[3])
  rect(x + 6, y + 6, w - 12, h - 12, T[1])
end

function M.text(s, x, y, colour, align)
  return text(s, x, y, {font = "gb", color = colour or T[4], align = align})
end

function M.cursor(x, y) tri(x, y, x, y + 14, x + 8, y + 7, T[4]) end -- the ▶ the font has not got

function M.blip() tone(2, "C6", {wave = "square", duty = 0.25, decay = 0.03, vol = 0.18}) end
function M.ok() tone(2, "G6", {wave = "square", duty = 0.25, decay = 0.06, vol = 0.18}) end
function M.no() tone(2, "C4", {wave = "square", duty = 0.5, decay = 0.1, vol = 0.2}) end

function M.wrap(s, cols) -- lines of at most cols letters, broken at spaces ("\n" breaks too)
  local lines = {}
  for para in (s .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      local n = utf8.len(line) + (line == "" and 0 or 1) + utf8.len(word)
      if line ~= "" and n > cols then lines[#lines + 1], line = line, word
      else line = line == "" and word or line .. " " .. word end
    end
    lines[#lines + 1] = line
  end
  return lines
end

-- ------------------------------------------------------------------ menu

local Menu = {}
Menu.__index = Menu

-- items: labels, or {label, off = true} for one that cannot be picked now (shown, skipped by nothing: A says no)
function M.menu(items, o)
  o = o or {}
  local w = o.w or 0
  for _, it in ipairs(items) do
    w = math.max(w, (utf8.len(type(it) == "table" and it[1] or it) + 3) * CH)
  end
  return setmetatable({items = items, i = o.i or 1, w = w, x = o.x or (480 - w), y = o.y or 32,
                       title = o.title, rows = o.rows or #items, top = 1}, Menu)
end

function Menu:label(i) local it = self.items[i] return type(it) == "table" and it[1] or it end
function Menu:off(i) local it = self.items[i] return type(it) == "table" and it.off end

function Menu:update() -- the index picked, "back" (B), or nil
  local n = #self.items
  if btnp("up", 14, 5) then self.i = (self.i - 2) % n + 1 M.blip() end
  if btnp("down", 14, 5) then self.i = self.i % n + 1 M.blip() end
  if self.i < self.top then self.top = self.i end
  if self.i >= self.top + self.rows then self.top = self.i - self.rows + 1 end
  if btnp("a") then
    if self:off(self.i) then M.no() return nil end
    M.ok()
    return self.i
  end
  if btnp("b") then M.blip() return "back" end
end

function Menu:height() return self.rows * LINE + 24 + (self.title and LINE or 0) end

function Menu:draw()
  local x, y = self.x, self.y
  M.box(x, y, self.w, self:height())
  local ty = y + 14
  if self.title then M.text(self.title, x + 16, ty, T[3]) ty = ty + LINE end
  for r = 0, self.rows - 1 do
    local i = self.top + r
    if not self.items[i] then break end
    M.text(self:label(i), x + 32, ty + r * LINE, self:off(i) and T[2] or T[4])
    if i == self.i then M.cursor(x + 14, ty + r * LINE) end
  end
  if self.top > 1 then tri(x + self.w - 22, y + 18, x + self.w - 14, y + 18, x + self.w - 18, y + 12, T[4]) end
  if self.top + self.rows <= #self.items then
    local by = y + self:height() - 16
    tri(x + self.w - 22, by, x + self.w - 14, by, x + self.w - 18, by + 6, T[4])
  end
end

-- ------------------------------------------------------------------ the dialogue box

local Say = {}
Say.__index = Say
local COLS, ROWS = 27, 2

function M.say(s, who)
  local lines = M.wrap(who and (who .. ": " .. s) or s, COLS)
  return setmetatable({lines = lines, page = 1, shown = 0, t = 0, done = false}, Say)
end

function Say:page_text()
  local a = (self.page - 1) * ROWS + 1
  return self.lines[a] or "", self.lines[a + 1] or ""
end

function Say:update() -- true once the last page has been read (A)
  self.t = self.t + 1
  local l1, l2 = self:page_text()
  local total = utf8.len(l1) + utf8.len(l2)
  if self.shown < total then
    self.shown = self.shown + 1
    if btnp("a") or btnp("b") then self.shown = total end
    return false
  end
  if btnp("a") or btnp("b") then
    M.blip()
    if self.page * ROWS >= #self.lines then self.done = true return true end
    self.page, self.shown = self.page + 1, 0
  end
  return false
end

function Say:draw()
  M.box(0, 224, 480, 96)
  local l1, l2 = self:page_text()
  local n1 = utf8.len(l1)
  text(l1, 22, 248, {font = "gb", color = T[4], chars = math.min(self.shown, n1)})
  text(l2, 22, 248 + LINE + 4, {font = "gb", color = T[4], chars = math.max(0, self.shown - n1)})
  if self.shown >= n1 + utf8.len(l2) and (self.t // 20) % 2 == 0 then
    tri(446, 296, 460, 296, 453, 304, T[4]) -- ▼
  end
end

return M
