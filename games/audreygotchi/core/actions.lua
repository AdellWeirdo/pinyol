-- actions: B on every screen, and Comer's, Jugar's and Curar's choices (a port of audreygotchi/core/actions.py).
local util = require("core.util")
local events = require("core.events")
local memory = require("core.memory")
local asks = require("core.asks")
local bird = require("core.bird")
local scene_grow = require("core.scene_grow")
local scene_sancho = require("core.scene_sancho")
local personality = require("core.personality")
local v2_gameplay = require("core.v2_gameplay")
local weather = require("core.weather")
local litter = require("core.litter")
local M = {}

M.REST_BLOCKED = {"Feed", "Play", "Cuddle", "Bath", "Sleep", "Heal", "Fiesta"}
M.PLAY_ACTIONS = {["Quita nudos"] = "Juego:QuitaNudos", ["Palito con plumas"] = "Juego:PalitoPlumas",
                  ["Trile de cajas"] = "Juego:Cajas", ["Simón"] = "Juego:Simon", ["Puntero láser"] = "Juego:Laser",
                  ["Cepillarla"] = "Juego:Cepillar"}
M.COMEBACK_MS = 30000      -- a refused cuddle: she comes back on her own (Bible §40)
M.DISLIKED_REFUSE_P = 0.30 -- the food she dislikes, refused this often when not hungry (owner's yes)
M.DISLIKED_ABOVE_H = 40.0

function M.heal_left(s)
  local n = #s.HEAL_OPTIONS
  s.heal_choice = (s.heal_choice - 1) % math.max(1, n)
  s:mark_dirty()
end

function M.heal_right(s)
  local n = #s.HEAL_OPTIONS
  s.heal_choice = (s.heal_choice + 1) % math.max(1, n)
  s:mark_dirty()
end

-- What the holiday's button gives her today (owner, 2026-10-07): the day's food (a Christmas day's own, else
-- Christmas's) or Sant Jordi's rose; nil outside a holiday, or while its food is not hers yet (a puppy).
function M.fiesta_item(s)
  local day = weather.holiday(s)
  if day == "sant_jordi" then
    return "Rosa"
  end
  local food = util.get(s.SEASON_FOODS, day)
  if food == nil then food = util.get(s.SEASON_FOODS, util.get(weather.PARENT, day)) end
  if food ~= nil and M.locked_until(s, food) == nil then return food end
  return nil
end

function M.feed_left(s)
  local n = #s.FOOD_OPTIONS
  s.feed_choice = (s.feed_choice - 1) % math.max(1, n)
  s:mark_dirty()
end

function M.feed_right(s)
  local n = #s.FOOD_OPTIONS
  s.feed_choice = (s.feed_choice + 1) % math.max(1, n)
  s:mark_dirty()
end

-- What an option waits for while she is younger than it: its stage ("Juvenil"), else its day lived ("6",
-- UNLOCK_DAY); nil once it is hers.
function M.locked_until(s, option)
  local at, order = util.get(s.UNLOCK_PHASE, option), s.PHASE_ORDER
  if at ~= nil and util.contains(order, s.phase) and util.index(order, s.phase) < util.index(order, at) then
    return at
  end
  local day = util.get(s.UNLOCK_DAY, option)
  if day ~= nil and day ~= 0 and util.int(s.age_days) < day then
    return tostring(day)
  end
  return nil
end

-- The games open to her and never played: the platform marks them new.
function M.new_games(s)
  local played = s.memory["games"]
  local out = {}
  for _, g in ipairs(s.PLAY_OPTIONS) do
    local n = played[g]
    if M.locked_until(s, g) == nil and (n == nil or n == 0) then out[#out + 1] = g end
  end
  return out
end

-- The locked options of Comer and Jugar, each with the stage it opens at.
function M.unlocks(s)
  local out = {}
  local options = {}
  for _, o in ipairs(s.FOOD_OPTIONS) do options[#options + 1] = o end
  for _, o in ipairs(s.PLAY_OPTIONS) do options[#options + 1] = o end
  for _, option in ipairs(options) do
    local at = M.locked_until(s, option)
    if at ~= nil then
      out[option] = at
    end
  end
  return out
end

-- The choice if she has it, else the first option she has (0-based, as the choice).
function M.first_open(s, options, choice)
  choice = util.int(choice) % math.max(1, #options)
  if #options > 0 and M.locked_until(s, options[choice + 1]) ~= nil then
    for i, o in ipairs(options) do
      if M.locked_until(s, o) == nil then return i - 1 end
    end
    return 0
  end
  return choice
end

function M.selected_food_name(s)
  local n = math.max(1, #s.FOOD_OPTIONS)
  return s.FOOD_OPTIONS[s.feed_choice % n + 1]
end

function M.food_kind(s, food)
  if util.contains(util.get(s.FEED_TYPE_FOODS, "Comida", {}), food) then return "Comida" end
  return "Snack"
end

function M.selected_feed_type(s)
  return M.food_kind(s, M.selected_food_name(s))
end

-- She eats `food` if she will: not while she is still eating the last (the press is dropped), never a meal when
-- full, and maybe not the food she dislikes. True if she ate it.
function M.feed(s, food, now_ms)
  if now_ms < s._feed_cd_until_ms then
    return false -- still eating: the press waits for nothing (2026-10-09)
  end
  local ftype = M.food_kind(s, food)
  local meal = ftype == "Comida"
  local candidates = {}
  if meal and s.hunger >= s.MEAL_FULL_AT then -- full: a no, every time (the Tamagotchi way);
    candidates[#candidates + 1] = {1.0, "Paso, estoy llenita"} -- a snack always goes down, and fattens
  end
  if food == s.disliked_food and s.hunger > M.DISLIKED_ABOVE_H then
    candidates[#candidates + 1] = {M.DISLIKED_REFUSE_P, "¡Puaj! Eso no"}
  end
  local refusal = personality.pick_rejection(candidates)
  if refusal ~= nil then
    s:_emit_sound("rechazo")
    s._reject_cd_until_ms = now_ms + 1200
    s.overlay_text = refusal
    s.overlay_until = now_ms + 900
    s:_log_event("Rechaza " .. food)
    s:_register_interaction("Alimentar:" .. food, false)
    s:mark_dirty()
    return false
  end

  local effect = s.FEED_EFFECTS[ftype]
  s.hunger = math.min(100.0, s.hunger + effect["H"])
  s.dirt = math.min(100.0, s.dirt + effect["D"])
  s.affection = math.min(100.0, s.affection + effect["F"])
  s.weight_kg = math.min(9.5, s.weight_kg + 0.0012 * effect["H"] + 0.0004 * effect["F"])
  v2_gameplay.register_feed_outcome(s, now_ms, food, ftype)
  s._feed_cd_until_ms = now_ms + util.int(s.FEED_COOLDOWN_SEC * 1000) -- transient (ms: reset on load)
  s:_register_interaction("Alimentar:" .. food, true)
  s:_log_event("Feed " .. food)
  if food == s.favorite_food then -- Bible §7: shown in how she eats it
    memory.first(s, "favorite")
    s:_emit_sound("favorita")
  else
    s:_emit_sound("come") -- she eats (a puppy drinks her bottle)
  end
  return true
end

-- The holiday's button: its food, eaten as Comer's are (cooldown, refusals), or the rose; the first time each
-- holiday it is her moment (events.celebrate).
function M.give_fiesta(s, now_ms)
  local item, day = M.fiesta_item(s), weather.holiday(s)
  if item == nil then
    return
  end
  if item == "Rosa" then
    if s.memory["first"][day] == nil then -- once in her events, not at every press
      s:_log_event("Le das una rosa")
    end
    s.overlay_text, s.overlay_until = "¿Una rosa? ¡Para mí!", now_ms + 900
  elseif M.feed(s, item, now_ms) then
    s.overlay_text, s.overlay_until = "¡Mmm, " .. item .. "!", now_ms + 900
  else
    return
  end
  events.celebrate(s, day, now_ms)
  s:compute_mood()
  s:mark_dirty()
end

local function shh(s, now_ms)
  s.overlay_text = "Shhh... ¡que duerme!"
  s.overlay_until = now_ms + 900
  s:mark_dirty()
end

-- The buttons' guide put away (the owner, 2026-10-09): seen, not shown again on its own.
function M.close_guide(s)
  s.guide_seen, s.mode = true, "main"
  s:mark_dirty()
end

local function wants_comeback(s) -- any(s == "se_acerca" for _t, s in state._later)
  for _, x in ipairs(s._later) do
    if x[2] == "se_acerca" then return true end
  end
  return false
end

local function refusal_want(s) -- sleep_refusal_want(state)[1]: the menu item that answers her want
  local words, item = personality.sleep_refusal_want(s)
  if type(words) == "table" then return words[2] end -- a tuple as an array
  return item
end

-- B on the main screen: the item under the cursor (the screens' own B is above, in press_ok).
local function press_menu(s, now_ms)
  local action = s:current_label()
  if action == "Sitter" then -- Sancho comes for her: no refusal roll, he is her friend
    s:_call_sancho(now_ms)
    return
  end

  -- v9 §7.6: resting after a visit from critical, nothing but looking at her
  if util.contains(M.REST_BLOCKED, action) and s:_vet_softlock_active() then
    s.overlay_text = string.format("Toca reposo (%dm)", math.max(1, (s:_vet_softlock_left_sec() + 59) // 60))
    s.overlay_until = now_ms + 900
    s:mark_dirty()
    return
  end

  -- cooldowns come before refusal rolls, so spam is charged the same every time
  if action == "Cuddle" and now_ms < s._hug_cd_until_ms then
    return -- her purr still playing: the press is dropped, quietly
  end
  -- a game's end still showing: the press is dropped, quietly (the owner, 2026-10-09)
  if action == "Play" and now_ms < s._play_cd_until_ms then
    return
  end

  local reject = s:should_reject(now_ms, action)
  if reject ~= nil then
    s:_emit_sound("rechazo")
    if action == "Sleep" then -- she wants something instead: the cursor goes there
      local items = s:active_menu_items()
      local want = refusal_want(s)
      if util.contains(items, want) then
        s.selected_index = util.index(items, want)
      end
    end
    if action == "Cuddle" and not wants_comeback(s) then
      events.later(s, now_ms + M.COMEBACK_MS, "se_acerca") -- Bible §40: not now; later she comes herself
    end
    s.overlay_text = reject
    s.overlay_until = now_ms + 900
    s:_log_event("Rechaza: " .. action)
    s:_register_interaction(action, false)
    if util.contains(personality.DIVA_LINES, reject) then -- no reason but her whim: spoil her or scold her
      asks.start(s, "diva", asks.DIVA_WAIT_SEC)
    end
    s:mark_dirty()
    return
  end

  if action == "Fiesta" then -- the holiday's button (owner, 2026-10-07)
    M.give_fiesta(s, now_ms)
    return
  end
  if action == "Feed" then
    s:enter_action_feed(now_ms)
    s:compute_mood()
    return
  elseif action == "Play" then
    s:enter_action_play(now_ms)
    s:compute_mood()
    return
  elseif action == "Cuddle" then
    -- she got her cuddle: nothing to come back for
    local keep = {}
    for _, x in ipairs(s._later) do
      if x[2] ~= "se_acerca" then keep[#keep + 1] = x end
    end
    s._later = keep
    s:_act_hug(now_ms)
    s:compute_mood()
    return
  elseif action == "Bath" then -- bathe her or clean her box: a choice (litter.py)
    litter.open_bath(s, now_ms)
    return
  elseif action == "Sleep" then
    s:enter_sleep(now_ms, "manual", true)
    return
  elseif action == "Heal" then
    s:enter_action_heal(now_ms)
    s:compute_mood()
    return
  elseif action == "Status" then
    s:enter_status(now_ms)
    s:compute_mood()
    return
  elseif action == "Album" or action == "Friends" then -- Estado, opened at her album or her animal friends
    s:enter_status(now_ms)
    s.status_page = util.index(s.STATUS_PAGES, action == "Album" and "Álbum" or "Amigos")
    s:mark_dirty()
    return
  elseif action == "Settings" then
    s:enter_settings(now_ms)
    s:compute_mood()
    return
  end

  s:compute_mood()
  s:maybe_purr(now_ms)
  s:mark_dirty()
end

local function press_play(s, now_ms)
  local opt = s.PLAY_OPTIONS[s.play_choice % math.max(1, #s.PLAY_OPTIONS) + 1]
  if M.locked_until(s, opt) ~= nil then
    return
  end
  if opt == "Siguela por la casa" then -- hide and seek: she hides, you find her
    s:_play_seek(now_ms)
    if s.hidden then
      memory.game_started(s, opt)
    end
    s:compute_mood()
    return
  end
  local action_key = util.get(M.PLAY_ACTIONS, opt, "Juego:PalitoPlumas")
  s:enter_action_minigame(now_ms, action_key)
  if s.mode == "action_minigame" then
    memory.game_started(s, opt)
    if memory.fav_game(s) == opt then
      s:_emit_sound("favorita") -- her favourite game: glad of it (Bible §7)
    end
  end
  s:compute_mood()
end

function M.press_ok(s, now_ms)
  if s.deep_sleep and not s.powered_off and s:is_night() then
    shh(s, now_ms) -- at night nothing wakes her (owner, 2026-10-05)
    return
  end
  if s.powered_off or s.deep_sleep then
    s:wake_by_button(now_ms, "B")
    return
  end

  -- "leave her with Sancho?": B answers
  if s.mode == "sitter_confirm" then
    scene_sancho.confirm(s, now_ms)
    return
  end
  if s.mode == "ask" then -- what she asks: B answers
    asks.confirm(s, now_ms)
    return
  end

  if s.mode == "birth" or s.mode == "grow" then -- a new life arriving, or her growing up: the buttons wait
    return
  end
  if s.mode == "guide" then -- the buttons' guide: B, and to play
    M.close_guide(s)
    return
  end
  if s.mode == "sancho_intro" then -- Sancho explaining himself: B moves him on
    scene_sancho.intro_next(s, now_ms)
    return
  end

  -- Farewell: once it is over, B starts a new life
  if s.mode == "farewell" then
    s:confirm_new_life_from_farewell(now_ms)
    return
  end

  -- Status: B goes back
  if s.mode == "status" then
    s:exit_status(now_ms)
    s:compute_mood()
    return
  end

  -- Tech: B goes back
  if s.mode == "tech" then
    s:exit_tech_mode(now_ms)
    s:compute_mood()
    return
  end

  -- Modo Sistema: a tap; destructive options wait for B held (cancel_action)
  if s.mode == "system" then
    s:system_choose(now_ms, false)
    return
  end

  -- Settings: B confirms the option
  if s.mode == "settings" then
    s:settings_confirm(now_ms)
    s:compute_mood()
    return
  end

  if s.mode == "action_feed" then
    local selected_food = s:_selected_food_name()
    if M.locked_until(s, selected_food) ~= nil then -- greyed: the strip says when it opens
      return
    end
    if M.feed(s, selected_food, now_ms) then
      s:exit_action_feed(now_ms, "¡Mmm, " .. selected_food .. "!")
      s:compute_mood()
    end
    return
  end

  if s.mode == "action_play" then
    press_play(s, now_ms)
    return
  end

  -- Action minigame: B confirms the timing
  if s.mode == "action_minigame" then
    s:minigame_confirm(now_ms)
    s:compute_mood()
    return
  end

  if s.mode == "action_bath" then -- Baño's choice: her bath, or her box
    litter.confirm(s, now_ms)
    return
  end

  -- Action heal: B confirms
  if s.mode == "action_heal" then
    s:heal_confirm(now_ms)
    s:compute_mood()
    return
  end

  -- with Sancho: B picks her up
  if s.sitter_until ~= 0 and s.mode == "main" then
    s:_pick_up(now_ms)
    return
  end

  -- at night she cannot be woken nor disturbed (owner, 2026-10-05); looking (Estado, Ajustes) is fine and
  -- goes on below
  local night = s.sleeping and s:is_night()
  if night then
    local label = s:current_label()
    if label ~= "Status" and label ~= "Settings" then
      shh(s, now_ms)
      return
    end
  end

  -- Sleeping: B wakes her, and waking her lasts (v11 phase 2)
  if s.sleeping and not night then
    s.sleeping = false
    s:_emit_sound("despierta") -- heard on the board, and the platform reacts to it
    s.overlay_text = "¿Mmm? ¿Ya es de día?"
    s.overlay_until = now_ms + 900
    s:_log_event("Se despertó")
    s:compute_mood()
    s:mark_dirty()
    return
  end

  -- her growing up calls you: B plays it, and does nothing else (core/scene_grow.py)
  if scene_grow.can_show(s) then
    scene_grow.start(s, now_ms)
    return
  end

  -- a sparrow at the window: B shoos it, and does nothing else (core/bird.py)
  if bird.here(s) and s.mode == "main" then
    bird.shoo(s, now_ms)
    return
  end

  -- hide and seek: B looks in the room on screen
  if s.hidden and s.mode == "main" then
    s:_search_here(now_ms)
    return
  end

  press_menu(s, now_ms)
end

return M
