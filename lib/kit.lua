-- kit: the game model behind pinyol's editor (editor/): a map of tiles, objects that move by themselves, events. A game
-- made in the editor is its data (data.lua: pictures, map, objects, sounds, made by the editor) and the code of its
-- blocks, which calls kit. A hand-written game can use it too.
--
--   local kit = require("kit")
--   kit.setup(require("data"))
--   kit.on("press", "a", function() kit.sound("salto") end)
--   kit.on("touch", "heroe", "moneda", function(este, otro) kit.destroy(otro) puntos = puntos + 1 end)
--   function _init() kit.init() end  function _update() kit.update() end  function _draw() kit.draw() end
--
-- Coordinates are the world's pixels (240x160 on screen at a time, each shown 2x2). The map is a grid of tiles of
-- `tile` pixels; tiles named in data.solid are walls and floors. Objects are of a kind (data.kinds) that says their
-- picture and how they move: "platformer" (the player: arrows and A to jump), "topdown" (the player: four ways),
-- "grid" (the player, a tile at a time: puzzles), "patrol" (walks and turns at walls and edges), "chase" (goes after
-- the player), "shot" (flies straight, `dir` "up", "down", "left", "right" or "forward" where its maker faces; gone at
-- a wall), "push" (a box the grid player pushes), "still". `gravity` true or false overrides the behaviour's own
-- (platformers and patrols fall). Players stay inside the world; anything else that leaves it is gone ("out"). Up
-- to three pictures go behind the map (backdrops = {{sprite = "montes", parallax = 0.3, vx = 0, vy = 0.5}}), repeated,
-- moving with the camera by their parallax (0 still, 1 with the map) and on their own by vx, vy pixels a tick.
--
-- A game is levels (data.levels = {{id, name, map, objects, background, camera, backdrops}, ...}; or one map, its
-- fields straight in data), played in order: kit.next_level() goes on, past the last one the game is won
-- (data.ending says how). data.cover = {text, subtitle, picture, tiled, background, music} is a title screen before
-- them. A level's or the cover's `music` ("MUS_x": audio/MUS_x.wav) loops while it lasts; kit.music() changes it.
-- Losing tries the level again; winning goes back to the cover.
--
-- Events: "start" (a game begins), "level" (a level begins: any, or the one named), "tick", "press" and "hold" (a
-- button), "touch" (two kinds meet), "tile" (a kind on a tile, or against a solid one), "out" (a kind leaves the
-- world), "every" (seconds), "tap" (a finger, where in the world), "clap" and "blow" (the microphone hears a sudden
-- sound, or a breath), "answer" (a question answered: which), "video_end" (a video on the whole screen is over).
--
-- Conversations: kit.say(who, text) and kit.ask(question, option, option, option) show a box at the foot of the
-- screen, a line after another, letters typed out; the game waits meanwhile; A (or a tap) goes on, up and down pick
-- an answer. Videos (video/<id>.npv): kit.video(id, "full") over the game, which waits until it ends (A skips it);
-- kit.video(id, corner) in a window, looping, while the game goes on; kit.video() takes it away. The microphone:
-- kit.mic_level() 0..100, kit.mic_note() Hz. On firmware without a microphone or video these do nothing.
--
-- Named animations: a kind's anims = {idle = {frames = {0}}, walk = {frames = {1, 2, 3}, fps = 10}, hit = {frames =
-- {4}, loop = false}} (frames from 0, as lib/anim.lua says them; fps: the kind's own pause between frames, animate, if
-- left out; loop = false stops on the last frame; {first, last} as before still works) play by themselves, walk while it moves, idle while it stands, also while a conversation waits; idle_side, walk_side,
-- idle_up and walk_up are its side and back views (idle and walk, the front), chosen by the way it last moved or
-- was turned (kit.face(o, other)); the side view looks right and is flipped to look left. kit.play(o, "hit") plays
-- the hit once, kit.play(o, "act1") an action ("act1".."act6") once: while a conversation waits, its last frame stays.
-- A kind's pivot = {x, y} (in its picture) is the point it turns round when it looks the other way. Lives:
-- kit.set_lives(n) shows hearts, kit.add_lives(-1) takes one; at none, "no_lives" fires (or the level is lost) and
-- trying the level again gives them back. kit.countdown(seconds) shows a clock; at 0, "time_up" fires (or the level
-- is lost). kit.label(key, text, where, style): "normal", "shadow", "wave", "big", "gradient". data.style =
-- {text, outline, accent, bad, heart, talk_bg, talk_edge, talk_text, talk_who, talk_dim, talk_inner} are its colours
-- (a look's palette; talk_* the conversation box's, talk_inner a second line inside its edge) and data.words its
-- sentences (its language). data.transition: blinds close and open between two levels.
local juice = require("juice")
local particles = require("particles")

local M = {}
local D = {}                         -- the game's data
local T = 16                          -- tile size
local objs, nextid = {}, 1
local handlers
local contacts = {}                   -- pairs touching last tick: "touch" fires when they start
local on_tile = {}
local labels, message, message_t = {}, nil, 0
local cam = {x = 0, y = 0}
local fx
local ended                           -- {text, won} once the game is won or lost
local timer = 0
local cells                           -- the map's tile names, row by row
local LV = {}                         -- the level being played: {id, name, map, objects, background, camera, backdrops}
local level_i = 1
local going                           -- the level to go to, once this tick is over
local trans                           -- the blinds between two levels (data.transition): {to, t, out}
local TRANS = 10                      -- ticks they take to close, and to open
local on_cover = false                -- the title screen is showing
local map_w, map_h = 1, 1             -- KIT_MAP's size: the biggest level's, so one canvas serves them all
local clock = 0

local BUTTONS = {a = true, b = true, c = true, up = true, down = true, left = true, right = true, start = true}

local lives, lives_start, countdown -- the hearts and the clock, once a block sets them (countdown in ticks)
local WORDS = {start = "Pulsa A para empezar", to_cover = "A: a la portada", again = "A: otra partida",
               retry = "A: probar otra vez", fell = "¡Te has caído!", won = "¡Has ganado!", lost = "Has perdido",
               no_lives = "¡Sin vidas!", time_up = "¡Se acabó el tiempo!"}
local STYLE = {text = 0xFFFFFF, outline = 0x202020, accent = 0xFFE070, bad = 0xFF7060, heart = 0xFF4060,
               talk_bg = 0x101820, talk_edge = 0xE8D8B0, talk_text = 0xFFFFFF, talk_who = 0xFFE070, talk_dim = 0xB8C8D8}
local W, S = WORDS, STYLE             -- the game's own (data.words, data.style), these where it says nothing

local talk                            -- what is being said: {lines = {{who, text}...}, i, shown, ask, sel}
local vid                             -- the video showing: {clip, canvas, where}
local listening, blow_t, blowing = false, 0, false -- the microphone, once a block uses it

local function reset_handlers()
  handlers = {start = {}, level = {}, tick = {}, press = {}, hold = {}, touch = {}, tile = {}, out = {}, every = {},
              tap = {}, clap = {}, blow = {}, answer = {}, video_end = {}, no_lives = {}, time_up = {}}
end
reset_handlers()

function M.setup(data)
  D = data or {}
  T = D.tile or 16
  W = setmetatable(D.words or {}, {__index = WORDS})
  S = setmetatable(D.style or {}, {__index = STYLE})
  D.kinds, D.sprites, D.solid, D.sounds = D.kinds or {}, D.sprites or {}, D.solid or {}, D.sounds or {}
  for _, k in pairs(D.kinds) do -- each named animation as its frames and the ticks each stays, worked out once
    local every = (k.animate or 0) > 0 and k.animate or 6
    for name, r in pairs(k.anims or {}) do
      if not r.frames then -- {first, last}, as games said them before
        local a, z = math.min(r[1] or 0, r[2] or 0), math.max(r[1] or 0, r[2] or 0)
        local frames = {}
        for f = a, z do frames[#frames + 1] = f end
        r = {frames = frames}
        k.anims[name] = r
      end
      r.every = r.fps and math.max(1, math.floor(60 / r.fps + 0.5)) or every
      r.loop = r.loop ~= false
    end
  end
  if not D.levels then -- one map, the way games were before levels
    D.levels = {{id = "nivel1", map = D.map, objects = D.objects, background = D.background, camera = D.camera,
                 backdrops = D.backdrops}}
  end
  level_i, LV = 1, D.levels[1] or {}
end

-- ------------------------------------------------------------------ events

-- on("start" | "tick", fn); on("level", [id,] fn); on("press" | "hold", button, fn); on("touch", kind, kind,
-- fn(this, other)); on("tile", kind, tile, fn(this, tx, ty)); on("out", kind, fn(this)); on("every", seconds, fn);
-- on("tap", fn(x, y))
function M.on(what, a, b, c)
  local list = handlers[what]
  assert(list, "kit.on: no event called " .. tostring(what))
  if what == "start" or what == "tick" then list[#list + 1] = a
  elseif what == "level" then list[#list + 1] = type(a) == "function" and {fn = a} or {id = a, fn = b}
  elseif what == "press" or what == "hold" then
    assert(BUTTONS[a], "kit.on: no button called " .. tostring(a))
    list[#list + 1] = {button = a, fn = b}
  elseif what == "touch" or what == "tile" then list[#list + 1] = {a = a, b = b, fn = c}
  elseif what == "out" then list[#list + 1] = {a = a, fn = b}
  elseif what == "every" then list[#list + 1] = {ticks = math.max(1, math.floor((tonumber(a) or 1) * 60 + 0.5)), fn = b}
  elseif what == "tap" or what == "clap" or what == "blow" or what == "video_end" or what == "no_lives"
         or what == "time_up" then list[#list + 1] = a
  elseif what == "answer" then list[#list + 1] = type(a) == "function" and {fn = a} or {n = a, fn = b} end
end

-- ------------------------------------------------------------------ talk, video, the microphone

local function talk_line()
  local l = talk and talk.lines[talk.i]
  if l then talk.shown, talk.total = 0, utf8.len(l.text) or #l.text end
end

function M.say(who, words)
  talk = talk or {lines = {}, i = 1}
  talk.lines[#talk.lines + 1] = {who = who ~= "" and who or nil, text = tostring(words)}
  if #talk.lines == 1 then talk_line() end
end

function M.ask(question, ...)
  local options = {}
  for _, o in ipairs({...}) do if tostring(o) ~= "" then options[#options + 1] = tostring(o) end end
  if #options == 0 then return end
  M.say(nil, question)
  talk.lines[#talk.lines].options = options
end

local function talk_update() -- the conversation, while there is one: true (the game waits)
  if not talk then return false end
  local l = talk.lines[talk.i]
  local _, ty, _, tapped = touch()
  local go = btnp("a") or (tapped and not l.options)
  if talk.shown < talk.total then
    talk.shown = (go or tapped) and talk.total or math.min(talk.total, talk.shown + 1)
    return true
  end
  local picked
  if l.options then
    talk.sel = talk.sel or 1
    if btnp("up") then talk.sel = (talk.sel - 2) % #l.options + 1 end
    if btnp("down") then talk.sel = talk.sel % #l.options + 1 end
    if btnp("a") then picked = talk.sel end
    if tapped and l.oy then -- a tap on an answer (where talk_draw put them)
      local row = math.floor((ty * 2 - (l.oy - l.up)) / l.step) + 1
      if row >= 1 and row <= #l.options then picked = row end
    end
    if not picked then return true end
  elseif not go then
    return true
  end
  talk.i, talk.sel = talk.i + 1, nil
  if talk.i > #talk.lines then talk = nil else talk_line() end
  if picked then for _, h in ipairs(handlers.answer) do if not h.n or h.n == picked then h.fn(picked) end end end
  return true
end

local function talk_layout(l) -- once a line: where its answers go, and how far up the box grows for all to fit
  local y = 222 + (l.who and 18 or 0)
  local _, th = text(l.text, -999, -999, {width = 420, chars = 0}) -- (measured, nothing drawn)
  local inner = S.talk_inner and 4 or 0 -- a second line inside the edge takes some room
  l.up = math.max(0, y + th - 306 + inner)
  if l.options then
    l.step = 18
    for _, o in ipairs(l.options) do l.step = math.max(l.step, select(2, text("> " .. o, -999, -999, {}))) end
    l.oy = math.max(262, y + th + 2)
    l.up = math.max(0, l.oy + #l.options * l.step - 308 + inner)
  end
end

local function talk_draw()
  if not talk then return end
  local l = talk.lines[talk.i]
  if not l.up then talk_layout(l) end
  local up = l.up
  rect(16, 214 - up, 448, 98 + up, S.talk_bg)
  box(18, 216 - up, 444, 94 + up, S.talk_edge)
  if S.talk_inner then box(22, 219 - up, 436, 88 + up, S.talk_inner) end
  local y = 222 - up
  if l.who then
    text(l.who, 30, y, {font = "bold", color = S.talk_who})
    y = y + 18
  end
  text(l.text, 30, y, {color = S.talk_text, width = 420, chars = math.floor(talk.shown)})
  if l.options and talk.shown >= talk.total then
    for i, o in ipairs(l.options) do
      local on = i == (talk.sel or 1)
      text((on and "> " or "  ") .. o, 40, l.oy - up + (i - 1) * l.step, {color = on and S.talk_who or S.talk_dim})
    end
  elseif talk.shown >= talk.total and clock % 40 < 26 then
    tri(446, 296, 456, 296, 451, 302, S.talk_edge)
  end
end

function M.video(id, where)
  if vid then vid.clip:close() vid = nil end
  if not id or not video then return end
  local canvas = "VID_" .. id
  local ok, c = pcall(video, id, {canvas = canvas, loop = where ~= "full"})
  if ok then vid = {clip = c, canvas = canvas, where = where or "full"} else log(c) end
end

local function video_update() -- a video over the whole screen: true while the game waits for it
  if not vid or vid.where ~= "full" then return false end
  if vid.clip:playing() and not btnp("a") and not select(4, touch()) then return true end
  M.video()
  for _, f in ipairs(handlers.video_end) do f() end
  return true
end

local WINDOWS = {top_left = {8, 8}, top_right = {328, 8}, bottom_left = {8, 208}, bottom_right = {328, 208}}

local function video_draw()
  if not vid then return end
  local w, h = imgsize(vid.canvas)
  if not w then return end
  if vid.where == "full" then
    local s = math.min(SCREEN_W / w, SCREEN_H / h)
    rect(0, 0, SCREEN_W, SCREEN_H, 0x000000)
    img(vid.canvas, (SCREEN_W - w * s) // 2, (SCREEN_H - h * s) // 2, {scale = s})
  else
    local at = WINDOWS[vid.where] or WINDOWS.top_right
    local s = math.min(144 / w, 104 / h)
    rect(at[1] - 2, at[2] - 2, w * s + 4, h * s + 4, 0x101010)
    img(vid.canvas, at[1], at[2], {scale = s})
  end
end

function M.mic_level()
  listening = true
  local l = mic and mic()
  return l and math.floor(l * 100 + 0.5) or 0
end

function M.mic_note()
  listening = true
  local l, p = nil, nil
  if mic then l, p = mic() end
  return l and math.floor(p + 0.5) or 0
end

local function hear() -- "clap" and "blow", for the games that listen
  if not mic or not (listening or #handlers.clap > 0 or #handlers.blow > 0) then return end
  local level, pitch, hit = mic()
  if not level then return end
  if hit then for _, f in ipairs(handlers.clap) do f() end end
  if level > 0.45 and pitch == 0 then blow_t = blow_t + 1 else blow_t = 0 end
  if level < 0.25 then blowing = false end
  if blow_t >= 8 and not blowing then
    blowing = true
    for _, f in ipairs(handlers.blow) do f() end
  end
end

-- ------------------------------------------------------------------ the map

local function tile_index(tx, ty)
  if not LV.map or tx < 0 or ty < 0 or tx >= LV.map.w or ty >= LV.map.h then return nil end
  return ty * LV.map.w + tx + 1
end

function M.tile(x, y) -- the name of the tile at a world point, or nil
  local i = tile_index(math.floor(x / T), math.floor(y / T))
  return i and cells[i] or nil
end

local function solid_at(tx, ty)
  if not LV.map then return false end
  if tx < 0 or tx >= LV.map.w then return true end -- the map's sides are walls; above and below are open
  local i = tile_index(tx, ty)
  local name = i and cells[i]
  return name ~= nil and D.solid[name] == true
end

local function world() -- its size in pixels: the map's, or one screen
  return LV.map and LV.map.w * T or 240, LV.map and LV.map.h * T or 160
end

local function free_cell(tx, ty) -- inside the map and not solid: where a grid player or a box can go
  return not LV.map or (tx >= 0 and ty >= 0 and tx < LV.map.w and ty < LV.map.h and not solid_at(tx, ty))
end

local function paint_tile(tx, ty)
  local name = cells[tile_index(tx, ty)]
  target("KIT_MAP")
  rect(tx * T, ty * T, T, T, CLEAR)
  if name and D.sprites[name] then img("SPR_" .. name, tx * T, ty * T, 0) end
  target()
end

function M.set_tile(x, y, name) -- a tile changed while playing: a door opens, a block breaks
  local tx, ty = math.floor(x / T), math.floor(y / T)
  local i = tile_index(tx, ty)
  if not i then return end
  cells[i] = (name ~= "" and name) or nil
  paint_tile(tx, ty)
end

-- ------------------------------------------------------------------ objects

local DIRS = {up = {0, -1}, down = {0, 1}, left = {-1, 0}, right = {1, 0}}

local function cell_of(o) return math.floor((o.x + o.w / 2) / T), math.floor((o.y + o.h / 2) / T) end
local function centre_in(o, cx, cy) return cx * T + (T - o.w) / 2, cy * T + (T - o.h) / 2 end

function M.spawn(kind, x, y, from) -- from: whom it comes from (a shot "forward" flies where that one faces)
  local k = D.kinds[kind]
  if not k then return nil end
  local s = D.sprites[k.sprite or kind] or {w = T, h = T, frames = 1}
  local o = {id = nextid, kind = kind, sprite = k.sprite or kind, x = x or 0, y = y or 0, w = s.w, h = s.h, vx = 0,
             vy = 0, flip = false, frame = 0, anim = 0, ground = false, alive = true, dir = 1, fx = 1, fy = 0}
  nextid = nextid + 1
  local b = k.behaviour
  if b == "patrol" then o.vx = k.speed or 1 end
  if b == "shot" then
    local d = DIRS[k.dir or "forward"]
    local fx, fy = 1, 0
    if d then fx, fy = d[1], d[2] elseif from then fx, fy = from.fx, from.fy end
    local n = math.sqrt(fx * fx + fy * fy)
    o.vx, o.vy, o.flip = fx / n * (k.speed or 3), fy / n * (k.speed or 3), fx < 0
  end
  if b == "grid" or b == "push" then o.x, o.y = centre_in(o, cell_of(o)) end
  objs[#objs + 1] = o
  return o
end

function M.destroy(o) if o then o.alive = false end end

function M.all(kind)
  local list = {}
  for _, o in ipairs(objs) do if o.alive and (not kind or o.kind == kind) then list[#list + 1] = o end end
  return list
end

function M.first(kind)
  for _, o in ipairs(objs) do if o.alive and o.kind == kind then return o end end
end

function M.count(kind) return #M.all(kind) end

function M.player() -- whom the camera follows, or the first player-like object
  if LV.camera then
    local o = M.first(LV.camera)
    if o then return o end
  end
  for _, o in ipairs(objs) do
    local b = o.alive and D.kinds[o.kind] and D.kinds[o.kind].behaviour
    if b == "platformer" or b == "topdown" then return o end
  end
end

function M.set_sprite(o, name) if o and D.sprites[name] then o.sprite = name end end
function M.play(o, name) -- a named animation once: "hit", or an action "act1".."act6" (walk and idle play by themselves)
  local k = o and D.kinds[o.kind]
  local r = k and k.anims and k.anims[name]
  if not r then return end
  local t = #r.frames * r.every
  if name == "hit" then o.hit_t = t else o.act, o.act_t = name, t end
end
function M.face(o, t) -- o turns towards t: its side, back or front view, as its drawing has them
  if not (o and t and o ~= t) then return end
  local dx, dy = (t.x + t.w / 2) - (o.x + o.w / 2), (t.y + t.h / 2) - (o.y + o.h / 2)
  if math.abs(dx) > math.abs(dy) then o.view, o.flip, o.fx, o.fy = "side", dx < 0, dx < 0 and -1 or 1, 0
  else o.view, o.fx, o.fy = dy < 0 and "up" or "down", 0, dy < 0 and -1 or 1 end
end

-- lives and a countdown: shown once set
function M.set_lives(n) lives = math.max(0, math.min(99, math.floor(tonumber(n) or 0))) lives_start = lives end
function M.lives() return lives or 0 end
function M.add_lives(n)
  if not lives then return end
  local before = lives
  lives = math.max(0, math.min(99, lives + math.floor(tonumber(n) or 0)))
  if before > 0 and lives == 0 then
    if #handlers.no_lives > 0 then for _, f in ipairs(handlers.no_lives) do f() end else M.lose(W.no_lives) end
  end
end
function M.countdown(seconds) countdown = math.max(0, math.floor((tonumber(seconds) or 0) * 60 + 0.5)) end
function M.add_time(seconds)
  if countdown then countdown = math.max(0, countdown + math.floor((tonumber(seconds) or 0) * 60 + 0.5)) end
end
function M.time_left() return countdown and (countdown + 59) // 60 or 0 end
function M.stop_countdown() countdown = nil end

-- what the blocks read and change: an object that is not there (nil, or gone) is quietly left alone
local PROPS = {x = true, y = true, vx = true, vy = true}
function M.get(o, prop) return o and PROPS[prop] and o[prop] or 0 end
function M.set(o, prop, v) if o and o.alive and PROPS[prop] then o[prop] = tonumber(v) or 0 end end
function M.change(o, prop, dv) if o and o.alive and PROPS[prop] then o[prop] = o[prop] + (tonumber(dv) or 0) end end
function M.spawn_at(kind, o) -- a new one where another is (a shot from the player, a coin where an enemy was)
  if not o then return nil end
  local n = M.spawn(kind, o.x + (o.w - (D.sprites[kind] or o).w) / 2, o.y + (o.h - (D.sprites[kind] or o).h) / 2, o)
  if n and o.flip and (D.kinds[kind] or {}).behaviour ~= "shot" then n.flip = true end
  return n
end

-- moving with the map's walls in the way: one axis then the other, stopped at the tile's edge
local function hits_wall(x, y, w, h) -- the box [x, x + w) x [y, y + h): positions have fractions
  for ty = math.floor(y / T), math.floor((y + h - 0.001) / T) do
    for tx = math.floor(x / T), math.floor((x + w - 0.001) / T) do
      if solid_at(tx, ty) then return true end
    end
  end
  return false
end

local function move(o, solid)
  o.ground = false
  if not solid then o.x, o.y = o.x + o.vx, o.y + o.vy return end
  local hit = false
  local nx = o.x + o.vx
  if hits_wall(nx, o.y, o.w, o.h) then
    nx = o.vx > 0 and math.floor((nx + o.w) / T) * T - o.w or (math.floor(nx / T) + 1) * T
    if hits_wall(nx, o.y, o.w, o.h) then nx = o.x end
    o.vx, hit = 0, true
  end
  o.x = nx
  local ny = o.y + o.vy
  if hits_wall(o.x, ny, o.w, o.h) then
    if o.vy > 0 then
      ny = math.floor((ny + o.h) / T) * T - o.h
      o.ground = true
    else
      ny = (math.floor(ny / T) + 1) * T
    end
    if hits_wall(o.x, ny, o.w, o.h) then ny = o.y end
    o.vy, hit = 0, true
  end
  o.y = ny
  return hit
end

local function box_at(cx, cy) -- a box ("push") in that cell, or on its way to it
  for _, p in ipairs(objs) do
    if p.alive and (D.kinds[p.kind] or {}).behaviour == "push" then
      local px, py = cell_of(p)
      if (p.tx or px) == cx and (p.ty or py) == cy then return p end
    end
  end
end

local function slide(o, cx, cy, step) o.tx, o.ty, o.step = cx, cy, step end -- there over the next ticks

local function sliding(o) -- a step of a grid move; true while it lasts
  if not o.tx then return false end
  local gx, gy = centre_in(o, o.tx, o.ty)
  local dx, dy, st = gx - o.x, gy - o.y, o.step or 2
  if math.abs(dx) <= st and math.abs(dy) <= st then
    o.x, o.y, o.tx, o.ty, o.vx, o.vy = gx, gy, nil, nil, 0, 0
  else
    o.vx, o.vy = dx > 0 and st or dx < 0 and -st or 0, dy > 0 and st or dy < 0 and -st or 0
    o.x, o.y = o.x + o.vx, o.y + o.vy
  end
  return true
end

local SETTLE = 20 -- ticks a level starts with its players still: an arrow held from the last level moves nothing
local function arrow(name) return timer >= SETTLE and btn(name) end

local function grid_step(o, speed) -- an arrow held: a cell that way, pushing a box if there is room behind it
  local dx = (arrow("right") and 1 or 0) - (arrow("left") and 1 or 0)
  local dy = dx == 0 and ((arrow("down") and 1 or 0) - (arrow("up") and 1 or 0)) or 0
  if dx == 0 and dy == 0 then return end
  o.fx, o.fy = dx, dy
  if dx ~= 0 then o.flip = dx < 0 end
  o.view = dy < 0 and "up" or dy > 0 and "down" or "side"
  local cx, cy = cell_of(o)
  local nx, ny = cx + dx, cy + dy
  if not free_cell(nx, ny) then return end
  local box = box_at(nx, ny)
  if box then
    if not free_cell(nx + dx, ny + dy) or box_at(nx + dx, ny + dy) then return end
    slide(box, nx + dx, ny + dy, speed)
  end
  slide(o, nx, ny, speed)
end

local function anim_range(a, o, moving) -- the named animation it is in: an action, a hit, or idle/walk its way
  if (o.act_t or 0) > 0 and a[o.act] then return a[o.act] end
  if (o.hit_t or 0) > 0 and a.hit then return a.hit end
  local v = o.view == "up" and "_up" or o.view == "side" and "_side" or "" -- down: the plain idle and walk
  if moving then return a["walk" .. v] or a.walk or a["idle" .. v] or a.idle end
  return a["idle" .. v] or a.idle
end

local function animate(o, still) -- its frame this tick; still: the game waits (a conversation), nobody walks
  local k = D.kinds[o.kind] or {}
  local b = k.behaviour or "still"
  local moving = not still and (o.vx ~= 0 or o.vy ~= 0)
  if k.anims then -- named: walk while it moves, idle while it stands, a hit or an action once when told
    local s = D.sprites[o.sprite]
    local last = (s and s.frames or 1) - 1
    local r = anim_range(k.anims, o, moving)
    if (o.hit_t or 0) > 0 then o.hit_t = o.hit_t - 1 end
    local every = r and r.every or ((k.animate or 0) > 0 and k.animate or 6)
    local hold = still and (o.act_t or 0) > 0 and o.act_t <= every -- an action's last frame waits for the conversation
    if (o.act_t or 0) > 0 and not hold then o.act_t = o.act_t - 1 end
    if r ~= o.anim_r then o.anim_r, o.anim = r, 0 end -- a new animation starts from its first frame
    if not hold then o.anim = o.anim + 1 end
    local i = (o.anim - 1) // every
    if r then -- going round, or stopped on its last frame
      i = r.loop and i % #r.frames or math.max(0, math.min(i, #r.frames - 1))
      o.frame = math.max(0, math.min(r.frames[i + 1], last))
    else o.frame = i % (last + 1) end
  elseif (k.animate or 0) > 0 then -- frames go round while it moves (or always, for things that are not players)
    local player = b == "platformer" or b == "topdown" or b == "grid" or b == "push"
    o.anim = (moving or not player) and o.anim + 1 or 0
    local s = D.sprites[o.sprite]
    o.frame = s and s.frames > 1 and (o.anim // k.animate) % s.frames or 0
  end
end

local function behave(o)
  local k = D.kinds[o.kind] or {}
  local b, speed = k.behaviour or "still", k.speed or 1.5
  local gravity = k.gravity
  if gravity == nil then gravity = b == "platformer" or b == "patrol" end
  if b == "grid" or b == "push" then -- moves a cell at a time, by itself never
    if not sliding(o) and b == "grid" then grid_step(o, math.max(0.5, speed)) sliding(o) end
  elseif b == "platformer" then
    local dx = (arrow("right") and 1 or 0) - (arrow("left") and 1 or 0)
    o.vx = dx * speed
    if dx ~= 0 then o.flip, o.fx, o.fy = dx < 0, dx, 0 end
    if timer >= SETTLE and btnp("a") and o.ground then o.vy = -(k.jump or 4.5) end
  elseif b == "topdown" then
    local dx = (arrow("right") and 1 or 0) - (arrow("left") and 1 or 0)
    local dy = (arrow("down") and 1 or 0) - (arrow("up") and 1 or 0)
    local n = (dx ~= 0 and dy ~= 0) and 0.7071 or 1 -- diagonals no faster
    o.vx, o.vy = dx * speed * n, dy * speed * n
    if dx ~= 0 or dy ~= 0 then o.fx, o.fy = dx, dy end
    if dx ~= 0 then o.flip = dx < 0 end
    if dy ~= 0 then o.view = dy < 0 and "up" or "down" elseif dx ~= 0 then o.view = "side" end
  elseif b == "patrol" then
    if o.vx == 0 then o.dir = -o.dir end
    if gravity and o.ground then -- turns at the edge of what it walks on
      local ahead = o.dir > 0 and o.x + o.w + 1 or o.x - 1
      if not solid_at(math.floor(ahead / T), math.floor((o.y + o.h + 1) / T)) then o.dir = -o.dir end
    end
    o.vx = o.dir * speed
    o.flip = o.dir < 0
  elseif b == "chase" then
    local p = M.player()
    if p and p ~= o then
      local dx, dy = p.x - o.x, p.y - o.y
      local d = math.sqrt(dx * dx + dy * dy)
      if d > 1 then
        o.vx = dx / d * speed
        if not gravity then o.vy = dy / d * speed end
        o.flip = dx < 0
      end
    end
  end
  if b ~= "grid" and b ~= "push" then
    if gravity then o.vy = math.min(o.vy + (k.weight or 0.25), 6) end
    local wall = move(o, k.solid ~= false and b ~= "shot")
    if b == "shot" and (wall or (LV.map and hits_wall(o.x, o.y, o.w, o.h))) then o.alive = false end
  end
  local W, H = world() -- players stay inside the world (a platformer may still fall out of the bottom)
  if b == "platformer" or b == "topdown" or b == "grid" then o.x = math.max(0, math.min(W - o.w, o.x)) end
  if b == "topdown" or b == "grid" then o.y = math.max(0, math.min(H - o.h, o.y)) end
  animate(o, false)
end

local function overlap(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- ------------------------------------------------------------------ what the blocks do besides

function M.label(key, text, where, style) -- a text on the screen from now on (where: "top_left", "top", "top_right",
  if text == nil then labels[key] = nil return end            -- "bottom"...; style: "normal", "shadow", "wave", "big"...)
  labels[key] = {text = tostring(text), where = where or "top_left", style = style}
end

function M.message(text, seconds) message, message_t = tostring(text), math.floor((seconds or 2) * 60) end

function M.sound(name) -- made from numbers (SND_), or brought in from a file (its own name, SFX_)
  local p = D.sounds[name]
  if p then sfx(p.file or "SND_" .. name) end
end

local tune -- the music playing (audio/MUS_*.wav, read from the card as it plays), or nil
function M.music(id) -- "MUS_x" or "x"; nil stops it. The same one again goes on where it is
  if id and id:sub(1, 4) ~= "MUS_" then id = "MUS_" .. id end
  if id ~= tune then tune = id music(id) end
end
function M.playing() return tune end

function M.shake(px) juice.shake(px or 4) end

function M.burst(x, y, colour, n)
  fx:burst(x, y, n or 16, {speed = 2, colours = {colour or 0xFFE070, 0xFFFFFF}, gravity = 0.06, life = 30, size = 2})
end
function M.burst_at(o, colour) if o then M.burst(o.x + o.w / 2, o.y + o.h / 2, colour) end end

function M.win(text) ended = {text = text or W.won, won = true} M.sound("ganar") end
function M.lose(text) ended = {text = text or W.lost, won = false} M.sound("perder") end

-- levels: changed once this tick is over (a touch that sends to the next level is in the middle of the objects)
function M.goto_level(which)
  for i, l in ipairs(D.levels) do if i == which or l.id == which then going = i return end end
end
function M.next_level()
  if level_i < #D.levels then going = level_i + 1 else M.win(D.ending) end
end
function M.level() return LV.id end
function M.retry() going = level_i end -- the level from its start

function M.count_on(kind, tile) -- how many of a kind stand (not still moving) on a tile: boxes on their marks
  local n = 0
  for _, o in ipairs(objs) do
    if o.alive and o.kind == kind and not o.tx then
      local i = tile_index(cell_of(o))
      if i and cells[i] == tile then n = n + 1 end
    end
  end
  return n
end
function M.state() -- "cover", "play", "won" or "lost"
  return on_cover and "cover" or ended and (ended.won and "won" or "lost") or "play"
end

-- ------------------------------------------------------------------ the loop

local function start_level(first) -- the level LV from its start; first: a game begins with it
  objs, contacts, on_tile, message, ended, timer, going = {}, {}, {}, nil, nil, 0, nil
  countdown = nil                                   -- each level sets its own clock
  if lives and lives <= 0 then lives = lives_start end -- out of lives: trying again gives them back
  cells, talk = {}, nil
  backdrop(LV.background or 0x6CB4E0)
  local layers = 0
  if LV.map then
    for i = 1, LV.map.w * LV.map.h do
      local t = LV.map.cells[i] or 0
      cells[i] = t > 0 and LV.map.tiles[t] or nil
    end
    canvas("KIT_MAP", map_w, map_h) -- cleared
    for ty = 0, LV.map.h - 1 do for tx = 0, LV.map.w - 1 do if cells[tile_index(tx, ty)] then paint_tile(tx, ty) end end end
    bg(0, {image = "KIT_MAP", wrap = false})
    layers = BG0
  end
  for i = 1, 3 do -- pictures behind the map, repeated, moving slower than it
    local b = (LV.backdrops or {})[i]
    if b and D.sprites[b.sprite] then
      bg(i, {image = "SPR_" .. b.sprite})
      layers = layers | ({BG1, BG2, BG3})[i]
    else
      bg(i)
    end
  end
  show(layers)
  for _, p in ipairs(LV.objects or {}) do M.spawn(p.kind, p.x, p.y) end
  fx = particles.new()
  juice.reset()
  M.music(LV.music) -- its own, or silence
  if #D.levels > 1 and LV.name then M.message(LV.name, 1.5) end
  if first then for _, f in ipairs(handlers.start) do f() end end
  for _, h in ipairs(handlers.level) do if not h.id or h.id == LV.id then h.fn() end end
end

local function play_level(i, first)
  level_i, LV, on_cover = i, D.levels[i] or {}, false
  start_level(first)
end

local function begin_game(which) -- labels last the whole game; "start" fires once the first level is there
  labels, lives, lives_start, countdown, trans = {}, nil, nil, nil, nil
  M.video()
  local i = 1
  for k, l in ipairs(D.levels) do if k == which or l.id == which then i = k end end
  play_level(i, true)
end

local function show_cover()
  local c = D.cover
  on_cover, objs, ended, message, going = true, {}, nil, nil, nil
  backdrop(c.background or 0x1D2B53)
  M.music(c.music)
  if c.tiled and c.picture and D.sprites[c.picture] then -- a picture made to repeat, as behind a level
    bg(1, {image = "SPR_" .. c.picture})
    scroll(1, 0, 0)
    show(BG1)
  else
    show(0)
  end
end

function M.init()
  for _, l in ipairs(D.levels) do
    if l.map then map_w, map_h = math.max(map_w, l.map.w * T), math.max(map_h, l.map.h * T) end
  end
  for name, p in pairs(D.sounds) do -- {recipe = "coin", seed = 3}, the numbers themselves, or {file = "SFX_x"}
    if p.recipe then sound("SND_" .. name, p.recipe, p.seed or 1) elseif not p.file then sound("SND_" .. name, p) end
  end
  if not D.sounds.ganar then D.sounds.ganar = sound("SND_ganar", "powerup", 4) end
  if not D.sounds.perder then D.sounds.perder = sound("SND_perder", "hit", 9) end
  if D.cover and not D.start then show_cover() else begin_game(D.start) end
end

function M.restart() begin_game() end -- the game from its first level

local function pair_key(a, b) return a.id * 65536 + b.id end

function M.update()
  clock = clock + 1
  local again = btnp("a") or btnp("start") or select(4, touch())
  if on_cover then
    if again then begin_game() end
    return
  end
  if ended then
    if again then
      if not ended.won then start_level(false) -- the same level again
      elseif D.cover then show_cover()
      else begin_game() end
    end
    return
  end
  if trans then -- between two levels: the blinds close, the next level comes, they open
    trans.t = trans.t + 1
    for _, o in ipairs(objs) do if o.alive then animate(o, true) end end
    if trans.t >= TRANS then if trans.out then play_level(trans.to, false) trans = {t = 0} else trans = nil end end
    return
  end
  if video_update() or talk_update() then -- a video or a conversation: the game waits, what is drawn still breathes
    for _, o in ipairs(objs) do if o.alive then animate(o, true) end end
    return
  end
  if juice.update() then return end
  timer = timer + 1
  if countdown and countdown > 0 then
    countdown = countdown - 1
    if countdown == 0 then
      if #handlers.time_up > 0 then for _, f in ipairs(handlers.time_up) do f() end else M.lose(W.time_up) end
    end
  end
  hear()
  for _, h in ipairs(handlers.press) do if btnp(h.button) then h.fn() end end
  for _, h in ipairs(handlers.hold) do if btn(h.button) then h.fn() end end
  local tx, ty, _, tapped = touch()
  if tapped then for _, f in ipairs(handlers.tap) do f(tx + cam.x, ty + cam.y) end end
  local player = M.player()
  for _, o in ipairs(objs) do if o.alive then behave(o) end end
  local ww, wh = world() -- (not W: that is the game's words, used just below)
  for _, o in ipairs(objs) do -- whatever leaves the world is gone; the player falling out loses, unless told otherwise
    if o.alive and (o.x + o.w < -32 or o.x > ww + 32 or o.y + o.h < -32 or o.y > wh + 32) then
      o.alive = false
      local told = false
      for _, h in ipairs(handlers.out) do if h.a == o.kind then h.fn(o) told = true end end
      if o == player and not told and not ended then M.lose(W.fell) end
    end
  end
  local now = {}
  for _, h in ipairs(handlers.touch) do -- each pair once, when it starts touching
    for _, a in ipairs(objs) do
      if a.alive and a.kind == h.a then
        for _, b in ipairs(objs) do
          if b.alive and b ~= a and b.kind == h.b and overlap(a, b) then
            local k = pair_key(a, b)
            now[k] = true
            if not contacts[k] then h.fn(a, b) end
          end
        end
      end
    end
  end
  contacts = now
  local tiles_now = {}
  for _, h in ipairs(handlers.tile) do -- on a tile, or against a solid one (a wall, a door, the floor underfoot)
    local reach = D.solid[h.b] and 1 or 0
    for _, o in ipairs(objs) do
      if o.alive and o.kind == h.a then
        for cy = math.floor((o.y - reach) / T), math.floor((o.y + o.h + reach - 0.001) / T) do
          for cx = math.floor((o.x - reach) / T), math.floor((o.x + o.w + reach - 0.001) / T) do
            local i = tile_index(cx, cy)
            if i and cells[i] == h.b then
              local k = o.id * 100000 + i
              tiles_now[k] = true
              if not on_tile[k] then h.fn(o, cx * T, cy * T) end
            end
          end
        end
      end
    end
  end
  on_tile = tiles_now
  for _, h in ipairs(handlers.every) do if timer % h.ticks == 0 then h.fn() end end
  for _, f in ipairs(handlers.tick) do f() end
  for i = #objs, 1, -1 do if not objs[i].alive then table.remove(objs, i) end end
  fx:update()
  if message_t > 0 then message_t = message_t - 1 end
  local p = M.player() -- the camera: on the player, within the map
  if p then
    local mw, mh = LV.map and LV.map.w * T or 240, LV.map and LV.map.h * T or 160
    cam.x = math.max(0, math.min(mw - 240, math.floor(p.x + p.w / 2 - 120)))
    cam.y = math.max(0, math.min(mh - 160, math.floor(p.y + p.h / 2 - 80)))
  end
  if going and not ended then
    if D.transition then trans, going = {to = going, t = 0, out = true}, nil else play_level(going, false) end
  end
end

local PLACES = {top_left = {12, 8, "left"}, top = {240, 8, "center"}, top_right = {468, 8, "right"},
                bottom = {240, 290, "center"}, bottom_left = {12, 290, "left"}, bottom_right = {468, 290, "right"}}

local function label_style(style, align) -- a label's options for text()
  local o = {font = "bold", color = S.text, outline = S.outline, align = align}
  if style == "shadow" then o.outline, o.shadow, o.shadow_x, o.shadow_y = nil, S.outline, 1, 1
  elseif style == "wave" then o.wave = 2
  elseif style == "big" then o.font = "large_bold"
  elseif style == "gradient" then o.gradient = S.accent end
  return o
end

local HEART = {".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."}
local function draw_hearts(n, y) -- at the top right, 2 screen pixels a dot, outlined
  local shown = math.min(n, 8)
  for i = 1, shown do
    local x = 468 - i * 18 + 4
    for pass = 1, 2 do
      for r, row in ipairs(HEART) do
        for c = 1, #row do
          if row:sub(c, c) == "X" then
            if pass == 1 then rect(x + (c - 1) * 2 - 2, y + (r - 1) * 2 - 2, 6, 6, S.outline)
            else rect(x + (c - 1) * 2, y + (r - 1) * 2, 2, 2, S.heart) end
          end
        end
      end
    end
    rect(x + 2, y + 2, 2, 2, S.text)
  end
  if n > shown then text("x" .. n, 468 - shown * 18 - 4, y - 2, {font = "bold", color = S.text, outline = S.outline, align = "right"}) end
end

local function draw_cover()
  local c = D.cover
  local s = not c.tiled and c.picture and D.sprites[c.picture]
  if s and s.h <= 50 then -- a character: in the band between the title and the line under it, up to 6 times
    local k = math.max(1, math.min(6, 100 // s.h, SCREEN_W // s.w))
    img("SPR_" .. c.picture, (SCREEN_W - s.w * k) // 2, 128 + (100 - s.h * k) // 2, {frame = 0, scale = k})
  elseif s then -- a picture: as big as fits, in whole steps, the title over it
    local k = math.max(1, math.min(SCREEN_W // s.w, SCREEN_H // s.h))
    img("SPR_" .. c.picture, (SCREEN_W - s.w * k) // 2, (SCREEN_H - s.h * k) // 2, {frame = 0, scale = k})
  end
  text(c.text or D.title or "", SCREEN_W // 2, 80, {font = "large_bold", scale = 2, color = S.text, outline = S.outline,
                                                   align = "center", width = 440})
  if (clock // 30) % 2 == 0 then
    text(c.subtitle or W.start, SCREEN_W // 2, 236, {font = "bold", color = S.accent, outline = S.outline, align = "center"})
  end
end

function M.draw()
  if on_cover then draw_cover() return end
  local sx, sy = juice.offset()
  if LV.map then scroll(0, cam.x - sx // 2, cam.y - sy // 2) end
  for i, b in ipairs(LV.backdrops or {}) do -- parallax 0: still; 1: with the map
    if i <= 3 then
      local p = b.parallax or 0.5
      scroll(i, math.floor(cam.x * p - clock * (b.vx or 0)) - sx // 2, math.floor(cam.y * p - clock * (b.vy or 0)) - sy // 2)
    end
  end
  for _, o in ipairs(objs) do
    if o.alive then
      local x, y = (o.x - cam.x) * 2 + sx, (o.y - cam.y) * 2 + sy
      if x > -64 and x < SCREEN_W + 64 and y > -64 and y < SCREEN_H + 64 then
        local k = D.kinds[o.kind]
        local views = k and k.anims and (k.anims.idle_up or k.anims.walk_up or k.anims.idle_side or k.anims.walk_side)
        if o.flip and not (views and o.view ~= "side") then -- with views, only the side one is flipped
          local s = D.sprites[o.sprite] -- round its pivot, if it has one: that point stays where it was
          if k and k.pivot and s then x = x + (2 * k.pivot[1] - s.w + 1) * 2 end
          img("SPR_" .. o.sprite, x, y, {frame = o.frame, scale = 2, flip_x = true})
        else img("SPR_" .. o.sprite, x, y, o.frame, 2) end
      end
    end
  end
  camera((cam.x * 2 - sx), (cam.y * 2 - sy))
  local g = fx -- the particles are in world pixels: drawn 2x by hand
  for _, p in ipairs(g.list) do
    local age = 1 - p.left / p.life
    circ(p.x * 2, p.y * 2, math.max(1, p.size * 2 * (1 - age)), p.colours[math.min(#p.colours, 1 + math.floor(age * #p.colours))])
  end
  camera()
  for _, l in pairs(labels) do
    local at = PLACES[l.where] or PLACES.top_left
    text(l.text, at[1], at[2], label_style(l.style, at[3]))
  end
  if lives then draw_hearts(lives, labels.top_right and 34 or 10) end
  if countdown then
    local left = (countdown + 59) // 60
    local o = label_style(nil, "center")
    if left <= 10 then o.color = (clock // 15) % 2 == 0 and S.bad or S.text end
    text(string.format("%d:%02d", left // 60, left % 60), SCREEN_W // 2, labels.top and 32 or 8, o)
  end
  if message and message_t > 0 and not ended then
    text(message, SCREEN_W // 2, 140, {font = "large_bold", color = S.text, outline = S.outline, align = "center",
                                       width = 440})
  end
  video_draw()
  if trans then -- ten blinds in the look's darkest colour
    local h = math.floor(32 * (trans.out and trans.t / TRANS or 1 - trans.t / TRANS) + 0.5)
    if h > 0 then for y = 0, SCREEN_H - 1, 32 do rect(0, y, SCREEN_W, h, S.outline) end end
  end
  talk_draw()
  if ended then
    shade(0, 0, SCREEN_W, SCREEN_H)
    text(ended.text, SCREEN_W // 2, 120, {font = "large_bold", color = ended.won and S.accent or S.bad,
                                          outline = S.outline, align = "center", width = 440})
    text(ended.won and (D.cover and W.to_cover or W.again) or W.retry, SCREEN_W // 2, 180,
         {font = "bold", color = S.text, outline = S.outline, align = "center"})
  end
  juice.draw()
end

-- for tests and the editor's preview
function M.objects() return objs end
function M.camera_at() return cam.x, cam.y end
function M.reset_events() reset_handlers() end

return M
