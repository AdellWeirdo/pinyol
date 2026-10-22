-- tests/picmem.script: a packed picture, drawn once the script asks for it (so the script can make its first load find no memory)
function _init() show(0) end
function _update() end
function _draw()
  cls(0x102030)
  if SHOW then img("SPR_BOOM", 100, 60) end
  if SHOW2 then img("SPR_SHIP", 10, 10) end
end
