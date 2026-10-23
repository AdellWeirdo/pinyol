-- const: the sizes and the physics of Botín. Positions are world pixels, speeds pixels a tick (60 a second). A cell of a level is 16x16.
return {
  W = 240, H = 160, T = 16,
  -- the hero's body (the sprite is 32x32 and is drawn round it)
  HW = 12, HH = 22, CROUCH_H = 13,
  GRAVITY = 0.27, MAX_FALL = 5.6, JUMP = -5.1, JUMP_CUT = -1.8,
  WALK = 1.35, WALK_ACCEL = 0.16, FRICTION = 0.2, AIR_ACCEL = 0.12,
  RAM = 2.9, RAM_TICKS = 26, CRAWL = 0.8, CARRY = 1.05,
  SPRING = -8.1, SMASH = 6.2,
  COYOTE = 6, BUFFER = 6,
  SWIM_GRAV = 0.05, SWIM_MAX = 1.1, SWIM_KICK = -1.5, SWIM_SPEED = 1.0,
  HURT_TICKS = 90, STUN_TICKS = 300,
  HEARTS = 3,
}
