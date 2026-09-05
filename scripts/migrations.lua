local state = require("scripts.state")

local M = {}

-- Упорядоченный список {version, fn}, применяется в on_configuration_changed,
-- если storage.mod_version меньше version шага. Пуст в Phase 0 -- мигрировать
-- ещё не от чего. Новые шаги только добавляются в конец, старые не переписываются
-- и не удаляются (docs/sdlc.md, "Миграции только аддитивные").
M.steps = {
  {
    version = "0.2.0",
    fn = function()
      for _, session in state.each_session() do
        session.mode = session.mode or "new"
        session.next_internal_id = session.next_internal_id or 1
        session.entities = session.entities or {}
        session.tiles = session.tiles or {}
        session.render_ids = session.render_ids or { grid = nil, entities = {}, tiles = {} }
      end
    end,
  },
}

local function parse_version(version)
  local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)$")
  return tonumber(major), tonumber(minor), tonumber(patch)
end

local function version_less_than(a, b)
  local a_major, a_minor, a_patch = parse_version(a)
  local b_major, b_minor, b_patch = parse_version(b)
  if a_major ~= b_major then
    return a_major < b_major
  end
  if a_minor ~= b_minor then
    return a_minor < b_minor
  end
  return a_patch < b_patch
end

function M.run()
  local current = state.get_mod_version()
  for _, step in ipairs(M.steps) do
    if version_less_than(current, step.version) then
      step.fn()
      current = step.version
    end
  end
  state.set_mod_version(current)
end

return M
