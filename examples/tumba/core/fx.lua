-- fx: the cart's effects: particles (single pixels, like pset), screen shake, and the palette fade done with pal(), the way PICO-8 carts did it.
local F = {}

-- PICO-8's colours (0..15) as 0xRRGGBB
F.P8 = {[0] = 0x000000, 0x1D2B53, 0x7E2553, 0x008751, 0xAB5236, 0x5F574F, 0xC2C3C7, 0xFFF1E8, 0xFF004D, 0xFFA300, 0xFFEC27,
        0x00E436, 0x29ADFF, 0x83769C, 0xFF77A8, 0xFFCCAA}
-- each colour darkened step by step to black (the fade tables of PICO-8 games): FADE[colour][level], level 0 = as is, 5 = black
local FADE = {
  [0] = {0, 0, 0, 0, 0, 0}, {1, 1, 1, 0, 0, 0}, {2, 2, 2, 1, 0, 0}, {3, 3, 1, 1, 0, 0}, {4, 2, 2, 1, 0, 0}, {5, 5, 1, 1, 0, 0},
  {6, 13, 5, 1, 1, 0}, {7, 6, 13, 5, 1, 0}, {8, 8, 2, 2, 1, 0}, {9, 4, 4, 2, 1, 0}, {10, 9, 4, 5, 1, 0}, {11, 3, 3, 1, 0, 0},
  {12, 12, 1, 1, 0, 0}, {13, 5, 5, 1, 1, 0}, {14, 14, 13, 5, 1, 0}, {15, 14, 13, 5, 1, 0},
}
F.level = 0 -- the fade now: 0 normal .. 5 black

-- palette entry i+1 holds colour i (0 is see-through). `swap` is a table colour -> colour shown instead (pal())
local swaps = {}
function F.apply()
  for c = 0, 15 do
    local shown = swaps[c] or c
    local f = FADE[shown][math.min(5, math.floor(F.level)) + 1]
    pal(c + 1, F.P8[f])
    pal(c + 1, F.P8[f], true)
  end
end
function F.fade(level) F.level = level F.apply() end
function F.swap(c, to) swaps[c] = to F.apply() end
function F.unswap() swaps = {} F.apply() end

-- screen shake
F.shake_t, F.shake_amp, F.sx, F.sy = 0, 0, 0, 0
function F.shake(amp, t) F.shake_amp, F.shake_t = amp, t end

-- particles
local parts = {}
function F.add(x, y, vx, vy, life, colour, size)
  parts[#parts + 1] = {x = x, y = y, vx = vx, vy = vy, life = life, max = life, c = colour, s = size or 1}
end
function F.clear() parts = {} end
function F.count() return #parts end

function F.burst(x, y, n, colours, speed, life)
  for _ = 1, n do
    local a = math.random() * 6.2832
    local sp = (0.3 + math.random()) * (speed or 1)
    F.add(x, y, math.cos(a) * sp, math.sin(a) * sp, (life or 18) + math.random(10), colours[math.random(#colours)])
  end
end

function F.update()
  if F.shake_t > 0 then
    F.shake_t = F.shake_t - 1
    local a = F.shake_amp * F.shake_t / math.max(1, F.shake_t + 4)
    F.sx, F.sy = math.floor((math.random() - 0.5) * 2 * a + 0.5), math.floor((math.random() - 0.5) * 2 * a + 0.5)
    if F.shake_t == 0 then F.sx, F.sy = 0, 0 end
  end
  for i = #parts, 1, -1 do
    local p = parts[i]
    p.x, p.y, p.vy, p.life = p.x + p.vx, p.y + p.vy, p.vy + 0.04, p.life - 1
    p.vx = p.vx * 0.97
    if p.life <= 0 then table.remove(parts, i) end
  end
end

-- the particles, in the 128x128 cart's pixels, at the screen offset ox, oy (overlay pixels; each cart pixel is 2x2)
function F.draw(ox, oy)
  for _, p in ipairs(parts) do
    local c = p.life > p.max * 0.4 and p.c or 5
    local px, py = math.floor(p.x), math.floor(p.y)
    if px >= 0 and px < 128 and py >= 0 and py < 128 then rect(ox + px * 2, oy + py * 2, 2 * p.s, 2 * p.s, F.P8[c]) end
  end
end

return F
