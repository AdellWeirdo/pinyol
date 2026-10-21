-- story: conversations and stories that branch, written as plain text, with a box that shows them (docs/lua.md,
-- "Stories"). The text, one line per thing:
--
--   == knot                 a place in the story, to go to by its name
--   Klaus: Hola, {nombre}.  a line said (the name before ": " is who says it; "Klaus (triste)" also gives a mood);
--                           {expr} puts a value in the text
--   Text alone.             a line nobody says
--   * Ask about it -> knot  a choice, once (taken, it goes); "+" always there; without "-> knot" the story goes on
--                           after the choices
--   -> knot                 go there ("-> END" ends the story)
--   [if expr] ...           that line only when expr is true (any of the above)
--   [do code]               Lua, with the story's variables as globals: [do confianza = confianza + 1]
--   [var name = expr]       a variable and the value it starts with, unless a saved story has it already
--   // a comment
--
-- local s = story.new(file("story/es.txt"), {vars = stored("story"), name = "es.txt"})
-- s:go("start"); s:update() and s:draw() each tick; store("story", s.vars) to save where the story's variables are.
local story = {}
story.__index = story
local rich = require("rich") -- a line's text may carry marks: [c=FF8040]color[/c], [wave], [wait=20], [sfx=ID]...

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local render -- a line's parts as text (below)

local UI = {
  font = "main", color = 0xFFFFFF, name_color = 0xFFE070, choice_color = 0xB8C8D8, pick_color = 0xFFFFFF,
  speed = 1, x = 16, y = 214, w = 448, h = 94, pad = 12, frame = nil, frame_scale = 1, panel = false, portraits = {},
  box = 0x101820, border = 0xE8D8B0,
  blip = nil, blip_every = 3,
}

-- Compiles the text into a list of instructions; errors name the file and the line. Lines indented under a choice
-- are what happens when it is taken; then the story goes on after the choices (or where the choice's -> says).
local function compile(self, src, name)
  local prog, knots, defaults, at, knot = {}, {}, {}, 0, ""
  local groups = {} -- choices still open, the innermost last: {indent, ins, cur (the last choice), body}
  local function fail(msg) error(name .. ":" .. at .. ": " .. msg, 0) end
  local function code(text, ret)
    local f, err = load((ret and "return " or "") .. text, "=" .. name .. ":" .. at, "t", self.env)
    if not f then fail(err:gsub("^[^:]*:%d+:%d*:?%s*", "")) end
    return f
  end
  local parts
  local seqs = 0
  local function sequence(e) -- {a|b|c} the next each time it is read, then the last for ever; {&a|b} round and round;
    -- {~a|b} one at random; {!a|b} once each, then nothing. What it has shown is kept with the story (vars.seq)
    local kind = e:sub(1, 1)
    if kind == "&" or kind == "~" or kind == "!" then e = e:sub(2) else kind = "" end
    local items = {}
    for item in (e .. "|"):gmatch("(.-)|") do items[#items + 1] = parts(item) end
    seqs = seqs + 1
    local key = name .. ":" .. seqs
    return function()
      local seq = self.vars.seq
      local n = (seq[key] or 0) + 1
      seq[key] = n
      local i
      if kind == "&" then i = (n - 1) % #items + 1
      elseif kind == "~" then i = math.random(#items)
      elseif kind == "!" then i = n <= #items and n or nil
      else i = math.min(n, #items) end
      return i and render(items[i]) or ""
    end
  end
  function parts(text) -- "Hola {nombre}." -> {"Hola ", f, "."}
    local out, pos = {}, 1
    while true do
      local a, b, e = text:find("{(.-)}", pos)
      if not a then out[#out + 1] = text:sub(pos); return out end
      out[#out + 1] = text:sub(pos, a - 1)
      out[#out + 1] = e:find("|", 1, true) and sequence(e) or code(e, true)
      pos = b + 1
    end
  end
  local function emit(ins)
    local g = groups[#groups]
    if g and not g.body then g.body, g.cur.body = true, #prog + 1 end -- the first line under a choice
    prog[#prog + 1] = ins
  end
  local function end_body(g) -- the lines under a choice end: on past the choices, or where it goes
    if g.body then
      prog[#prog + 1] = g.cur.target and {op = "goto", target = g.cur.target, at = g.cur.at} or {op = "after", group = g.ins}
      g.body = false
    end
  end
  local function close(indent, choice) -- the groups this line is not under; the one it continues, if a choice
    while #groups > 0 do
      local g = groups[#groups]
      if indent > g.indent then return nil end
      end_body(g)
      if indent == g.indent and choice then return g end
      g.ins.after, groups[#groups] = #prog + 1, nil
    end
  end
  for raw in (src .. "\n"):gmatch("(.-)\r?\n") do
    at = at + 1
    local indent = #raw:match("^[ \t]*"):gsub("\t", "    ")
    local line = trim(raw)
    local cond
    local c, rest = line:match("^%[if%s+(.-)%]%s*(.*)$")
    if c then cond, line = code(c, true), rest end
    if line == "" or line:sub(1, 2) == "//" then
      if cond then fail("[if] with nothing after it") end
    elseif line:sub(1, 2) == "==" then
      if cond then fail("[if] does not apply to a knot") end
      close(-1)
      local k = trim(line:gsub("^=+", ""):gsub("=+$", ""))
      if not k:match("^[%w_]+$") then fail("a knot's name is letters, digits and _: '" .. k .. "'") end
      if knots[k] then fail("knot '" .. k .. "' twice") end
      knots[k], knot = #prog + 1, k
      prog[#prog + 1] = {op = "knot", name = k, at = at}
    elseif line:match("^%[var%s") then
      local v, e = line:match("^%[var%s+([%a_][%w_]*)%s*=%s*(.-)%]$")
      if not v then fail("[var name = value]") end
      defaults[#defaults + 1] = {v, code(e, true)}
    elseif line:match("^[%*%+]") then
      local body = trim(line:sub(2))
      local cc, br = body:match("^%[if%s+(.-)%]%s*(.*)$")
      if cc then cond, body = code(cc, true), br end
      local text, target = body:match("^(.-)%s*%->%s*(%S+)$")
      text = text or body
      local choice = {text = parts(text), target = target, once = line:sub(1, 1) == "*", cond = cond, at = at,
                      key = knot .. "|" .. text} -- (a saved story keeps the once-choices taken by these)
      local g = close(indent, true)
      if g then
        g.ins.list[#g.ins.list + 1] = choice
      else
        local ins = {op = "choices", list = {}, at = at}
        emit(ins)
        g = {indent = indent, ins = ins}
        groups[#groups + 1] = g
        ins.list[1] = choice
      end
      choice.group, g.cur, g.body = g.ins, choice, false
    else
      close(indent)
      local ins
      if line:match("^%[do%s") then
        local e = line:match("^%[do%s+(.-)%]$")
        if not e then fail("[do code] needs its ]") end
        ins = {op = "do", fn = code(e)}
      elseif line:sub(1, 2) == "->" then
        ins = {op = "goto", target = trim(line:sub(3))}
      else
        local who, said = line:match("^([^:{}%[%]]+):%s+(.+)$")
        if who and #who > 30 then who, said = nil, nil end
        local mood
        if who then
          who = trim(who)
          local w, m = who:match("^(.-)%s*%((.-)%)$")
          if w then who, mood = w, m end
        end
        ins = {op = "say", who = who, mood = mood, text = parts(said or line)}
      end
      ins.cond, ins.at = cond, at
      emit(ins)
    end
  end
  close(-1)
  local function check(target, where)
    if target and target ~= "END" and not knots[target] then
      at = where
      fail("there is no knot '" .. target .. "'")
    end
  end
  for _, ins in ipairs(prog) do
    if ins.op == "goto" then check(ins.target, ins.at) end
    if ins.op == "choices" then
      for _, c in ipairs(ins.list) do check(c.target, c.at) end
    end
  end
  return prog, knots, defaults
end

-- story.new(text [, {vars, name, ui}]): ui changes how the box looks (font, color, name_color, choice_color,
-- pick_color, speed (letters a tick), x, y, w, h, pad, box and border (its colours), frame (a picture for frame()
-- instead), frame_scale, panel (true: the game's theme's panel instead), portraits
-- (who or "who_mood" -> picture), blip (a sound per letters, or a function(letter): a voice, which can ask
-- s:line().who for whose it is), blip_every)
function story.new(src, opts)
  opts = opts or {}
  if type(src) ~= "string" then error("story.new: the story's text (file(...) gave nil?)", 2) end
  local self = setmetatable({}, story)
  self.vars = opts.vars or {}
  self.env = setmetatable({}, {
    __index = function(_, k)
      local v = self.vars[k]
      if v == nil then v = _G[k] end
      return v
    end,
    __newindex = function(_, k, v) self.vars[k] = v end,
  })
  self.prog, self.knots, self.defaults = compile(self, src, opts.name or "story")
  self.vars.seen = self.vars.seen or {}
  self.vars.taken = self.vars.taken or {}
  self.vars.seq = self.vars.seq or {}
  rawset(self.env, "visits", function(knot) return self.vars.seen[knot] or 0 end) -- [if visits("bar") > 1]
  for _, d in ipairs(self.defaults) do
    if self.vars[d[1]] == nil then self.vars[d[1]] = d[2]() end
  end
  self.ui = setmetatable(opts.ui or {}, {__index = UI})
  self.done = true
  return self
end

function render(p)
  local out = {}
  for i, v in ipairs(p) do out[i] = type(v) == "function" and tostring(v()) or v end
  return table.concat(out)
end

function story:_jump(k)
  if k == "END" then self.done = true return end
  self.pc, self.jumped = k and self.knots[k] or 1, k ~= nil
end

-- Runs until something is said, choices are offered, or the story ends.
function story:_run()
  self.line_, self.choices_ = nil, nil
  local steps = 0
  while not self.done do
    steps = steps + 1
    if steps > 100000 then error("story: it goes round without saying anything (near line " .. self.prog[self.pc].at .. ")") end
    local ins = self.prog[self.pc]
    if not ins then self.done = true break end
    self.pc = self.pc + 1
    if ins.op == "knot" then
      if not self.jumped then self.done = true break end -- the end of a knot ends the story
      self.jumped = false
      self.knot = ins.name
      self.vars.seen[ins.name] = (self.vars.seen[ins.name] or 0) + 1
    elseif ins.cond and not ins.cond() then
    elseif ins.op == "say" then
      self.line_ = {who = ins.who, mood = ins.mood, text = render(ins.text)}
      self:_typeset()
      return
    elseif ins.op == "do" then
      ins.fn()
    elseif ins.op == "goto" then
      self:_jump(ins.target)
    elseif ins.op == "after" then
      self.pc = ins.group.after
    elseif ins.op == "choices" then
      local list = {}
      for _, c in ipairs(ins.list) do
        if (not c.cond or c.cond()) and not (c.once and self.vars.taken[c.key]) then
          list[#list + 1] = {text = render(c.text), c = c}
        end
      end
      if #list > 0 then
        self.choices_, self.sel = list, 1
        return
      end
      self.pc = ins.after
    end
  end
  self.line_, self.choices_ = nil, nil
end

function story:go(knot) -- start (again) at a knot, or with none from the first line
  if knot ~= nil and not self.knots[knot] then error("story: there is no knot '" .. tostring(knot) .. "'", 2) end
  self.done = false
  self:_jump(knot)
  self:_run()
end

function story:line() return self.line_ end -- {who, mood, text} being said, or nil
function story:choices() -- the texts of the choices offered, or nil
  if not self.choices_ then return nil end
  local t = {}
  for i, c in ipairs(self.choices_) do t[i] = c.text end
  return t
end

function story:next() -- past the line being said
  if self.line_ then self:_run() end
end

function story:choose(i)
  local o = self.choices_ and self.choices_[i]
  if not o then return end
  if o.c.once then self.vars.taken[o.c.key] = true end
  self.choices_ = nil
  if o.c.body then self.pc = o.c.body
  elseif o.c.target then self:_jump(o.c.target)
  else self.pc = o.c.group.after end
  self:_run()
end

function story:running() return not self.done end

-- The box: the letters come one by one; A (or a tap) shows the line whole, then goes on; up and down pick a choice,
-- A or a tap on it takes it. Returns "done" when the story has ended.
function story:update()
  if self.done then return "done" end
  local ui = self.ui
  local tx, ty, _, tapped = touch()
  local go = btnp("a") or tapped
  if self.line_ then
    if self.shown < self.total then
      if go then self.rt:skip() else self.rt:update() end
      self.shown = math.max(self.shown, self.rt.shown)
    elseif go then
      self:next()
    end
  elseif self.choices_ then
    local n = #self.choices_
    if btnp("up") then self.sel = (self.sel - 2) % n + 1 end
    if btnp("down") then self.sel = self.sel % n + 1 end
    if tapped then
      local row = self:_row_at(tx * 2, ty * 2)
      if row then self:choose(row) end
    elseif btnp("a") then
      self:choose(self.sel)
    end
  end
  if self.done then return "done" end
end

function story:_rows()
  local ui = self.ui
  local _, lh = textw("Ag", ui.font)
  local top = ui.y + ui.pad
  return top, lh + 4
end

function story:_row_at(x, y)
  local ui = self.ui
  if x < ui.x or x >= ui.x + ui.w then return nil end
  local top, step = self:_rows()
  local i = math.floor((y - top) / step) + 1
  if i >= 1 and i <= #self.choices_ then return i end
end

function story:_text_x() -- where a line's text starts and how wide it may be (a portrait takes the left)
  local ui, l = self.ui, self.line_
  local x, w = ui.x + ui.pad, ui.w - 2 * ui.pad
  local face = l.who and (ui.portraits[l.who .. "_" .. (l.mood or "")] or ui.portraits[l.who])
  local fw = face and imgsize(face)
  if fw then x, w = x + fw + ui.pad, w - fw - ui.pad end
  return x, w, face
end

function story:_typeset() -- the line laid out, with its marks, to be typed
  local ui = self.ui
  local _, w = self:_text_x()
  self.rt = rich.new(self.line_.text, {font = ui.font, color = ui.color, width = w, speed = ui.speed, blip = ui.blip,
                                       blip_every = ui.blip_every})
  self.shown, self.total = 0, self.rt.total
end

function story:draw()
  if self.done or not (self.line_ or self.choices_) then return end
  local ui = self.ui
  if ui.frame then frame(ui.frame, ui.x, ui.y, ui.w, ui.h, ui.frame_scale)
  elseif ui.panel then panel(ui.x, ui.y, ui.w, ui.h)
  else
    rect(ui.x, ui.y, ui.w, ui.h, ui.box)
    box(ui.x + 2, ui.y + 2, ui.w - 4, ui.h - 4, ui.border)
  end
  local x, w = ui.x + ui.pad, ui.w - 2 * ui.pad
  if self.line_ then
    local l = self.line_
    local tx, tw, face = self:_text_x()
    if face then
      local _, fh = imgsize(face)
      img(face, x, ui.y - fh + ui.h - ui.pad)
    end
    x, w = tx, tw
    local y = ui.y + ui.pad
    if l.who then
      local _, h = text(l.who, x, y, {color = ui.name_color, font = ui.font})
      y = y + h + 2
    end
    self.rt.shown = self.shown
    self.rt:draw(x, y)
    if self.shown >= self.total and ticks() % 40 < 26 then
      tri(ui.x + ui.w - 20, ui.y + ui.h - 14, ui.x + ui.w - 10, ui.y + ui.h - 14, ui.x + ui.w - 15, ui.y + ui.h - 8,
          ui.name_color)
    end
  else
    local top, step = self:_rows()
    for i, c in ipairs(self.choices_) do
      local y = top + (i - 1) * step
      local on = i == self.sel
      if on then tri(x, y + 3, x, y + step - 7, x + 6, y + step / 2 - 2, ui.pick_color) end
      text(c.text, x + 12, y, {color = on and ui.pick_color or ui.choice_color, font = ui.font, width = w - 12})
    end
  end
end

return story
