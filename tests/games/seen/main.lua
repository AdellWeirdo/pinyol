-- img's alpha and add (tests/seen.script): a red picture drawn half seen through over blue, and added to it, on
-- canvases whose pixels the test reads back; and the same turned, which goes through the kept turned pictures.
function _init()
  show(0)
  canvas("RED", 8, 8) target("RED") cls(0xF80000) target()
  for _, id in ipairs({"MIX", "ADD", "TURN", "NONE"}) do canvas(id, 16, 16) target(id) cls(0x0000F8) target() end
  target("MIX") img("RED", 4, 4, {alpha = 0.5}) target()
  target("ADD") img("RED", 4, 4, {add = true}) target()
  target("TURN") img("RED", 4, 4, {alpha = 0.5, angle = 90}) target()
  target("NONE") img("RED", 4, 4, {alpha = 0}) target()
end
function _draw() img("RED", 100, 100, {alpha = 0.5, angle = 45}) img("RED", 140, 100, {add = true, scale = 3}) end
