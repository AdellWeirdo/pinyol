-- explain: "Cómo funciona", from the console's menu. It takes the strokes of the frame that was on the screen and
-- draws them again slowly, the way the beam did: one line after another, a bright head where it is now, the older
-- ones fading as the phosphor does, and the path it takes between lines with the beam off.
local V = require("vec")
local lang = require("lang")
local E = {}

E.hook = function(id) end
local OX, OY, K = 16, 58, 0.45   -- where the small copy of the screen goes, and its scale
local SPEEDS = {1, 2, 4, 8, 16, 32}
local list, n, idx, speed_i, hold, mult = {}, 0, 0, 3, 0, 0

function E.enter(back)
  E.back = back
  list, n = V.snapshot()
  idx, speed_i, hold, mult = 0, 3, 0, 0
  E.hook("curioso")
end

-- true when the player is done
function E.update()
  if btnp("left") then speed_i = math.max(1, speed_i - 1) end
  if btnp("right") then speed_i = math.min(#SPEEDS, speed_i + 1) end
  if btnp("a") then idx, hold, mult = 0, 0, 0 end
  if btnp("up") then mult = (mult + 1) % 5 idx = n end
  if mult > 0 then return btnp("b") end
  if idx < n then idx = idx + SPEEDS[speed_i] else hold = hold + 1 if hold > 90 then idx, hold = 0, 0 end end
  return btnp("b")
end

local function at(i) return OX + list[i * 5 + 1] * K, OY + list[i * 5 + 2] * K, OX + list[i * 5 + 3] * K, OY + list[i * 5 + 4] * K end

local function live() -- the frame drawn again and again, k times over: past the budget the beam drops what it cannot reach
  local total = n * mult
  local drop = (V.flicker and total > V.budget) and (total - V.budget) / total or 0
  for r = 1, mult do
    for i = 0, n - 1 do
      if drop == 0 or math.random() >= drop then
        local x0, y0, x1, y1 = at(i)
        local jx = (r - 1) * 2
        line(x0 + jx, y0, x1 + jx, y1, list[i * 5 + 5])
      end
    end
  end
  return total
end

function E.draw()
  local head = math.min(n, math.floor(idx))
  box(OX - 3, OY - 3, 480 * K + 6, 320 * K + 6, 0x303050)
  local total = n
  if mult > 0 then total = live() end
  for i = 0, (mult > 0 and -1 or head - 1) do
    local age = head - i
    local k = math.max(0.1, 1 - age / 70)
    local x0, y0, x1, y1 = at(i)
    local c = list[i * 5 + 5]
    line(x0, y0, x1, y1, V.dim(c, k))
    if age < 3 then line(x0 + 1, y0, x1 + 1, y1, V.dim(c, 0.5)) end
  end
  if mult == 0 and head > 0 and head < n then -- the beam's way to the next line, dark, and where it is
    local _, _, px, py = at(head - 1)
    local nx, ny = at(head)
    line(px, py, nx, ny, 0x5060A0)
    circ(nx, ny, 3, 0xFFFFFF, true)
    circ(nx, ny, 5, 0x40608F, false)
  end
  local title, small = {font = "vector_arcade_title", align = "center", color = 0xFFE040}, {font = "hud_s", color = 0xE0E8FF, width = 222}
  text(lang.tr("ex_title"), 240, 14, title)
  local y = 58
  local keys = {"ex_1", "ex_2", "ex_3", "ex_4"}
  if mult > 0 then
    keys = {total > V.budget and "ex_live" or "ex_live_ok"}
    if total > V.budget and not V.flicker then keys[2] = "ex_calm" end
  end
  for _, key in ipairs(keys) do
    local _, h = text(lang.tr(key, {n = n, max = V.budget, k = mult, total = total}), 244, y, small)
    y = y + h + 11
  end
  small = {font = "hud_s", color = 0x8090C0, width = 216}
  if mult == 0 then text(lang.tr("ex_slow", {k = math.max(1, math.floor(n / SPEEDS[speed_i] + 0.5))}) .. " · " .. math.min(head, n) .. " / " .. n, OX, 210, small) end
  small.width = 450
  text(lang.tr("ex_keys"), OX, 298, small)
end

return E
