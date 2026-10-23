-- puppet: a paper doll. Its parts are pictures put on four corners with quad(), turned about where they hang and bent a little, so a limb swings, an ear
-- droops and the whole thing sways like cardboard on a stick. A part is {tex, w, h, hx, hy} with (hx, hy) the point of the picture it hangs by.
local M = {}
M.flex = true -- false: no bend (the switch of "Cómo funciona")

-- one part at (x, y) (where its hinge goes), turned `deg`, scaled, with the free end pushed sideways by `bend` pixels (a paper bend), and a shadow
function M.part(tex, w, h, hx, hy, x, y, deg, scale, bend, alpha)
  local r = math.rad(deg or 0)
  local c, s = math.cos(r), math.sin(r)
  scale, bend = scale or 1, M.flex and (bend or 0) or 0
  local function pt(px, py, push) -- a corner of the picture, relative to the hinge, turned, scaled
    local dx, dy = (px - hx) * scale + push, (py - hy) * scale
    return x + dx * c - dy * s, y + dx * s + dy * c
  end
  local x1, y1 = pt(0, 0, 0)
  local x2, y2 = pt(w, 0, 0)
  local x3, y3 = pt(w, h, bend)
  local x4, y4 = pt(0, h, bend)
  if alpha then quad(tex, x1, y1, x2, y2, x3, y3, x4, y4, {alpha = alpha})
  else quad(tex, x1, y1, x2, y2, x3, y3, x4, y4) end
end

return M
