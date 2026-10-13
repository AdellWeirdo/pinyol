-- Calle de neón: a beat-em-up, the way a Neo Geo one looks. Every pixel at the screen's full 480x320 from packed
-- pictures (art.py): a wet night street (mirrored every other time as it goes on), Kai from examples/duelo, and
-- thugs who come in groups. The street has depth: everyone walks up and down it too, and who is lower on the screen is
-- drawn in front. The camera stops at each group until it is down. A: strike. Arrows: walk.
local juice = require("juice")
local particles = require("particles")

local STREET_W = 720
local K = 0.8                         -- everyone drawn at 0.8: Kai and the thugs are 168 pixels tall in their pictures
local TOP, BOTTOM = 220, 314          -- the walkable band: where feet can be
local LEVEL_W = STREET_W * 6
local GROUPS = {                      -- where the camera stops, and who comes: {x, count}
  {300, 2}, {900, 3}, {1500, 3}, {2200, 4}, {2900, 4}, {3600, 6},
}
local STRIKE = {6, 6, 7, 7, 8, 8, 8, 9, 9, 10, 10, 10} -- Kai's strike, frame by frame (ticks)
local ACTIVE = 5                                        -- the tick it lands
local REACH, DEPTH = 100, 18                            -- how far in front, and how far up or down, a blow reaches

local fx = particles.new()
kai, thugs, cam = {}, {}, 0 -- (global: tests/calle.script reads and moves them)
state, score = "title", 0
local group, stop, timer = 1, nil, 0
local look = {}

local function reset()
  kai = {x = 120, y = 280, dir = 1, frame = 0, t = 0, act = "idle", hp = 100, hurt = 0}
  thugs, cam, group, stop, score = {}, 0, 1, nil, 0
  fx:clear()
  state, timer = "play", 0
end

function _init()
  show(0) -- no 240x160 world: every pixel at the screen's resolution
  sound("SND_HIT", "hit", 7)
  sound("SND_SWING", {wave = "noise", freq = 900, slide = -4000, sustain = 0.03, decay = 0.08, volume = 0.25})
  sound("SND_DOWN", "explosion", 5)
end

-- ------------------------------------------------------------------ fighting

local function spawn(n)
  for i = 1, n do
    local left = i % 3 == 0
    thugs[#thugs + 1] = {x = left and cam - 60 - i * 30 or cam + 540 + i * 40, y = TOP + (i * 37) % (BOTTOM - TOP),
                         dir = left and 1 or -1, hp = 3, act = "walk", t = math.random(30), frame = 1, flash = 0,
                         cool = 60 + math.random(90)}
  end
end

local function blow(from, to, push)
  to.act, to.t, to.flash, to.vx = "hurt", 0, 6, push
  sfx("SND_HIT")
  fx:burst(to.x - from.dir * 20, to.y - 110, 12, {speed = 3, life = 14, size = 2, colours = {0xFFF0A0, 0xFF6030}})
  juice.freeze(4)
  juice.shake(3)
end

local function update_kai()
  local k = kai
  k.t = k.t + 1
  if k.hurt > 0 then k.hurt = k.hurt - 1 end
  if k.act == "strike" then
    k.frame = STRIKE[math.min(k.t, #STRIKE)]
    if k.t == ACTIVE then -- everyone in front, near enough, at about the same depth
      for _, t in ipairs(thugs) do
        local d = (t.x - k.x) * k.dir
        if t.act ~= "down" and d > 0 and d < REACH and math.abs(t.y - k.y) < DEPTH then
          t.hp = t.hp - 1
          blow(k, t, k.dir * 3)
          if t.hp <= 0 then t.act, t.t = "down", 0 score = score + 300 sfx("SND_DOWN", 0.6) end
        end
      end
    end
    if k.t >= #STRIKE then k.act, k.t = "idle", 0 end
    return
  end
  if k.act == "hurt" then
    k.x = k.x + (k.vx or 0)
    if k.t >= 14 then k.act, k.t = "idle", 0 end
    k.frame = 0
    return
  end
  local dx = (btn("right") and 1 or 0) - (btn("left") and 1 or 0)
  local dy = (btn("down") and 1 or 0) - (btn("up") and 1 or 0)
  if dx ~= 0 then k.dir = dx end
  local right = stop and stop + 460 or LEVEL_W - 40
  k.x = math.max(cam + 40, math.min(right, k.x + dx * 2.4))
  k.y = math.max(TOP, math.min(BOTTOM, k.y + dy * 1.6))
  k.frame = (dx ~= 0 or dy ~= 0) and 1 + (k.t // 6) % 5 or 0
  if btnp("a") then k.act, k.t = "strike", 0 sfx("SND_SWING", 0.6) end
end

local function update_thugs()
  for i = #thugs, 1, -1 do
    local t = thugs[i]
    t.t = t.t + 1
    if t.flash > 0 then t.flash = t.flash - 1 end
    if t.act == "down" then
      t.frame, t.x = 5, t.x + (t.vx or 0) * 0.5
      if t.t > 50 then table.remove(thugs, i) end
    elseif t.act == "hurt" then
      t.frame, t.x = 5, t.x + (t.vx or 0)
      if t.t >= 16 then t.act, t.t = "walk", 0 end
    elseif t.act == "punch" then
      t.frame = 4
      if t.t == 8 and math.abs(kai.x - (t.x + t.dir * 60)) < 50 and math.abs(kai.y - t.y) < DEPTH and kai.hurt == 0 then
        kai.hp, kai.hurt = kai.hp - 8, 30
        blow(t, kai, t.dir * 2)
        if kai.hp <= 0 then state, timer = "over", 0 end
      end
      if t.t >= 20 then t.act, t.t = "walk", 0 end
    else -- walk to a spot in front of Kai, at his depth, and wait for the moment to punch
      t.dir = kai.x < t.x and -1 or 1
      local gx, gy = kai.x - t.dir * 80, kai.y
      local dx, dy = gx - t.x, gy - t.y
      local moving = math.abs(dx) > 6 or math.abs(dy) > 4
      if math.abs(dx) > 6 then t.x = t.x + (dx > 0 and 1.3 or -1.3) end
      if math.abs(dy) > 4 then t.y = t.y + (dy > 0 and 1 or -1) end
      t.frame = moving and 1 + (t.t // 8) % 3 or 0
      t.cool = t.cool - 1
      if not moving and t.cool <= 0 then t.act, t.t, t.cool = "punch", 0, 70 + math.random(80) end
    end
  end
end

-- ------------------------------------------------------------------ the loop

function _update()
  local frozen = juice.update()
  fx:update()
  timer = timer + 1
  if state == "title" then
    if btnp("a") or btnp("start") then reset() end
    return
  end
  if frozen or state ~= "play" then
    if (state == "over" or state == "clear") and timer > 90 and btnp("a") then state = "title" end
    return
  end
  update_kai()
  update_thugs()
  if not stop and GROUPS[group] and cam >= GROUPS[group][1] then -- the camera stops; the group comes
    stop = GROUPS[group][1]
    spawn(GROUPS[group][2])
    group = group + 1
  end
  if stop and #thugs == 0 then stop = nil end
  if not stop then cam = math.max(cam, math.min(LEVEL_W - 480, kai.x - 200)) end
  if not stop and not GROUPS[group] and #thugs == 0 and cam >= LEVEL_W - 480 - 40 then state, timer = "clear", 0 end
end

-- ------------------------------------------------------------------ drawing

local MIRROR = {flip_x = true}
local cast = {}

local function draw_one(c, id, ax)
  local flip = (id == "SPR_KAI") == (c.dir < 0) -- Kai faces right in his picture, a thug left
  look.frame, look.flip_x, look.scale = c.frame, flip, K
  look.tint = c.flash and c.flash > 0 and c.flash % 4 < 2 and 0xFFFFFF or (c.act == "down" and c.t % 6 < 3 and 0x401030) or nil
  local x = flip and (192 - ax) or ax
  shade(c.x - 36, c.y - 4, 72, 8) -- a shadow on the wet street
  img(id, c.x - x * K, c.y - 181 * K, look)
end

function _draw()
  if state == "title" then
    img("BG_STREET", 0, 0)
    look.frame, look.flip_x, look.scale, look.tint = 0, false, K, nil
    img("SPR_KAI", 70, 300 - 181 * K, look)
    img("SPR_THUG", 280, 300 - 181 * K, look)
    text("CALLE", 240, 30, {font = "arcade", scale = 4, align = "center", color = 0xFF60C0, gradient = 0x6040FF,
                            outline = 0x100010})
    text("DE NEON", 240, 96, {font = "arcade", scale = 2, align = "center", color = 0x60F0FF, outline = 0x100010})
    if (timer // 30) % 2 == 0 then
      text("PULSA A", 240, 140, {font = "arcade", align = "center", color = 0xFFFFFF, outline = 0x100010})
    end
    return
  end
  local ox, oy = juice.offset()
  camera(cam + ox, oy)
  local first = cam // STREET_W
  for c = first, first + 1 do
    if c % 2 == 1 then img("BG_STREET", c * STREET_W, 0, MIRROR) else img("BG_STREET", c * STREET_W, 0) end
  end
  local n = 1 -- everyone, the highest on the screen (the farthest) first
  cast[1] = kai
  for _, t in ipairs(thugs) do n = n + 1 cast[n] = t end
  for i = n + 1, #cast do cast[i] = nil end
  table.sort(cast, function(a, b) return a.y < b.y end)
  for _, c in ipairs(cast) do
    if c == kai then
      if kai.hurt % 6 < 4 then draw_one(c, "SPR_KAI", 70) end
    else draw_one(c, "SPR_THUG", 122) end
  end
  fx:draw()
  camera()
  rect(14, 12, 204, 16, 0x100010)
  rect(16, 14, math.max(0, math.floor(2 * kai.hp)), 12, 0xFF60C0)
  text("KAI", 16, 32, {font = "arcade", color = 0xFFFFFF, outline = 0x100010})
  text(string.format("%06d", score), 464, 12, {font = "arcade", scale = 2, align = "right", color = 0x60F0FF,
                                               outline = 0x100010})
  if not stop and state == "play" and timer % 60 < 40 and cam > 0 then
    text("ADELANTE >", 464, 150, {font = "arcade", align = "right", color = 0xFFE070, outline = 0x100010})
  end
  if state == "over" then
    text("FIN", 240, 120, {font = "arcade", scale = 4, align = "center", color = 0xFFFFFF, gradient = 0xFF4080,
                           outline = 0x100010})
  elseif state == "clear" then
    text("CALLE", 240, 100, {font = "arcade", scale = 3, align = "center", color = 0xFF60C0, outline = 0x100010})
    text("LIMPIA", 240, 140, {font = "arcade", scale = 3, align = "center", color = 0x60F0FF, outline = 0x100010})
  end
  juice.draw()
end
