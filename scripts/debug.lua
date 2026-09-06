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
  log(serpent.block(session, { name = "session" }))
  player.print({"", "Blueprint Editor: session dumped to the log."})
end

return M
