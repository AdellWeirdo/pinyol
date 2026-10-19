-- kit.lua's named animations (tests/kitanims.script): the frame each object shows, tick after tick.
kit = require("kit")
kit.setup(require("data"))
seen = {rapido = {}, lento = {}, una_vez = {}, viejo = {}}

function _init()
  for name in pairs(seen) do -- the editor writes these as files; here, drawn: three frames of 8 x 8
    canvas("SPR_" .. name, 24, 8)
    target("SPR_" .. name)
    for f = 0, 2 do rect(f * 8 + 1, 1, 6, 6, 0x808080 + f * 0x202020) end
    target()
  end
  kit.init()
end

function _update()
  kit.update()
  for name, list in pairs(seen) do
    local o = kit.first(name)
    if o then list[#list + 1] = o.frame end
  end
end

function _draw() kit.draw() end

-- what the script asks: how many ticks each frame stayed (the first and the last stay are cut short), and the frames in order
function stays(name)
  local l, out, n = seen[name], {}, 1
  for i = 2, #l do
    if l[i] == l[i - 1] then n = n + 1 else out[#out + 1] = n n = 1 end
  end
  table.remove(out, 1)
  return out, n
end
function all_stay(name, ticks)
  local s = stays(name)
  if #s < 3 then return false end
  for _, n in ipairs(s) do if n ~= ticks then return false end end
  return true
end
function order(name)
  local l, s = seen[name], ""
  for i, f in ipairs(l) do if i == 1 or f ~= l[i - 1] then s = s .. f end end
  return s
end
