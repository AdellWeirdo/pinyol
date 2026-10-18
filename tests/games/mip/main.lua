-- quad drawing a big picture small (src/gfx_quad.c, the mip copy): onto canvases and read back (tests/mip.script)
function _init()
  show(0)
  canvas("MIN", 64, 64) canvas("MINP", 64, 64) canvas("HALF16", 16, 16) canvas("BIGUP", 64, 64)
end
function _draw()
  target("MIN") cls(0x000000) quad("BIG", 0, 0, 64, 0, 64, 64, 0, 64) target()
  target("MINP") cls(0x000000) quad("BIG", 0, 0, 64, 0, 56, 64, 8, 64, {persp = true}) target()
  target("HALF16") cls(0x0000FF) quad("HALF", 0, 0, 16, 0, 16, 16, 0, 16) target()
  target("BIGUP") cls(0x000000) quad("BIG", 0, 0, 255, 0, 255, 255, 0, 255) target() -- not smaller: no mip, the checker as it is
  rect(0, 0, 480, 320, 0x202838)
  quad("BIG", 100, 40, 200, 40, 200, 140, 100, 140)
  quad("BIG", 240, 40, 340, 60, 330, 160, 250, 150, {light = 0xC0C0FF})
  quad("HALF", 100, 200, 140, 200, 140, 240, 100, 240)
  img("MIN", 360, 20) img("HALF16", 360, 100)
end
function px(c, x, y) return pget(x, y, c) or -1 end
function red(c, x, y) return (px(c, x, y) >> 16) & 255 end
function grn(c, x, y) return (px(c, x, y) >> 8) & 255 end
function blu(c, x, y) return px(c, x, y) & 255 end
-- how far the pixels of a canvas are from grey: the checker point-sampled is black or white, the mip is the grey between
function extremes(c, x0, y0, x1, y1)
  local n = 0
  for y = y0, y1 do for x = x0, x1 do local r = red(c, x, y) if r < 40 or r > 215 then n = n + 1 end end end
  return n
end
