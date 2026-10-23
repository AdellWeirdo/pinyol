-- poses: the pose a fighter is in, from its state and how far into it it is: the key poses of fighter.lua, blended.
local F = require("fighter")
local Moves = require("moves")
local M = {}
local P, mix = F.POSES, F.mix

local function ease(a, b, k) k = math.max(0, math.min(1, k)) return mix(P[a] or a, P[b] or b, k) end

function M.of(f, time)
  local st = f.state
  if st == "idle" then
    local br = math.sin((time or 0) / 14) * 1.2
    local p = mix(P.idle, P.idle, 0)
    p.lean = p.lean + br
    p.an, p.af = p.an + br * 2, p.af - br * 2
    return p
  elseif st == "walk" then return mix(P.walk_a, P.walk_b, (math.sin(f.phase) + 1) / 2)
  elseif st == "crouch" then return f.blocking and P.block_low or P.crouch
  elseif st == "block" then return P.block
  elseif st == "jump" then
    if f.move then return ease("jump", "jkick", f.t / 6) end
    return P.jump
  elseif st == "attack" then
    local m, t = f.move, f.t
    local a, b = m.windup, m.strike
    if t < m.startup * 0.55 then return ease("idle", a, t / (m.startup * 0.55))
    elseif t < m.startup then return ease(a, b, (t - m.startup * 0.55) / (m.startup * 0.45))
    elseif t < m.startup + m.active then return P[b]
    else return ease(b, "idle", (t - m.startup - m.active) / math.max(1, m.rec)) end
  elseif st == "hurt" then return f.low_hit and P.hit_low or P.hit
  elseif st == "blocked" then return f.crouch and P.block_low or P.block
  elseif st == "down" or st == "ko" then
    return ease(f.t < 8 and "hit" or "down", "down", f.t / 8)
  elseif st == "getup" then return ease("down", "idle", f.t / 14)
  elseif st == "win" then return P.win end
  return P.idle
end

return M
