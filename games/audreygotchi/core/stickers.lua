-- stickers: her album, stickers earned for milestones of a life together, kept in her memory
-- (a port of audreygotchi/core/stickers.py).
--
-- The owner, 2026-10-08, from how a Tamagotchi rewards care (Uni's care icons, Pix's daily tree): something to
-- collect, so coming back has a small reward beyond the care itself. Each sticker is a milestone she already
-- remembers (memory's firsts), a game's stars, or time together. Earned once, in order, never lost; each new
-- one is heard (pegatina) and shown.
local util = require("core.util")
local M = {}

local function first(what)
  return function(s) return s.memory["first"][what] ~= nil end
end

local function all_games(s)
  local stars = s.memory["stars"]
  for _, g in ipairs(s.PLAY_OPTIONS) do
    if util.int(util.get(stars, g, 0)) < 1 then return false end
  end
  return true
end

local function three_stars(s)
  for _, v in pairs(s.memory["stars"]) do
    if util.int(v) == 3 then return true end
  end
  return false
end

M.STICKERS = {
  {"comida", first("feed")}, {"mimos", first("cuddle")}, {"bano", first("bath")},
  {"juego", first("play")}, {"encontrada", first("found")}, {"veterinario", first("vet")},
  {"favorita", first("favorite")}, {"amigo", first("friend")}, {"tesoro", first("object")},
  {"cielo", first("stars")}, {"juvenil", first("phase_Juvenil")}, {"adulta", first("phase_Adulto")},
  {"tres_estrellas", three_stars},
  {"todos_los_juegos", all_games},
  {"semana", function(s) return util.int(s.age_days) >= 7 end},
  {"mes", function(s) return util.int(s.age_days) >= 30 end},
}
M.IDS = {}
for i, st in ipairs(M.STICKERS) do M.IDS[i] = st[1] end

-- Each simulated minute: a milestone reached and not yet in her album, a new sticker.
function M.check(s)
  local earned = s.memory["stickers"]
  local new = {}
  for _, st in ipairs(M.STICKERS) do
    if not util.contains(earned, st[1]) and st[2](s) then new[#new + 1] = st[1] end
  end
  if #new == 0 then
    return
  end
  for _, id in ipairs(new) do earned[#earned + 1] = id end
  s.new_sticker, s.new_sticker_seq = new[#new], util.int(s.new_sticker_seq) + 1
  s:_emit_sound("pegatina")
  s:_log_event("Nueva pegatina")
end

return M
