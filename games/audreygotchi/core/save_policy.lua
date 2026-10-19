-- save_policy: when to save (v9 §14.2; a port of audreygotchi/core/save_policy.py). The core decides, the platform
-- writes the slot. `now_ms` is the platform's frame tick. A tick that runs backwards (a wrap) saves at once: a
-- spare write costs little, a missed one loses progress.
-- Its fields (_save_last_ms, _save_group_ms, _save_marks) are transient: they belong to the running session, and
-- outlive new_life(). nil is Python's None.
local M = {}

M.AUTOSAVE_MS = 120000
M.GROUP_MS = 15000 -- actions in a burst share one save

-- Moments that save at once: falling asleep or waking, the farewell, a new cycle.
local function marks(s)
  return {(s.sleeping or s.deep_sleep) and true or false,
          (s.farewell_started or s.farewell_scheduled_day ~= 0) and true or false,
          s.cycle}
end

local function same_marks(a, b) -- Python's tuple ==; b is nil before the first save
  if b == nil then return false end
  return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

function M.note_action(s)
  if s._save_group_ms == nil then
    s._save_group_ms = s._frame_ms + M.GROUP_MS -- transient
  end
end

-- A fresh start from Modo Sistema replaces the game on flash at the next look.
function M.request_now(s)
  s._save_group_ms = s._frame_ms -- transient
  if s._save_last_ms == nil then
    s._save_last_ms = s._frame_ms -- transient
  end
end

function M.save_due(s, now_ms)
  if s._save_last_ms == nil then
    M.saved(s, now_ms)
    return false
  end
  if not same_marks(marks(s), s._save_marks) then
    return true
  end
  local since = now_ms - s._save_last_ms
  if since < 0 or since >= M.AUTOSAVE_MS then
    return true
  end
  return s._save_group_ms ~= nil and now_ms >= s._save_group_ms
end

function M.saved(s, now_ms)
  s._save_last_ms = now_ms -- transient
  s._save_group_ms = nil
  s._save_marks = marks(s) -- transient
end

return M
