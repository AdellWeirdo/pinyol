-- textfit: what textbox, textw with a width and --check-text promise. G.mode picks a screen: "ok" draws texts that fit; "cut" one the edge cuts;
-- "box" one that cannot fit its box; "slide" one that enters from the left on purpose.
G = {mode = "ok"}
local LONG = "A long sentence that wants several lines of this box, and then some more words to push it past what a small box can hold."

function _draw()
  cls(0x102030)
  if G.mode == "ok" then
    G.r = {textbox(LONG, 20, 20, 300, 120, {font = "main", scale = 2, align = "left"})}
    G.tw = {textw(LONG, {font = "main", width = 200})}
    G.one = {textw("one line", "main")}
  elseif G.mode == "cut" then
    text("this line is much too long for the screen's edge to leave it whole", 440, 100, {font = "main"})
  elseif G.mode == "box" then
    G.r = {textbox(LONG, 20, 20, 100, 24, {font = "main"})}
  elseif G.mode == "slide" then
    text("scrolling in", -30, 100, {font = "main", slide = true})
  elseif G.mode == "ui" then
    local box = require("box")
    local h = box.draw{x = 20, y = 16, w = 440, title = "Title", body = LONG, font = "main", title_font = "bold", color = 0x302010}
    G.h = h
    G.ht = box.height{x = 0, y = 0, w = 440, title = "Title", body = LONG, font = "main", title_font = "bold"}
  elseif G.mode == "capped" then
    G.capped = {require("box").draw{x = 20, y = 200, w = 300, body = LONG, font = "main", max_h = 40, color = 0x302010}}
  elseif G.mode == "fonts" then
    G.r = {textbox(LONG, 20, 20, 440, 100, {font = "large", fonts = {"main"}})}
  end
end
