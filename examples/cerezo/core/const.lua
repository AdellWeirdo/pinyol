-- const: the sizes of the game's screen. A Game Boy shows 160x144; the world here is 240x160, so the playfield is
-- 240x144 (15 x 9 metatiles of 16 pixels, the way a Game Boy Color's wide mode would) under a 16-pixel status bar.
return {
  W = 240, H = 160,
  HUD = 16,        -- the status bar's height; the playfield starts under it
  T = 16,          -- a metatile
  SW = 15, SH = 9, -- metatiles a screen shows
  PW = 240, PH = 144,
}
