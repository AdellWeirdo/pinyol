-- dialog: people talking. The words are written as stories (story/es.txt, ca.txt, en.txt: knots, choices, conditions,
-- things that happen) and this is their window: the console's own, a framed box of tiles at the foot of the screen
-- (or at the top when the hero stands low), the letters typed one by one with a blip that is each speaker's voice.
-- A long line is cut into pages that fit the box, as a handheld's text always was.
local story = require("story")
local rich = require("rich")
local voice = require("voice")
local Game = require("core.game")
local UI = require("core.ui")
local Pal = require("core.pal")
local E = require("core.ents")
local D = {}

D.active = false
D.story = nil

local TW = 200        -- the text's width, in world pixels
local LINE = 12       -- a line's height, in world pixels (the letters are 8 tall)
local FONT = "ps"
local win = {tx = 1, tw = 28, th = 7, top = false}
local after = {}      -- what to do when the window closes
local voices = {}
local VOICES = {default = 0.9, yaya = 0.8, higuera = 0.62, bellota = 1.5, nogal = 0.55, sardina = 0.95, espantajo = 1.15,
                mostaza = 1.9, topo = 0.4, aldeano = 1.0, vecina = 0.75, brote = 1.2}
local cur, pages, page = nil, nil, 1   -- the line being shown, its pages, which page

-- who is speaking, as the story names them in any language ("Yaya", "Iaia", "Granny"): which voice
local NAMES = { -- fragments of the lower-case name, in the order they are tried
  {"yaya", "yaya"}, {"iaia", "yaya"}, {"granny", "yaya"},
  {"higuera", "higuera"}, {"figuera", "higuera"}, {"mayor", "higuera"},
  {"bellota", "bellota"}, {"gla", "bellota"}, {"acorn", "bellota"},
  {"nogal", "nogal"}, {"noguer", "nogal"}, {"walnut", "nogal"},
  {"sardin", "sardina"},
  {"espanta", "espantajo"}, {"scarecrow", "espantajo"},
  {"mostaza", "mostaza"}, {"mostassa", "mostaza"}, {"mustard", "mostaza"},
  {"topo", "topo"}, {"talp", "topo"}, {"mole", "topo"},
  {"aldeano", "aldeano"}, {"vilat", "aldeano"}, {"villager", "aldeano"},
  {"vecina", "vecina"}, {"ve\195\175na", "vecina"}, {"neighbour", "vecina"},
  {"brot", "brote"}, {"sprout", "brote"},
}
local function voice_of(who)
  if not who then return voices.default end
  local k = who:lower()
  for _, n in ipairs(NAMES) do
    if k:find(n[1], 1, true) then return voices[n[2]] or voices.default end
  end
  return voices.default
end

function D.init(code)
  for name, pitch in pairs(VOICES) do voices[name] = voice.new({sound = "SFX_BLIP", pitch = pitch, spread = 2, every = 2, gain = 0.5}) end
  Game.story = Game.story or {}
  local src = file("story/" .. code .. ".txt") or file("story/es.txt")
  D.story = story.new(src, {vars = Game.story, name = code .. ".txt", ui = {
    font = FONT, color = 0, speed = 0.65, w = TW * 2, pad = 0, name_color = 0,
    blip = function(ch) return voice_of(D.story and D.story.line_ and D.story.line_.who):say(ch) end, blip_every = 1,
  }})
  cur, pages = nil, nil
end

function D.after(fn) after[#after + 1] = fn end

-- the window, th tiles tall, at the foot of the screen or at the top
local function place(th)
  if win.shown then UI.clear(win.tx, win.ty, win.tw, win.th) end
  win.th = th
  win.ty = win.top and 2 or (19 - th)
  UI.window(win.tx, win.ty, win.tw, win.th)
  win.shown = true
end

-- starts a conversation at `knot`; opts: pose (leave the hero as he is: he holds an item up)
function D.start(knot, opts)
  opts = opts or {}
  local s = D.story
  s.ui.color = Pal.tone(4)
  s.ui.name_color = Pal.tone(4)
  local h = E.hero
  win.top = h and (h.y - require("core.world").cam_y) > 76 or false
  D.active = true
  D.keep = opts.pose
  if h and not opts.pose then require("core.hero").set(h, "talk") end
  win.shown = false
  place(7)
  cur, pages, page = nil, nil, 1
  s:go(knot)
end

function D.close()
  if win.shown then UI.clear(win.tx, win.ty, win.tw, win.th) end
  win.shown = false
  D.active = false
  local h = E.hero
  if h and h.state == "talk" then require("core.hero").set(h, "walk") end
  local todo = after
  after = {}
  for _, fn in ipairs(todo) do fn() end
end

-- the words cut into lines that fit the box
local function wrap(str)
  local lines, line = {}, ""
  for word in str:gmatch("%S+") do
    local try = line == "" and word or (line .. " " .. word)
    if textw(try, FONT) > TW * 2 and line ~= "" then lines[#lines + 1] = line line = word else line = try end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

-- the line typed out with the spacing this box wants (the story's own is too close for letters 8 tall)
local function typeset(s)
  local ui = s.ui
  s.rt = rich.new(s.line_.text, {font = FONT, color = ui.color, width = TW * 2, speed = ui.speed, blip = ui.blip,
                                 blip_every = ui.blip_every, line = LINE * 2})
  s.shown, s.total = 0, s.rt.total
end

-- a new line of the story has arrived: if it is longer than the box, cut it into pages
local function paginate(s)
  local l = s.line_
  if not l or l == cur then return end
  cur, page = l, 1
  local per = l.who and 2 or 3
  local lines = wrap(l.text)
  pages = nil
  if #lines > per then
    pages = {}
    for i = 1, #lines, per do pages[#pages + 1] = table.concat(lines, " ", i, math.min(#lines, i + per - 1)) end
    l.text = pages[1]
  end
  typeset(s)
end

function D.update()
  if not D.active then return end
  local s = D.story
  if s.line_ and not s.choices_ then paginate(s) end
  -- on a page that is not the last: A shows the rest of the page, and then goes to the next page
  if pages and s.line_ and page < #pages and s.shown >= s.total and btnp("a") then
    page = page + 1
    s.line_.text = pages[page]
    typeset(s)
    return
  end
  if s.choices_ and not win.fit then
    local n = #s.choices_
    place(math.max(7, math.ceil((n * LINE + 22) / 8)))
    win.fit = true
  end
  if not s.choices_ then win.fit = false end
  if s:update() == "done" then D.close() end
end

function D.draw()
  if not D.active then return end
  local s = D.story
  if s.done then return end
  local ink = Pal.tone(4)
  local x, y = (win.tx + 1) * 8 + 4, (win.ty + 1) * 8 + 3
  if s.line_ then
    local l = s.line_
    if l.who then
      local w = textw(l.who, FONT)
      text(l.who, x * 2, y * 2, {font = FONT, color = ink})
      rect(x * 2, y * 2 + 17, w, 2, ink)
      y = y + LINE
    end
    s.rt.shown = s.shown
    s.rt:draw(x * 2, y * 2)
    if s.shown >= s.total and ticks() % 40 < 26 then
      local ax, ay = (win.tx + win.tw - 2) * 8 * 2 + 2, (win.ty + win.th - 1) * 8 * 2 - 6 + (ticks() // 20 % 2)
      tri(ax, ay, ax + 10, ay, ax + 5, ay + 6, ink)
    end
  elseif s.choices_ then
    for i, c in ipairs(s.choices_) do
      local cy = (y + (i - 1) * LINE) * 2
      if i == s.sel then tri(x * 2, cy + 5, x * 2, cy + 15, x * 2 + 7, cy + 10, ink) end
      text(c.text, x * 2 + 16, cy, {font = FONT, color = ink})
    end
  end
end

return D
