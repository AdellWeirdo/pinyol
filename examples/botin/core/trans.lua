-- trans: the way out of a scene and into the next, as the GBA did it: the picture goes blocky (mosaic) while it fades to black, and comes back the same way.
local Trans = {}

Trans.mode = nil -- "out" or "in"
Trans.t, Trans.dur = 0, 24
Trans.cb = nil
Trans.after = nil -- called when an "in" finishes (re-arms the scene's own effects)

local function apply(k)
  local m = 1 + math.floor(k * 12)
  mosaic(m, m, m, m)
  fade("dark", ALL, math.floor(k * 16))
end

-- the scene goes away; `cb` runs when the screen is black and the next scene can be set up (then call Trans.into())
function Trans.out(cb, dur)
  Trans.mode, Trans.t, Trans.dur, Trans.cb = "out", 0, dur or 24, cb
end

function Trans.into(dur)
  Trans.mode, Trans.t, Trans.dur = "in", 0, dur or 24
  apply(1)
end

function Trans.active() return Trans.mode ~= nil end

function Trans.update()
  if not Trans.mode then return end
  Trans.t = Trans.t + 1
  local k = math.min(1, Trans.t / Trans.dur)
  if Trans.mode == "out" then
    apply(k)
    if k >= 1 then
      local cb = Trans.cb
      Trans.mode, Trans.cb = nil, nil
      if cb then cb() end
    end
  else
    apply(1 - k)
    if k >= 1 then
      Trans.mode = nil
      mosaic(1, 1, 1, 1)
      fx_off()
      if Trans.after then Trans.after() end
    end
  end
end

return Trans
