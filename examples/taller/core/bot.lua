-- bot: a very small player for the title's attract mode and for tests: walks to the nearest automaton or prop, strikes it, jumps now and then, grabs, and lets the special go when the gauge is full.
local Foes = require("core.foes")
local Props = require("core.props")
local Items = require("core.items")
local Boss = require("core.boss")
local In = require("core.input")
local B = {}
local t = 0

function B.start() t = 0 In.state = {} end

local function nearest(h, list)
  local best, bd
  for _, f in ipairs(list) do
    if f.alive ~= false then
      local d = math.abs(f.x - h.x) + math.abs(f.y - h.y) * 1.5
      if not bd or d < bd then best, bd = f, d end
    end
  end
  return best
end

function B.step(h)
  t = t + 1
  local s = {}
  local tgt = Boss.ent and Boss.ent.alive and Boss.ent or nearest(h, Foes.list) or nearest(h, Items.list) or nearest(h, Props.list)
  if tgt then
    local dx, dy = tgt.x - h.x, tgt.y - h.y
    local reach = h.d.reach - 8 + (tgt.hw or 20) * 0.5
    if math.abs(dx) > reach then s[dx > 0 and "right" or "left"] = true elseif math.abs(dx) < reach - 24 then s[dx > 0 and "left" or "right"] = true end
    if dy > 7 then s.down = true elseif dy < -7 then s.up = true end
    if math.abs(dx) < reach + 16 and math.abs(dy) < 14 then
      if t % 12 < 2 then s.a = true end
      if h.st == "idle" or h.st == "walk" then s[dx > 0 and "right" or "left"] = true end
    end
    if t % 140 == 70 and math.abs(dx) < 120 then s.b = true end
  else
    s.right = true
  end
  if h.meter >= 100 and tgt and math.abs(tgt.x - h.x) < 90 then s.c = true end
  In.state = s
end

return B
