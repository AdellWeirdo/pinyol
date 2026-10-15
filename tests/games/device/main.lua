-- The console itself: its LED, its battery and its MENU button (tests/device.script). CONTROL's tally light:
-- red while on air.
on_air, menus, starts = false, 0, 0
function _init() show(0) end
function _update()
  if btnp("a") then
    on_air = not on_air
    if on_air then led(0xFF0000) else led() end
  end
  level, charging = battery()
  if btnp("menu") then menus = menus + 1 end
  if btnp("start") then starts = starts + 1 end
end
function _draw()
  cls(0x101418)
  text(on_air and "EN EL AIRE" or "ENSAYO", 240, 120, {font = "large", align = "center", color = on_air and 0xFF4040 or 0x808890})
  if level then text(string.format("batería %d%%%s", math.floor(level * 100 + 0.5), charging and " (cargando)" or ""), 240, 170, {align = "center"}) end
end
