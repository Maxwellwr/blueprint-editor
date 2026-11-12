local state = require("scripts.state")
local blueprint_io = require("scripts.blueprint_io")

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
  -- DoD-теста (wire bookkeeping смотрится только в entities). Постоянное
  -- решение, не часть временного playtest-логирования -- найдено при
  -- финальном ревью Phase 2 (Minor: "session целиком слишком шумный лог").
  log(serpent.block(session.entities, { name = "session.entities" }))
  log(serpent.block(session.tiles, { name = "session.tiles" }))
  player.print({"", "Blueprint Editor: session dumped to the log."})
end

-- Dev-only команда (phase-4-plan.md «Задача 4», опционально): результат
-- экспорта текущей сессии -- массивы BlueprintEntity/Tile, сводка и выбранная
-- цель сохранения -- в лог БЕЗ записи в предмет/запись. Разбор по логу того,
-- что ушло бы в set_blueprint_entities/set_blueprint_tiles, не трогая
-- исходник (no-op регрессия, S2/S4 в Задаче 5).
function M.dump_export(command)
  if not command.player_index then
    log("Blueprint Editor: eb-dump-export must be run by a player, not the server console.")
    return
  end
  local session = state.get_session(command.player_index)
  local player = game.get_player(command.player_index)
  if not session then
    player.print({"", "Blueprint Editor: no active editor session."})
    return
  end
  local entities = blueprint_io.export_to_entities_array(session.entities)
  local tiles = blueprint_io.export_to_tiles_array(session.tiles)
  local summary = blueprint_io.summarize_export(entities, tiles)
  local target, reason = blueprint_io.choose_save_target(session)
  log(serpent.block(entities, { name = "export.entities" }))
  log(serpent.block(tiles, { name = "export.tiles" }))
  log(serpent.block(blueprint_io.build_save_metadata(session), { name = "export.metadata" }))
  log(string.format(
    "Blueprint Editor: export summary -- %d entities, %d wires, %d tiles; save target = %s (%s)",
    summary.entities, summary.wires, summary.tiles, target, tostring(reason)
  ))
  player.print({"", "Blueprint Editor: export dumped to the log (nothing was written)."})
end

return M
