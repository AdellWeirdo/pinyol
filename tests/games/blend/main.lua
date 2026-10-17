-- img's four blends on a canvas (tests/blend.script): each is a 16x16 picture drawn over a 16x16 base. The channel
-- values are the ones a 5-6-5 colour keeps exactly (0 and full), so what comes out can be written down.
local cases = {
  -- name, base, picture, options
  {"sub_red", 0xFFFFFF, 0xFF0000, {sub = true}},                -- white take red = cyan
  {"sub_half", 0xFFFFFF, 0xFF0000, {sub = true, alpha = 0.5}},  -- half of the red taken
  {"sub_floor", 0x000000, 0xFFFFFF, {sub = true}},              -- nothing under black: stays black
  {"add_over", 0x808080, 0xFFFFFF, {add = true}},               -- held at white
  {"quarter", 0x000000, 0xFFFFFF, {quarter = true}},            -- black plus a quarter of white
  {"quarter_over", 0xFFFFFF, 0xFFFFFF, {quarter = true}},       -- held at white
  {"alpha", 0x000000, 0xFFFFFF, {alpha = 0.5}},                 -- plain half mix, as before
}
function _init()
  show(0)
  for i, c in ipairs(cases) do
    canvas("BASE" .. i, 16, 16); target("BASE" .. i); cls(c[2]); target()
    canvas("TOP" .. i, 16, 16); target("TOP" .. i); cls(c[3]); target()
  end
end
function _draw()
  for i, c in ipairs(cases) do
    canvas("OUT" .. i, 16, 16)
    target("OUT" .. i)
    img("BASE" .. i, 0, 0)
    img("TOP" .. i, 0, 0, c[4])
    target()
    img("OUT" .. i, 20 * (i - 1), 0)
  end
end
function px(i) return pget(8, 8, "OUT" .. i) end
function ch(c) return c >> 16 & 255, c >> 8 & 255, c & 255 end
