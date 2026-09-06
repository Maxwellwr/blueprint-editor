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

-- Чистая логика без Factorio API: центр bounding box всех сущностей и тайлов
-- (в локальных координатах самого blueprint'а). Нужен, чтобы отрисовать
-- содержимое чертежа так, чтобы его центр совпадал с точкой, куда
-- телепортируется игрок -- позиции BlueprintEntity/Tile сохраняют координаты
-- реального мира на момент захвата, а не нормализованы к (0,0) (найдено
-- playtest'ом: чертёж, захваченный далеко от спавна, рендерился за пределами
-- видимой области). {0, 0} для пустого чертежа ("new"-режим).
function M.compute_bounding_box_center(entities, tiles)
  local min_x, min_y, max_x, max_y = nil, nil, nil, nil
  local function consider(position)
    if min_x == nil or position.x < min_x then min_x = position.x end
    if max_x == nil or position.x > max_x then max_x = position.x end
    if min_y == nil or position.y < min_y then min_y = position.y end
    if max_y == nil or position.y > max_y then max_y = position.y end
  end
  for _, record in pairs(entities) do
    consider(record.raw.position)
  end
  for _, record in pairs(tiles) do
    consider(record.raw.position)
  end
  if min_x == nil then
    return { x = 0, y = 0 }
  end
  return { x = (min_x + max_x) / 2, y = (min_y + max_y) / 2 }
end

-- Разворачивает blueprint-книгу (если держат книгу, а не одиночный чертёж)
-- до её текущей выбранной страницы -- по образцу проверенной сторонней
-- реализации (wcjohnson/factorio-mod-core, blueprint/actual.lua), не
-- придумано с нуля. `record` предпочтительнее `stack`, если оба присутствуют
-- (см. import_from_stack). `is_preview` отсекает превью-запись библиотеки,
-- которая выглядит как blueprint, но не является реальными данными.
local function unwrap_actual_blueprint(player, cursor_stack, cursor_record)
  local record = cursor_record
  while record and record.valid and record.type == "blueprint-book" do
    record = record.get_selected_record(player)
  end
  if record and record.valid and not record.is_preview and record.type == "blueprint" and record.is_blueprint_setup() then
    return record, "cursor_record"
  end

  local stack = cursor_stack
  if not (stack and stack.valid_for_read) then
    return nil, nil
  end
  while stack and stack.valid_for_read and stack.is_blueprint_book do
    local main_inventory = stack.get_inventory(defines.inventory.item_main)
    if not main_inventory then
      return nil, nil
    end
    stack = main_inventory[stack.active_index]
  end
  if stack and stack.valid_for_read and stack.is_blueprint and stack.is_blueprint_setup() then
    return stack, "cursor"
  end

  return nil, nil
end

-- API-факт (проверено lua-api.factorio.com перед написанием кода): свойство
-- называется `preview_icons`, а не `blueprint_icons` (последнее нигде не
-- существует в текущей версии API -- расхождение с формулировкой ADR-0001
-- §8(b).2, зафиксировано как найденный факт в phase-1-implementation.md).
--
-- API-факт (Phase 1, патч 0.2.1): blueprint, перетащенный прямо из игровой
-- Blueprint Library, попадает в `player.cursor_record` (LuaRecord), а не в
-- `player.cursor_stack` (LuaItemStack) -- последний в этом случае читается
-- как невалидный (`valid_for_read = false`). `get_blueprint_entities()`/
-- `get_blueprint_tiles()` есть на обоих типах -- этого достаточно для
-- рендера и отменяет известное ограничение из phase-1-implementation.md
-- ("перенос из Blueprint Library не работает"). Метаданные (`label`,
-- `preview_icons`, snap-настройки) для LuaRecord НЕ читаем: документация
-- по составу его полей дважды дала противоречивые сведения (в т.ч. ложно
-- утверждала наличие `label`, которого в реальности нет -- падение
-- подтверждено в игре), а Phase 1 эти поля всё равно нигде не использует.
-- Уточнить точный набор полей LuaRecord, когда они реально понадобятся
-- (Phase 4, сохранение обратно).
function M.import_from_stack(player, cursor_stack, cursor_record)
  local source, source_kind = unwrap_actual_blueprint(player, cursor_stack, cursor_record)
  if not source then
    return nil
  end

  local bp_entities = source.get_blueprint_entities() or {}
  local bp_tiles = source.get_blueprint_tiles() or {}
  local entities, tiles, next_internal_id = M.build_import_data(bp_entities, bp_tiles)
  local blueprint_center = M.compute_bounding_box_center(entities, tiles)

  local label, icons, blueprint_snap
  if source_kind == "cursor" then
    label = source.label
    icons = source.preview_icons
    blueprint_snap = {
      snap_to_grid = source.blueprint_snap_to_grid,
      absolute_snapping = source.blueprint_absolute_snapping,
      position_relative_to_grid = source.blueprint_position_relative_to_grid,
    }
  end

  return {
    entities = entities,
    tiles = tiles,
    next_internal_id = next_internal_id,
    blueprint_center = blueprint_center,
    label = label,
    icons = icons,
    blueprint_snap = blueprint_snap,
    origin = { kind = source_kind },
  }
end

return M
