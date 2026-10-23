-- things: what a level has besides its ground and its enemies: coins, gems, hearts, the four pieces of the jewel (some hidden in boxes), the keyzer with the key, the
-- chest, the frog switch that starts the escape, and the vortex the hero comes out of and must come back to.
local C = require("core.const")
local U = require("core.util")
local W = require("core.world")
local P = require("core.phys")
local S = require("core.spr")
local Fx = require("core.fx")
local Sound = require("core.sound")
local Run = require("core.run")
local Hero = require("core.hero")
local Music = require("core.music")
local T = {}

T.list = {}
T.vortex = nil
T.frog = nil
T.on_escape = nil -- set by the scene

local COIN = {[1] = {"coin_s", 1}, [2] = {"coin_m", 5}, [3] = {"coin_l", 10}}
local GEM = {a = {"gem_a", 20}, b = {"gem_b", 50}}

function T.clear() for i = #T.list, 1, -1 do T.list[i] = nil end T.vortex, T.frog = nil, nil end

local function add(e) T.list[#T.list + 1] = e return e end

function T.load(lv)
  T.clear()
  for _, t in ipairs(lv.things) do
    local k = t.kind
    local x, y = t.x * 16, t.y * 16
    if k == "coin" then add({kind = "coin", x = x + 2, y = y + 2, w = 12, h = 12, size = t.s or 1, t = (t.x * 3) % 6, fixed = true})
    elseif k == "gem" then add({kind = "gem", x = x + 2, y = y + 2, w = 12, h = 12, gem = t.k or "a", t = (t.x * 5) % 6})
    elseif k == "diamond" then add({kind = "diamond", x = x + 2, y = y + 2, w = 12, h = 12, t = 0})
    elseif k == "heart" then add({kind = "heart", x = x + 2, y = y + 2, w = 12, h = 12, t = 0})
    elseif k == "jewel" then
      add({kind = "jewel", n = t.n, x = x + 2, y = y + 2, w = 12, h = 12, t = 0, hidden = t.box, cx = t.x, cy = t.y})
    elseif k == "keyzer" then
      add({kind = "keyzer", x = x, y = y - 32, w = 24, h = 24, home_x = x + 8, home_y = y - 24, t = 0, state = "float"})
    elseif k == "chest" then
      add({kind = "chest", x = x, y = (t.y + 1) * 16 - 32, w = 32, h = 32, t = 0, state = "closed"})
    elseif k == "frog" then
      T.frog = add({kind = "frog", x = x, y = (t.y + 1) * 16 - 32, w = 32, h = 32, t = 0, state = "off"})
    elseif k == "start" then
      T.vortex = add({kind = "vortex", x = x - 8, y = (t.y + 1) * 16 - 32, w = 32, h = 32, t = 0, state = "opening", cx = x + 8, cy = (t.y + 1) * 16})
    end
  end
end

-- a coin that jumps out of something and falls (from a box, an enemy, the chest)
function T.pop_coin(x, y, size, vx, vy)
  add({kind = "coin", x = x - 6, y = y - 6, w = 12, h = 12, size = size or 1, t = 0, vx = vx or (math.random() - 0.5) * 2, vy = vy or -3 - math.random() * 1.5, wait = 14})
end

function T.coin_drop(x, y, n)
  for i = 1, n do T.pop_coin(x, y, 1, (i - (n + 1) / 2) * 0.9, -3.2) end
end

-- called when a block breaks: boxes give what they hide
function T.on_break(cx, cy, c, how)
  Run.broken = Run.broken + 1
  local px, py = cx * 16 + 8, cy * 16 + 8
  if c == "K" then
    for i = -1, 1 do T.pop_coin(px, py, 1, i * 0.9, -3.4) end
    Sound.play("coin")
  elseif c == "J" then
    for _, e in ipairs(T.list) do
      if e.kind == "jewel" and e.hidden and e.cx == cx and e.cy == cy then
        e.hidden, e.vy, e.vx, e.pop = false, -3.6, 0, true
        e.x, e.y = cx * 16 + 2, cy * 16 - 2
        Fx.add("sparkle", px, py)
        Sound.play("chest")
      end
    end
  elseif c == "b" and (cx * 7 + cy * 3) % 5 == 0 then
    T.pop_coin(px, py, 1)
  end
end

local function collect_coin(e, play)
  local def = COIN[e.size] or COIN[1]
  Run.coins = Run.coins + def[2]
  Sound.play(e.size == 1 and "coin" or "coin_big")
  Fx.add("coin_spark", e.x + 6, e.y + 6)
  if play and play.coin_gain then play.coin_gain(def[2]) end
end

local function overlaps(h, e) return P.overlap(h.x, h.y + 1, h.w, h.h - 1, e.x, e.y, e.w, e.h) end

function T.update(h, play)
  local kill = {}
  for i = #T.list, 1, -1 do
    local e = T.list[i]
    e.t = e.t + 1
    local k = e.kind
    if k == "coin" or k == "gem" or k == "diamond" or k == "heart" or k == "jewel" then
      if e.vy then
        e.vy = e.vy + 0.18
        P.move_x(e, e.vx or 0)
        local hit = P.move_y(e, e.vy)
        if hit then
          if e.vy > 1.5 then e.vy = -e.vy * 0.45 else e.vy, e.vx = nil, nil end
        end
        if e.y > W.px_h + 40 then table.remove(T.list, i) goto continue end
      end
      if not e.hidden and (e.wait or 0) <= 0 and overlaps(h, e) and h.state ~= "dead" then
        if k == "coin" then collect_coin(e, play)
        elseif k == "gem" then
          Run.coins = Run.coins + GEM[e.gem][2]
          Sound.play("coin_big")
          Fx.add("sparkle", e.x + 6, e.y + 6)
        elseif k == "diamond" then
          Run.coins = Run.coins + 100
          Sound.play("jewel")
          Fx.add("sparkle", e.x + 6, e.y + 6)
        elseif k == "heart" then
          if h.hearts < C.HEARTS then h.hearts = h.hearts + 1 end
          Sound.play("heart")
          Fx.add("sparkle", e.x + 6, e.y + 6)
        elseif k == "jewel" then
          Run.jewels[e.n] = true
          Music.jingle("joya", 2)
          Sound.play("jewel")
          Fx.burst("sparkle", e.x + 6, e.y + 6, 6, 1.5)
          W.shake(1, 6)
          if play and play.jewel_got then play.jewel_got(e.n) end
        end
        table.remove(T.list, i)
      elseif e.wait then
        e.wait = e.wait - 1
      end
    elseif k == "keyzer" then
      if e.state == "float" then
        e.x = e.home_x + math.cos(e.t / 40) * 28 - 12
        e.y = e.home_y + math.sin(e.t / 25) * 12
        if overlaps(h, e) and (Hero.attacking(h) or h.vy > 0.5 or true) then
          e.state, e.st = "flee", 0
          Sound.play("key")
          Fx.add("impact", e.x + 12, e.y + 12)
          T.list[#T.list + 1] = {kind = "key", x = e.x + 4, y = e.y + 8, w = 12, h = 12, t = 0, vy = -2, vx = 0, wait = 30}
        end
      else
        e.st = e.st + 1
        e.x = e.x + 1.8
        e.y = e.y - 0.8
        if e.x > W.px_w + 40 or e.st > 240 then table.remove(T.list, i) end
      end
    elseif k == "key" then
      e.vy = e.vy + 0.15
      P.move_x(e, e.vx)
      if P.move_y(e, e.vy) then e.vy, e.vx = 0, 0 end
      if e.wait > 0 then e.wait = e.wait - 1 elseif overlaps(h, e) then
        Run.key = true
        Music.jingle("llave", 3)
        Fx.add("sparkle", e.x + 6, e.y + 6)
        table.remove(T.list, i)
      end
    elseif k == "chest" then
      if e.state == "closed" and Run.key and overlaps(h, e) then
        e.state, e.st = "opening", 0
        Run.key, Run.chest = false, true
        Music.jingle("tesoro", 2)
        Sound.play("chest")
      elseif e.state == "opening" then
        e.st = e.st + 1
        if e.st == 20 then
          for n = 1, 10 do T.pop_coin(e.x + 16, e.y + 8, n % 3 == 0 and 2 or 1, (n - 5.5) * 0.5, -3.5 - (n % 3)) end
          T.list[#T.list + 1] = {kind = "diamond", x = e.x + 10, y = e.y - 8, w = 12, h = 12, t = 0, vy = -3.5, vx = 0, wait = 20}
        end
        if e.st > 30 then e.state = "open" end
      end
    elseif k == "frog" then
      if e.state == "off" then
        local struck = (Hero.attacking(h) and P.overlap(h.x - 4, h.y, h.w + 8, h.h, e.x, e.y, e.w, e.h)) or
          (h.vy > 0.8 and P.overlap(h.x, h.y + h.h - 6, h.w, 8, e.x, e.y, e.w, 12))
        if struck then
          e.state, e.st = "hit", 0
          if h.vy > 0 and h.state ~= "ram" then h.vy = -3 end
          Sound.play("frog")
          W.shake(2, 20)
        end
      elseif e.state == "hit" then
        e.st = e.st + 1
        if e.st >= 24 then
          e.state = "on"
          if T.on_escape then T.on_escape() end
        end
      end
    elseif k == "vortex" then
      if e.state == "opening" then
        if e.t >= 48 then e.state, e.t = "closing", 0 end
      elseif e.state == "closing" then
        if e.t >= 36 then e.state, e.t = "closed", 0 end
      end
    end
    ::continue::
  end
end

function T.escape_started()
  if T.vortex then T.vortex.state, T.vortex.t = "live", 0 end
end

-- is the hero at the vortex while it is open?
function T.at_vortex(h)
  local v = T.vortex
  return v and v.state == "live" and P.overlap(h.x, h.y, h.w, h.h, v.x + 6, v.y + 4, 20, 28)
end

function T.draw(cx, cy)
  for _, e in ipairs(T.list) do
    local x, y = e.x - cx, e.y - cy
    if x > -40 and x < 270 and y > -40 and y < 200 and not e.hidden then
      local k = e.kind
      if k == "coin" then
        local p = COIN[e.size][1]
        S.draw("ITEMS16", p .. "_" .. ((e.t // 5) % 6), x - 2, y - 2, {})
      elseif k == "gem" then S.draw("ITEMS16", GEM[e.gem][1] .. "_" .. ((e.t // 6) % 6), x - 2, y - 2, {})
      elseif k == "diamond" then S.draw("ITEMS16", "diamond_" .. ((e.t // 5) % 6), x - 2, y - 2, {})
      elseif k == "heart" then S.draw("ITEMS16", "heart_item_" .. ((e.t // 8) % 4), x - 2, y - 2 + math.floor(math.sin(e.t / 12) * 2), {})
      elseif k == "jewel" then S.draw("ITEMS16", "jewel_" .. e.n .. "_" .. ((e.t // 7) % 4), x - 2, y - 2 + math.floor(math.sin(e.t / 14) * 2), {})
      elseif k == "key" then S.draw("ITEMS16", "key_" .. ((e.t // 6) % 4), x - 2, y - 2, {})
      elseif k == "keyzer" then
        if e.state == "float" then S.draw("ITEMS32", "keyzer_" .. ((e.t // 6) % 6), x - 4, y - 4, {flip = math.cos(e.t / 40) < 0})
        else S.draw("ITEMS32", "keyzer_flee_" .. ((e.t // 5) % 4), x - 4, y - 4, {}) end
      elseif k == "chest" then
        local f = e.state == "closed" and "chest_closed" or ("chest_open_" .. math.min(2, e.st // 8))
        if e.state == "open" then f = "chest_open_2" end
        S.draw("ITEMS16", f, x + 8, y + 16, {})
      elseif k == "frog" then
        local f
        if e.state == "off" then f = "frog_off_" .. ((e.t // 30) % 2)
        elseif e.state == "hit" then f = "frog_hit_" .. math.min(2, e.st // 8)
        else f = "frog_on_" .. ((e.t // 6) % 4) end
        S.draw("ITEMS32", f, x, y, {})
      elseif k == "vortex" then
        local f
        if e.state == "opening" then f = "vortex_open_" .. math.min(7, e.t // 6)
        elseif e.state == "closing" then f = "vortex_close_" .. math.min(5, e.t // 6)
        elseif e.state == "live" then f = "vortex_open_" .. (4 + (e.t // 5) % 4)
        else f = "vortex_closed_" .. ((e.t // 20) % 2) end
        S.draw("ITEMS32", f, x, y, {prio = 2})
      end
    end
  end
end

return T
