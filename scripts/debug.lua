local state = require("scripts.state")

local M = {}

-- Dev-only команда (ADR-0001 §10): serpent.block()-дамп текущей сессии
-- игрока в лог -- основной способ проверить entity_number/wire bookkeeping
-- (DoD-тест Phase 2), раз automated-тестов для API-зависимого кода нет
-- (docs/sdlc.md, "Тестирование"). CustomCommandData.player_index -- nil при
-- вызове из серверной консоли (подтверждённый API-факт) -- обрабатывается
-- явно, не молча падает на game.get_player(nil).
function M.dump_session(command)
  if not command.player_index then
    log("Blueprint Editor: eb-dump-session must be run by a player, not the server console.")
    return
  end
  local session = state.get_session(command.player_index)
  local player = game.get_player(command.player_index)
  if not session then
    player.print({"", "Blueprint Editor: no active editor session."})
    return
  end
  -- Дампим entities/tiles отдельно от всей session -- Session также содержит
  -- LuaObject-поля (pre_edit.character, origin.inventory, render_ids), для
  -- которых serpent.block не даёт читаемого вывода и которые не нужны для
  -- DoD-теста (wire bookkeeping смотрится только в entities). Временно, вместе
  -- с остальным playtest-логированием (см. scripts/input.lua) -- убрать перед
  -- закрытием фазы.
  log(serpent.block(session.entities, { name = "session.entities" }))
  log(serpent.block(session.tiles, { name = "session.tiles" }))
  player.print({"", "Blueprint Editor: session dumped to the log."})
end

return M
