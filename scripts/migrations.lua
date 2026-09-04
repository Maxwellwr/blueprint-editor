local M = {}

-- Упорядоченный список {version, fn}, применяется в on_configuration_changed,
-- если storage.mod_version меньше version шага. Пуст в Phase 0 -- мигрировать
-- ещё не от чего. Новые шаги только добавляются в конец, старые не переписываются
-- и не удаляются (docs/sdlc.md, "Миграции только аддитивные").
M.steps = {}

function M.run()
  for _, step in ipairs(M.steps) do
    if storage.mod_version ~= step.version then
      step.fn()
      storage.mod_version = step.version
    end
  end
end

return M
