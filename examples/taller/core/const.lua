-- const: the sizes and the physics of Taller de los Autómatas. Everything is at the screen's own 480x320; positions are pixels, speeds pixels a tick (60 a second).
-- A character stands at (x, y) in the street: x along it, y how far down the street floor it is (its feet row), and z how high it is above the floor.
return {
  W = 480, H = 320,
  Y_MIN = 240, Y_MAX = 304,        -- the walkable band of the street floor (feet rows)
  CHUNK = 960, STAGE_W = 2880,
  GRAV = 0.55,
  LIVES = 3, CONTINUE_SECS = 9,
  INVULN = 90, PART_TICKS = 1500,
  METER = 100,
}
