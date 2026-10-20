-- The corridor and who is in it, beat by beat: the band comes out of the lift and follows; the candidate sits, stands,
-- walks, doubts, walks on and knocks. Everyone stands against the wall, feet on FEET (art.py makes them to that size).
local M = {}

local FEET = 205
local LIFT_FEET = 200                      -- the lift's floor, a little higher
local PERSON_AX, PERSON_AY = 60, 109       -- SPR_PERSONA's feet in its 120x112 frame
local BAND_AX, BAND_AY = 52, 103           -- SPR_BANDA's, 104x104
local POSE = {sit = 0, stand = 1, walk = 2, doubt = 3, knock = 4}
local DOOR = {x = 398, y = 70, w = 57, h = 122}

local function lerp(a, b, f) return a + (b - a) * math.max(0, math.min(1, f)) end
local function between(t, t0, t1) return (t - t0) / (t1 - t0) end

-- Where the band is at beat t: x, feet, shown
local function band_at(t)
  if t < 2 then return 68, LIFT_FEET, false end
  if t < 12 then return 68, LIFT_FEET, true end
  if t < 16 then return lerp(68, 120, between(t, 12, 16)), lerp(LIFT_FEET, FEET, between(t, 12, 16)), true end
  if t < 48 then return lerp(120, 190, between(t, 16, 48)), FEET, true end
  if t < 80 then return lerp(190, 215, between(t, 48, 80)), FEET, true end
  return lerp(215, 300, between(t, 80, 108)), FEET, true
end

-- The candidate at beat t: x, pose
local function person_at(t)
  if t < 16 then return 205, POSE.sit end
  if t < 18 then return 205, POSE.stand end
  if t < 48 then return lerp(205, 300, between(t, 18, 48)), POSE.walk end
  if t < 80 then return 300, POSE.doubt end
  if t < 104 then return lerp(300, 372, between(t, 80, 104)), POSE.walk end
  return 372, POSE.knock
end

-- beat: the song's beat (or the last one, at the end); energy 0..1; hop: ticks since the candidate was cheered;
-- enter: 0..1 of the way through the door at the end (nil while playing)
function M.draw(beat, energy, hop, enter)
  img("BG_PASILLO", 0, 0)
  local swing = beat % 1 < 0.18 and 1 or 0 -- everyone moves on the beat
  if enter then -- the door open: the room's warm light
    rect(DOOR.x, DOOR.y, DOOR.w, DOOR.h, 0xFFE7B0)
    rect(DOOR.x, DOOR.y, 6, DOOR.h, 0x6B3A1E)
  end
  local bx, bfeet, shown = band_at(beat)
  if shown then
    local jump = math.floor(swing * (2 + 4 * energy))
    img("SPR_BANDA", math.floor(bx) - BAND_AX, math.floor(bfeet) - BAND_AY - jump)
  end
  local px, pose = person_at(beat)
  local lift = hop > 0 and math.floor(hop / 3) or 0
  if pose == POSE.walk then lift = lift + swing * 2 end
  if enter then
    px, pose = lerp(372, 430, enter), POSE.walk
    local a = math.max(0, 1 - enter * 1.4)
    if a > 0 then img("SPR_PERSONA", math.floor(px) - PERSON_AX, FEET - PERSON_AY, {frame = pose, alpha = a}) end
  else
    img("SPR_PERSONA", math.floor(px) - PERSON_AX, FEET - PERSON_AY - lift, {frame = pose})
  end
  plate(DOOR.x - 6, 50, DOOR.w + 12, 18, 0xF4EAD2) -- the door's sign
end

-- The encouragement meter across the top
function M.meter(energy, label)
  local x, y, w = 140, 4, 180
  rect(x - 6, y - 2, w + 90, 26, 0x1A1420)
  text(label, x, y + 2, {font = "comic_beatemup_body", color = 0xFFE9B0})
  local bx, bw = x + 76, w
  rect(bx, y + 5, bw, 12, 0x3A3044)
  local fill = math.floor(bw * energy)
  local col = energy > 0.66 and 0x6FD06A or energy > 0.33 and 0xF2C033 or 0xE0605A
  rect(bx, y + 5, fill, 12, col)
end

M.DOOR = DOOR
return M
