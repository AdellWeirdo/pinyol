-- ¡CUENTA!: the coins show for a moment and are hidden; say how many (up and down, then A). (It leaves a mosaic.)
local pad = require("pad")
local G = {verb = "¡CUENTA!", time = 5, bg = "BG3", timeout = "lose"}
local n, guess, shown, t, coins, step
local sheet_

function G.enter(level, spd)
  sheet_ = sheet("THINGS")
  n, guess, t, step = math.random(2, math.min(9, 4 + level)), 0, 0, 0
  shown = math.floor(100 / spd)
  coins = {}
  for i = 1, n do coins[i] = {x = 24 + (i - 1) % 5 * 38 + math.random(-6, 6), y = 36 + (i - 1) // 5 * 40 + math.random(-6, 6)} end
end

function G.update()
  t = t + 1
  local m = 1 + math.min(6, t // 15) -- (the memory blurs as the time goes)
  mosaic(1, 1, m, m)
  if t < shown then return end
  if pad.btnp("up") then guess = math.min(9, guess + 1) elseif pad.btnp("down") then guess = math.max(0, guess - 1) end
  if pad.btnp("a") then return guess == n and "win" or "lose" end
end

function G.bot(lose)
  if t < shown + 4 then return {} end
  step = step + 1
  if step % 6 ~= 0 then return {} end
  if lose then return {down = true} end
  if guess < n then return {up = true} end
  return {a = true}
end

function G.draw()
  for i, c in ipairs(coins) do
    if t < shown then spr(i - 1, sheet_, 2, c.x, c.y, prio(1) | MOSAIC) else spr_off(i - 1) end
  end
  if t >= shown then
    text("¿CUÁNTAS?", 240, 90, {font = "large_bold", align = "center", color = 0xFFFFFF})
    text(tostring(guess), 240, 140, {font = "large_bold", scale = 2, align = "center", color = 0xFFE070})
  end
end

return G
