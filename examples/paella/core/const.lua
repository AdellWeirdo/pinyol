-- const: the sizes and the physics of Paella de combate. Everything is at the screen's own 480x320; positions are pixels, speeds pixels a tick (60 a second).
return {
  W = 480, H = 320, FLOOR = 292,
  CHUNK = 960, ZONE_CHUNKS = 3, ZONE_W = 2880, ZONES = 3,
  LEVEL_W = 8640,          -- where the arena starts: the boss fight is one screen wide
  ARENA_W = 480,
  GRAVITY = 0.5, JUMP = -10.8, MAX_FALL = 11,
  WALK = 2.7, CRAWL = 1.3, AIR = 2.7,
  HERO_W = 30, HERO_H = 72, CROUCH_H = 44,
  LIVES = 3, GRENADES = 10,
  INVULN = 120, CONTINUE_SECS = 9,
}
