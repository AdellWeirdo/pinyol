-- box: a framed text that fits its frame the first time it is drawn. The frame is as tall as the title and the text need (measured with
-- textw before anything is drawn), or, with a `max_h`, the text is made to fit that height (a smaller scale, then the next of `fonts`),
-- and what still does not fit is cut with "..." and reported by the simulator's --check-text.
--
--   local box = require("box")
--   local h = box.draw{x = 20, y = 16, w = 440, title = lang.tr("ex_title"), body = lang.tr("ex_text"),
--                      font = "main", title_font = "bold", color = 0x402010, title_color = 0x8a3a08}
--   box.draw{..., frame = function(x, y, w, h) Hud.panel(x, y, w, h) end,   -- the game's own frame (default: the engine's panel)
--            pad = 16, gap = 6, align = "center", max_h = 120, fonts = {"small"}}
--   box.height{w = 440, body = "...", font = "main"}                          -- what draw would use, without drawing: to place the next thing
-- Returns the frame's height, then the scale and font name the body ended in.
local M = {}

local function measure(o)
  local pad, gap = o.pad or 14, o.gap or 6
  local inner = o.w - 2 * pad
  local th = 0
  if o.title and o.title ~= "" then local _, h = textw(o.title, {font = o.title_font or o.font or "bold"}) th = h + gap end
  local _, bh = textw(o.body or "", {font = o.font or "main", scale = o.scale or 1, width = inner})
  return pad, inner, th, bh
end

function M.height(o)
  local pad, _, th, bh = measure(o)
  local h = 2 * pad + th + bh
  return o.max_h and math.min(h, o.max_h) or h
end

function M.draw(o)
  local pad, inner, th = measure(o)
  local h = M.height(o)
  local frame = o.frame or panel
  frame(o.x, o.y, o.w, h)
  local align = o.align or "left"
  local ax = align == "center" and o.x + o.w // 2 or align == "right" and o.x + o.w - pad or o.x + pad
  if th > 0 then
    text(o.title, ax, o.y + pad, {font = o.title_font or o.font or "bold", align = align, color = o.title_color or o.color or 0xFFFFFF})
  end
  local _, _, scale = textbox(o.body or "", o.x + pad, o.y + pad + th, inner, h - 2 * pad - th, {
    font = o.font or "main", scale = o.scale or 1, align = align, color = o.color or 0xFFFFFF, fonts = o.fonts,
    outline = o.outline, shadow = o.shadow, valign = "top"})
  return h, scale
end

return M
