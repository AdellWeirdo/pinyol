-- shapes: every figure of the glass, as polygons: the juggler, the balls and where they can be, the seven-segment digits. The glass (glass.lua)
-- draws all of them once as ghosts; the game draws only the ones that are on.
local M = {}

local GX, GY, GW, GH = 44, 36, 392, 220 -- the glass, in the screen's 480x320
M.GX, M.GY, M.GW, M.GH = GX, GY, GW, GH

-- where things are on the glass: the hands, the arc of a thrown ball (5 places between them), the fall
local HL, HR = {178, 176}, {302, 176}
local function arc(k, dir) -- ball k (1..5) going to the right (dir 1) or to the left (-1)
  local f = k / 6
  local x = HL[1] + (HR[1] - HL[1]) * (dir == 1 and f or 1 - f)
  return x, HL[2] - 4 * 104 * f * (1 - f)
end
local function drop_at(side, k) return (side == 1 and HL or HR)[1] + (side == 1 and -22 or 22), HL[2] + 8 + k * 16 end


M.HL, M.HR, M.arc, M.drop_at = HL, HR, arc, drop_at

local function ball(x, y, c) circ(math.floor(x), math.floor(y), 9, c) end

local function juggler(c, lh, rh) -- lh, rh: the left and right hand up (catching)
  rect(222, 214, 14, 38, c) rect(244, 214, 14, 38, c)                               -- the legs
  rect(214, 250, 26, 5, c) rect(240, 250, 26, 5, c)                                 -- the shoes
  poly({216, 150, 264, 150, 270, 216, 210, 216}, c)                                 -- the body
  circ(240, 128, 15, c)                                                             -- the head
  poly({222, 116, 258, 116, 252, 88, 228, 88}, c)                                   -- the top hat
  rect(214, 114, 52, 5, c)
  -- the arms, to the side of each hand
  if lh then poly({216, 156, 224, 150, 190, 128, 180, 136}, c) rect(170, 124, 18, 14, c)
  else poly({216, 156, 224, 152, 196, 190, 188, 182}, c) rect(176, 182, 20, 14, c) end
  if rh then poly({264, 156, 256, 150, 290, 128, 300, 136}, c) rect(292, 124, 18, 14, c)
  else poly({264, 156, 256, 152, 284, 190, 292, 182}, c) rect(284, 182, 20, 14, c) end
end

local SEG = {a = {2, 0, 14, 3}, b = {16, 2, 3, 14}, c = {16, 18, 3, 14}, d = {2, 32, 14, 3}, e = {-1, 18, 3, 14}, f = {-1, 2, 3, 14}, g = {2, 16, 14, 3}}
local DIGIT = {[0] = "abcdef", "bc", "abdeg", "abcdg", "bcfg", "acdfg", "acdefg", "abc", "abcdefg", "abcdfg"}
local function digit(x, y, n, c) -- seven segments; n nil: all of them (the ghost)
  for s in (n and DIGIT[n] or "abcdefg"):gmatch(".") do local r = SEG[s] rect(x + r[1], y + r[2], r[3], r[4], c) end
end
local DX, DY = 58, 46 -- where the four digits go
local function digits(str, c) for i = 1, 4 do digit(DX + (i - 1) * 26, DY, tonumber(str:sub(i, i)), c) end end
local function colon(c) rect(DX + 52 + 2, DY + 8, 6, 6, c) rect(DX + 52 + 2, DY + 24, 6, 6, c) end


M.ball, M.juggler, M.digit, M.digits, M.colon, M.DX, M.DY = ball, juggler, digit, digits, colon, DX, DY

return M
