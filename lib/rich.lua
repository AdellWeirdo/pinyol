-- rich: text with marks inside it, as Godot's BBCode and PICO-8's control codes: a word in another colour, a wave or a
-- shake on a few words, and, typed out letter by letter, a pause, another speed, a sound at a given letter, a
-- picture among the words.
--
--   [color=FF8040]fuego[/color]  [c=FF8040]...[/c]   colour (0xRRGGBB, with or without #)
--   [wave]...[/wave]  [shake]...[/shake]              the letters move (their size: [wave=3])
--   [wait=30]  a pause of 30 ticks while typing        [speed=0.5]  letters a tick from there on
--   [sfx=SND_DING]  that sound when typing reaches it  [img=ICON_KEY]  a picture, as a word
--   [[  a "[" itself
--
--   rich.draw("Tienes [c=FFE070]3 llaves[/c].", 20, 40, {font = "main", width = 300})   -- all of it, at once
--   local r = rich.new("Hola[wait=20]... [wave]¿me oyes?[/wave]", {width = 420, speed = 1})
--   r:update() each tick, r:draw(x, y); r.done once all is shown; r:skip() shows it all
-- Options: font, color, width (wrap), speed (letters a tick, 1), line (pixels between lines), outline, shadow, blip
-- (a sound every few letters while typing) and blip_every.
local M = {}
local R = {}
R.__index = R

local function colour(v)
  v = tostring(v):gsub("^#", ""):gsub("^0x", "")
  return tonumber(v, 16)
end

-- The text into pieces: {text = what is between marks, style}, {wait = n}, {speed = n}, {sfx = id}, {img = id}.
-- (Cut where the marks are, not letter by letter: a line of a story made a garbage collection on the console.)
local function parse(str, base)
  local out, style, stack = {}, {color = base.color, wave = 0, shake = 0}, {}
  local function emit(t)
    if t == "" then return end
    local last = out[#out]
    if last and last.text and last.style == style then last.text = last.text .. t -- (around a [[)
    else out[#out + 1] = {text = t, style = style} end
  end
  local function restyle(k, v)
    stack[#stack + 1] = style
    local s = {}
    for kk, vv in pairs(style) do s[kk] = vv end
    s[k] = v
    style = s
  end
  local i = 1
  while i <= #str do
    local j = str:find("[", i, true)
    if not j then emit(str:sub(i)) break end
    emit(str:sub(i, j - 1))
    if str:sub(j + 1, j + 1) == "[" then emit("[") i = j + 2
    else
      local k = str:find("]", j, true)
      local name, val = (k and str:sub(j + 1, k - 1) or ""):match("^(/?%a+)=?(.*)$")
      if not name then emit("[") i = j + 1
      else
        if name == "color" or name == "c" then restyle("color", colour(val) or base.color)
        elseif name == "wave" then restyle("wave", tonumber(val) or 2)
        elseif name == "shake" then restyle("shake", tonumber(val) or 1)
        elseif name:sub(1, 1) == "/" then style = table.remove(stack) or style
        elseif name == "wait" then out[#out + 1] = {wait = tonumber(val) or 20}
        elseif name == "speed" then out[#out + 1] = {speed = math.max(0.05, tonumber(val) or 1)}
        elseif name == "sfx" then out[#out + 1] = {sfx = val}
        elseif name == "img" then out[#out + 1] = {img = val, style = style}
        else emit(str:sub(j, k)) end -- not a mark: as it is
        i = k + 1
      end
    end
  end
  return out
end

local function opts_of(o, style)
  return {font = o.font, color = style.color, wave = style.wave ~= 0 and style.wave or nil,
          shake = style.shake ~= 0 and style.shake or nil, outline = o.outline, shadow = o.shadow}
end

-- Where each piece goes: the words of a piece on the same line become one run, one text() each; a run's text is
-- cut from its piece once, at the end.
local function layout(pieces, o)
  local width, lh = o.width or 10000, o.line or select(2, textw("Ag", o.font))
  local space = textw(" ", o.font)
  local looks = {} -- style -> its text() options, shared by its runs (draw sets chars just before each text())
  local runs, x, y, n = {}, 0, 0, 0 -- n: letters so far (for typing)
  local cur
  local function close()
    if cur then cur.s, cur.seg, cur.p = cur.seg:sub(cur.a, cur.b), nil, nil end
    cur = nil
  end
  for _, p in ipairs(pieces) do
    if p.text then
      local seg = p.text
      for a, word, b, sep in seg:gmatch("()([^ \n]*)()([ \n]?)") do
        if word ~= "" then
          local w = textw(word, o.font)
          if x > 0 and x + w > width then close() x, y = 0, y + lh end -- wrap before the word
          local len = utf8.len(word) or #word
          if cur and cur.p == p then cur.b, cur.n1 = b - 1, n + len
          else
            close()
            cur = {p = p, seg = seg, a = a, b = b - 1, x = x, y = y, style = p.style, n0 = n, n1 = n + len,
                   t = looks[p.style] or opts_of(o, p.style)}
            looks[p.style] = cur.t
            runs[#runs + 1] = cur
          end
          n, x = n + len, x + w
        end
        if sep == "\n" then close() x, y = 0, y + lh
        elseif sep == " " and x > 0 then n, x = n + 1, x + space end -- (no space at the start of a line)
      end
    elseif p.img then
      close()
      local w, h = imgsize(p.img)
      w, h = w or 0, h or 0
      if x > 0 and x + w > width then x, y = 0, y + lh end
      runs[#runs + 1] = {img = p.img, x = x, y = y + math.max(0, lh - h) // 2, n0 = n, n1 = n + 1}
      n, x = n + 1, x + w + 2
    else
      p.at = n -- wait, speed and sfx happen when typing reaches this letter
      runs[#runs + 1] = p
    end
  end
  close()
  return runs, n
end

local function draw_runs(runs, x, y, o, shown)
  for _, r in ipairs(runs) do
    if r.s and r.n0 < shown then
      r.t.chars = shown < r.n1 and math.floor(shown - r.n0) or nil
      text(r.s, x + r.x, y + r.y, r.t)
    elseif r.img and r.n0 < shown then img(r.img, x + r.x, y + r.y) end
  end
end

local laid = setmetatable({}, {__mode = "k"}) -- options table -> the last text drawn with it, laid out
local PLAIN = {}

function M.draw(str, x, y, o) -- (the same str with the same options table each frame is laid out once)
  o = o or PLAIN
  o.color = o.color or 0xFFFFFF
  local c = laid[o]
  if not c or c.str ~= str then
    c = {str = str}
    c.runs, c.n = layout(parse(str, o), o)
    laid[o] = c
  end
  draw_runs(c.runs, x, y, o, c.n)
end

local function plain_runs(str, o) -- no marks: the engine wraps and types it, and nothing is made but this
  local n = utf8.len(str) or #str
  return {{s = str, x = 0, y = 0, n0 = 0, n1 = n, t = {font = o.font, color = o.color, width = o.width or 2 * SCREEN_W,
                                                          outline = o.outline, shadow = o.shadow}}}, n
end

function M.new(str, o)
  o = o or {}
  o.color = o.color or 0xFFFFFF
  local runs, n
  if str:find("[", 1, true) then runs, n = layout(parse(str, o), o) else runs, n = plain_runs(str, o) end
  local marks = {}
  for _, r in ipairs(runs) do if r.at then marks[#marks + 1] = r end end
  return setmetatable({runs = runs, marks = marks, o = o, total = n, shown = 0, speed = o.speed or 1, hold = 0, k = 1,
                       done = n == 0}, R)
end

function R:update()
  if self.done then return end
  if self.hold > 0 then self.hold = self.hold - 1 return end
  local before = math.floor(self.shown)
  self.shown = math.min(self.total, self.shown + self.speed)
  while self.marks[self.k] and self.marks[self.k].at <= self.shown do -- what typing has reached
    local m = self.marks[self.k]
    self.k = self.k + 1
    if m.wait then self.shown, self.hold = m.at, m.wait break
    elseif m.speed then self.speed = m.speed
    elseif m.sfx then sfx(m.sfx) end
  end
  local blip = self.o.blip
  if blip and math.floor(self.shown / (self.o.blip_every or 3)) > math.floor(before / (self.o.blip_every or 3)) then
    sfx(blip, 0.5)
  end
  if self.shown >= self.total and self.k > #self.marks then self.done = true end
end

function R:skip()
  self.shown, self.hold, self.done = self.total, 0, true
  for i = self.k, #self.marks do if self.marks[i].speed then self.speed = self.marks[i].speed end end
  self.k = #self.marks + 1
end

function R:draw(x, y) draw_runs(self.runs, x, y, self.o, self.shown) end

function M.plain(str) -- the text without its marks (to measure or to log it)
  local t = {}
  for _, p in ipairs(parse(str, {color = 0})) do
    if p.text then t[#t + 1] = p.text end
  end
  return table.concat(t)
end

return M
