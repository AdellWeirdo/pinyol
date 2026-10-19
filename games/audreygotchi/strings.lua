-- strings: the board's on-screen copy (platforms/esp32s3/strings.py), Spanish. The core's own copy (overlays,
-- foods, games, events) comes in the snapshot already in Spanish.
local M = {}

M.MENU = {Feed = "Comer", Play = "Jugar", Cuddle = "Mimos", Bath = "Baño", Sleep = "Dormir", Heal = "Curar",
          Status = "Estado", Album = "Álbum", Friends = "Amigos", Settings = "Ajustes", Sitter = "Sancho",
          Fiesta = "Fiesta", ["Simón"] = "%s dice"}

function M.label(item, name) -- an option's name as shown: Simón is hers, "Audrey dice"
  local l = M.MENU[item] or item
  if l:find("%s", 1, true) then l = l:format(name or "Audrey") end
  return l
end

M.T = {
  day = "Día %d",
  said = {
    juego = {{"¡Otra partida!", "¡Qué divertido!", "¡Soy la campeona!"}, {"Hoy no estoy para juegos", "Otro día jugamos"}},
    alimentar = {{"¡Qué rico!", "Barriguita llena", "¡Mmm, ñam!"}, {"Ahora no quiero comer", "Luego como, gracias"}},
    mimos = {{"Prrrr... más mimos", "Te quiero, humana"}, {"Ahora no, porfi", "Necesito mi espacio"}},
    ["baño"] = {{"Limpita y suave", "Huelo a rosas"}, {"¡Agua no, por favor!", "Baño no, gracias"}},
    luz = {{"Así está mejor", "Gracias, humana"}, {"Así está mejor"}},
    sleep = {{"Buenas noches"}, {"¿Dormir? ¡Ni hablar!", "Aún no tengo sueño"}},
    otro = {{"¡Bien!"}, {"Mejor luego"}},
  },
  said_as = {play = "juego", cuddle = "mimos", feed = "alimentar", bath = "baño", dormir = "sleep"},
  unlock = {Juvenil = "de juvenil", Adulto = "de adulta"},
  unlock_days = "en %d días", unlock_tomorrow = "mañana",
  hunger = "Hambre", affection = "Afecto", energy = "Energía", health = "Salud", dirt = "Suciedad",
  weight_height = "Peso %s kg  Altura %s cm",
  overweight = "Está algo rellenita.",
  no_events = "Sin eventos todavía",
  phase = "Fase: %s",
  day_age = "Día %d   Edad %d d",
  wait = "Espera %ds",
  confirm_hold = "Borrar: mantén A 2 s",
  sitter_ask = "¿Dejar a %s", sitter_ask2 = "con Sancho?", sitter_note = "Se la lleva 8 horas",
  bed_ask = "¿Me apagas", bed_ask2 = "la luz?", bed_note = "Es hora de dormir",
  whim_ask = "Te pide mimos.", whim_ask2 = "¿Le haces caso?", whim_note = "No le falta de nada",
  diva_ask = "Se hace la diva.", diva_ask2 = "¿Qué haces?", diva_note = "Mimarla la malcría",
  diva_yes = "Mimar", diva_no = "Regañar",
  yes = "Sí", no = "No",
  sitter_no = {sleeping = "duerme", hidden = "escondida", critical = "te necesita", today = "ya vino hoy"},
  intro_explica = {"Este es Sancho,", "su compañero de piso.", "Puede cuidarla 8 horas,", "una vez al día."},
  intro_menu = {"Cuando no puedas estar,", "llámalo desde aquí."},
  grow_title = "¡%s ha crecido!",
  grow_call = "¡Va a crecer! Pulsa A",
  gift_names = {zanahoria = "Zanahoria", pluma = "Pluma", pipa = "Pipa", uvas = "Uvas", bambu = "Bambú",
                hibisco = "Hibisco", tapon = "Tapón"},
  grow_stage = {Juvenil = "Ya es juvenil", Adulto = "Ya es adulta", Senior = "Ya es senior",
                Extra = "¡Qué gata tan especial!"},
  away_title = "%s está con Sancho",
  away_left = "Vuelve en %d h %d min",
  away_pick = "A: recoger",
  goodbye = "Adiós,",
  new_life_button = "Nueva vida", memories_button = "Recuerdos",
  memories_days = "Vivió %d días contigo.", memories_left = "Dejó %s.",
  legacy_items = {foto = "una foto", juguete = "su juguete", piedra = "una piedra", cojin = "su cojín",
                  cuenco = "su cuenco", estrella = "una estrella"},
  farewell_credits = {"%s ahora brilla", "en el cielo.", "", "Siempre podrás", "volver a encontrarla.", "",
                      "Audreygotchi"},
  farewell_thanks = {"Gracias por", "cuidar de", "%s."},
  farewell_authors = {{"Idea y diseño", "Pau Avila"}, {"Personajes y arte", "iPaud"},
                      {"Programación", "Pablo Palote"}, {"Música", "Paco Paquito"},
                      {"Con la inestimable\nayuda de", "Javi Adell"}, {"Inspirado en", "Audrey"},
                      {"Un regalo para", "Núria Blush"}},
  loves = "Le encanta: %s.", toy_line = "Su juguete: %s.", friends_line = "Amigos: %s.",
  friend_visit = "¡%s de visita!",
  animals = {conejita = "Conejita", patito = "Patito", hamster = "Hámster", zorrito = "Zorrito", panda = "Panda",
             iguana = "Iguana", mapache = "Mapache"},
  toys = {pelota = "la pelota", raton = "el ratón", pluma = "la pluma", tapon = "el tapón", cinta = "la cinta"},
  loves_game = "Le encanta jugar a %s.",
  fav_room = "Su sitio favorito: %s.",
  fav_times = {morning = "Le gustan las mañanas.", afternoon = "Le gustan las tardes.",
               evening = "Le gustan las noches."},
  moods = {happy = "Está contenta.", calm = "Está tranquila.", curious = "Está curiosa.",
           playful = "Tiene ganas de jugar.", affectionate = "Está mimosa.", bored = "Se aburre un poco.",
           sleepy = "Tiene sueño.", grumpy = "Está gruñona.", nervous = "Está nerviosa.", sad = "Está tristona.",
           sick = "No se encuentra bien.", proud = "Está orgullosa.", excited = "Está emocionada.",
           lonely = "Te echa de menos.", critical = "Necesita ayuda.", off = "Apagada.",
           deep_sleep = "Duerme profundamente."},
  about = {sociability_hi = "Le encanta estar contigo.", sociability_lo = "Va mucho a su aire.",
           activity_hi = "Últimamente está muy juguetona.", activity_lo = "Es tranquila por naturaleza.",
           curiosity_hi = "Parece especialmente curiosa.", curiosity_lo = "Es prudente con lo nuevo.",
           affection_hi = "Es muy cariñosa.", affection_lo = "Es reservada con sus mimos.",
           food_hi = "Es una glotona.", food_lo = "Es delicada con la comida.",
           rhythm_hi = "Es noctámbula.", rhythm_lo = "Es madrugadora.",
           pampered_hi = "Está muy mimada.", pampered_lo = "Es muy independiente."},
  called = "Todos la llaman %s %s.",
  nicknames = {sociability_hi = "la inseparable", sociability_lo = "la independiente",
               activity_hi = "la juguetona", activity_lo = "la dormilona", curiosity_hi = "la curiosa",
               curiosity_lo = "la prudente", affection_hi = "la cariñosa", affection_lo = "la discreta",
               food_hi = "la glotona", food_lo = "la delicada", rhythm_hi = "la noctámbula",
               rhythm_lo = "la madrugadora", pampered_hi = "la mimada", pampered_lo = "la valiente",
               neutral = "la dulce"},
  off = "Apagada", wake = "Pulsa A para despertar",
  sound = {"on", "off", "noche"}, volumes = {"bajo", "medio", "alto"}, onoff = {"sí", "no"},
  status = "Estado", system = "Sistema",
  guide_title = "Así se juega",
  guide = {{"Cruceta", "moverte"}, {"A", "elegir"}, {"B", "volver"}, {"START", "buscarla"}},
  guide_go = "Pulsa A para empezar",
  seek_title = "¿Dónde está?",
  -- the games (screens of game_screens.py)
  knots_title = "Quita nudos", knots_moves = {"Hilo", "Tirar", "Hilo"}, knots_score = "Nudo %d/%d",
  feather_title = "Palito con plumas", feather_moves = {"Paso", "Quieta", "Paso"}, feather_score = "Plumas %d/%d",
  levels = {"Fácil", "Medio", "Difícil"},
  game_boxes = "Trile de cajas", game_simon = "%s dice", game_laser = "Puntero láser", game_brush = "Cepillarla",
  btn_boxes = {"Caja", "Esta", "Caja"}, btn_simon = {"Rojo", "Verde", "Azul"},
  btn_laser = {"Punto", "¡Salta!", "Punto"}, btn_brush = {"", "Cepillar", ""},
  boxes_show = "Mira bien...", boxes_shuffle = "¡Se mezclan!", boxes_pick = "¿Dónde está?",
  boxes_found = "¡Aquí está!", boxes_empty = "Aquí no...",
  simon_show = "Escucha...", simon_turn = "Tu turno", simon_miss = "¡Uy!", simon_good = "¡Bien!",
  laser_aim = "Que salte encima", laser_catch = "¡Cazado!", laser_miss = "¡Se escapó!", laser_bored = "Se aburre...",
  brush_zones = {"Cabeza", "Lomo", "Cola", "Patas", "Barriga"},
  brush_swat = "¡La barriga no!", brush_smooth = "Ya está suave", brush_won = "¡Qué brillo!", brush_lost = "Se va...",
}

function M.said(ui) -- her last interaction in her words, one of a few by the day; asleep, a snore
  if ui.sleeping or ui.deep_sleep then return "Zzz..." end
  local action, ok = ui.last_interaction_action, ui.last_interaction_ok
  if not action or action == "init" or ok == nil then return nil end
  local key = tostring(action):match("^([^:]*)"):lower()
  local ways = M.T.said[M.T.said_as[key] or key] or M.T.said.otro
  ways = ways[ok and 1 or 2]
  return ways[(ui.day or 1) % #ways + 1]
end

function M.opens(at, age_days) -- when a locked option opens: its stage ("de adulta"), or the days left
  if not tostring(at):match("^%d+$") then return M.T.unlock[at] or at end
  local left = math.max(1, tonumber(at) - (age_days or 0))
  return left == 1 and M.T.unlock_tomorrow or M.T.unlock_days:format(left)
end

return M
