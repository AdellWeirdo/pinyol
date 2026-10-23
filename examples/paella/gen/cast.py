"""Registry of the six cooks, in line-up order."""
from chefcast import Estrella
from chefcast2 import Espuma, Pinche
from chefcast3 import Arrocero, Brioche, Crianza

CAST = {c.id: c for c in (Estrella, Espuma, Pinche, Arrocero, Brioche, Crianza)}
