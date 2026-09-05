local M = {}

-- Чистая логика без Factorio API (ADR-0001 §6): назначает монотонный
-- internal_id каждой сущности блюпринта (не переиспользуя entity_number)
-- и индексирует тайлы по "x,y". Обязательный TDD (docs/sdlc.md, DoD п.6) --
-- тесты в spec/blueprint_io_spec.lua написаны до этой реализации.
function M.build_import_data(bp_entities, bp_tiles)
  local entities = {}
  local next_internal_id = 1
  for _, bp_entity in ipairs(bp_entities) do
    local internal_id = next_internal_id
    next_internal_id = next_internal_id + 1
    entities[internal_id] = { internal_id = internal_id, raw = bp_entity }
  end

  local tiles = {}
  for _, bp_tile in ipairs(bp_tiles) do
    local key = string.format("%d,%d", bp_tile.position.x, bp_tile.position.y)
    tiles[key] = { raw = bp_tile }
  end

  return entities, tiles, next_internal_id
end

-- API-факт (проверено lua-api.factorio.com перед написанием кода): свойство
-- называется `preview_icons`, а не `blueprint_icons` (последнее нигде не
-- существует в текущей версии API -- расхождение с формулировкой ADR-0001
-- §8(b).2, зафиксировано как найденный факт в phase-1-implementation.md).
function M.import_from_stack(cursor_stack)
  if not (cursor_stack and cursor_stack.valid_for_read and cursor_stack.is_blueprint and cursor_stack.is_blueprint_setup()) then
    return nil
  end

  local bp_entities = cursor_stack.get_blueprint_entities() or {}
  local bp_tiles = cursor_stack.get_blueprint_tiles() or {}
  local entities, tiles, next_internal_id = M.build_import_data(bp_entities, bp_tiles)

  return {
    entities = entities,
    tiles = tiles,
    next_internal_id = next_internal_id,
    label = cursor_stack.label,
    icons = cursor_stack.preview_icons,
    blueprint_snap = {
      snap_to_grid = cursor_stack.blueprint_snap_to_grid,
      absolute_snapping = cursor_stack.blueprint_absolute_snapping,
      position_relative_to_grid = cursor_stack.blueprint_position_relative_to_grid,
    },
    origin = { kind = "cursor" },
  }
end

return M
