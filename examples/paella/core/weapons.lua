-- weapons: what each chef shoots. A weapon says how often, how fast, what it does and what it looks like; a pickup crate changes it for a while (a: a three-way spread,
-- b: twice the rate, c: bigger and piercing). Damage is in hits of an enemy's life.
local W = {}

-- name: {sheet prefix, frames, rate (ticks between shots), speed, dmg, life (ticks), gravity, pierce, spread (pellets), sfx, size (hitbox), recoil}
W.DEFS = {
  estrella = {name = "knife", frames = 4, every = 5, speed = 15, dmg = 1, life = 40, gravity = 0, pierce = 0, pellets = 1, sfx = "knife", r = 9},
  espuma = {name = "foam", frames = 4, every = 8, speed = 8, dmg = 1, life = 20, gravity = 0, pierce = 1, pellets = 3, spread = 0.18, sfx = "foam", r = 12},
  pinche = {name = "croqueta", frames = 4, every = 16, speed = 9, dmg = 3, life = 60, gravity = 0.14, pierce = 0, pellets = 1, sfx = "croqueta", r = 13, splash = 36},
  arrocero = {name = "rice", frames = 4, every = 10, speed = 10, dmg = 1, life = 26, gravity = 0.04, pierce = 0, pellets = 3, spread = 0.22, sfx = "rice", r = 10},
  brioche = {name = "cream", frames = 4, every = 3, speed = 10, dmg = 0.5, life = 24, gravity = 0, pierce = 0, pellets = 1, sfx = "cream", r = 9, jitter = 0.08},
  crianza = {name = "cork", frames = 4, every = 22, speed = 17, dmg = 4, life = 50, gravity = 0, pierce = 2, pellets = 1, sfx = "cork", r = 10},
}

W.NAMES = {
  estrella = {es = "Cuchillos", ca = "Ganivets", en = "Knives"}, espuma = {es = "Sifón de espuma", ca = "Sifó d'escuma", en = "Foam siphon"},
  pinche = {es = "Sartén de croquetas", ca = "Paella de croquetes", en = "Croquette pan"}, arrocero = {es = "Cucharón de arroz", ca = "Cullerot d'arròs", en = "Rice ladle"},
  brioche = {es = "Pistola de nata", ca = "Pistola de nata", en = "Cream gun"}, crianza = {es = "Corchos de cava", ca = "Taps de cava", en = "Cava corks"},
}

-- a pickup's effect: the modified weapon (a copy), for `shots` shots
function W.upgrade(base, kind)
  local w = {}
  for k, v in pairs(base) do w[k] = v end
  if kind == "a" then
    w.pellets, w.spread = math.max(3, base.pellets + 2), (base.spread or 0.16) + 0.06
  elseif kind == "b" then
    w.every = math.max(2, base.every // 2)
  elseif kind == "c" then
    w.dmg, w.pierce, w.r = base.dmg * 2, base.pierce + 2, base.r + 4
  end
  return w
end

return W
