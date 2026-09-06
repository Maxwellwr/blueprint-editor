local M = {}

-- Чистая логика без Factorio API (ADR-0001 §5, подтверждено
-- LuaEntityPrototype.tile_width/tile_height, см. phase-2-plan.md "Найденные
-- API-факты"): нечётный размер -- центр сущности на центре тайла (x.5),
-- чётный -- на границе тайлов (x.0).
local function snap_axis(value, size)
  if size % 2 == 1 then
    return math.floor(value) + 0.5
  end
  return math.floor(value + 0.5)
end

function M.snap_position(tile_width, tile_height, raw_position)
  return {
    x = snap_axis(raw_position.x, tile_width),
    y = snap_axis(raw_position.y, tile_height),
  }
end

-- Чистая логика: direction в Factorio 2.0 -- 1/16 оборота (0..15). Phase 2
-- MVP вращает фиксированным шагом в четверть оборота вне зависимости от
-- собственной гранулярности сущности (осознанно отложенный нюанс, см.
-- phase-2-plan.md "Область фазы").
function M.next_direction(current_direction, steps)
  local step_count = steps or 1
  return ((current_direction or 0) + step_count * 4) % 16
end

-- Чистая логика (ADR-0001 §6, флагманский TDD-пример из docs/sdlc.md): при
-- удалении сущности вычищает ссылки на неё из wires всех ОСТАЛЬНЫХ сущностей.
-- Мутирует `entities` на месте -- вызывающая сторона (M.remove_entity) уже
-- удалила саму запись под removed_internal_id до вызова этой функции.
function M.remove_wire_references(entities, removed_internal_id)
  for id, record in pairs(entities) do
    if id ~= removed_internal_id and record.wires then
      local kept = {}
      for _, wire in ipairs(record.wires) do
        if wire.target_internal_id ~= removed_internal_id then
          kept[#kept + 1] = wire
        end
      end
      record.wires = kept
    end
  end
end

-- Ниже -- API-зависимые обёртки (docs/sdlc.md "Тестирование": не покрыты
-- busted, верификация -- dev-loop + ручной playtest, Задача 9).

-- Только для свежеразмещённых сущностей строится новый минимальный raw
-- (preserve-unknown-fields, ADR-0001 §6) -- импортированные сущности этой
-- функцией не создаются.
function M.place_entity(session, name, world_position, direction)
  local prototype = prototypes.entity[name]
  if not prototype then
    error(string.format("Blueprint Editor: unknown entity prototype '%s'", name))
  end
  local internal_id = session.next_internal_id
  session.next_internal_id = internal_id + 1
  local local_position = M.to_local_position(session, world_position)
  session.entities[internal_id] = {
    internal_id = internal_id,
    raw = {
      name = name,
      position = M.snap_position(prototype.tile_width, prototype.tile_height, local_position),
      direction = direction or 0,
    },
    wires = {},
  }
  return internal_id
end

function M.remove_entity(session, internal_id)
  local record = session.entities[internal_id]
  if not record then
    return nil
  end
  session.entities[internal_id] = nil
  M.remove_wire_references(session.entities, internal_id)
  return record
end

-- nil, если сущность не найдена или её прототип не поддерживает вращение
-- (LuaEntityPrototype.supports_direction, найденный API-факт).
function M.rotate_entity(session, internal_id, steps)
  local record = session.entities[internal_id]
  if not record then
    return nil
  end
  local prototype = prototypes.entity[record.raw.name]
  if not prototype or not prototype.supports_direction then
    return nil
  end
  record.raw.direction = M.next_direction(record.raw.direction, steps)
  return record.raw.direction
end

-- Обратная операция офсета из rendering.lua (target = canvas_offset +
-- raw.position - blueprint_center) -- переводит мировую (target-space)
-- позицию клика обратно в локальные координаты blueprint'а.
function M.to_local_position(session, world_position)
  local offset = session.canvas_offset
  local center = session.blueprint_center
  return {
    x = world_position.x - offset.x + center.x,
    y = world_position.y - offset.y + center.y,
  }
end

-- Чистая логика (API-факт: TilePosition "rounds any non-integer x/y down to
-- whole numbers", doc-html/runtime-api.json -- см. phase-3-plan.md "Найденные
-- API-факты") -- в отличие от snap_position у сущностей, тайлы всегда 1x1 и
-- без odd/even-центрирования, просто floor по обеим осям.
function M.tile_coordinates(local_position)
  return { x = math.floor(local_position.x), y = math.floor(local_position.y) }
end

-- Тот же формат "x,y", что уже использует blueprint_io.build_import_data для
-- ключей session.tiles -- не создаём второй несовместимый способ индексации
-- одной и той же таблицы.
function M.tile_key(x, y)
  return string.format("%d,%d", x, y)
end

-- Первая сущность, чей footprint (tile_width/tile_height вокруг raw.position,
-- то же правило центрирования, что и snap_position) содержит world_position.
-- Коллизии не проверяются при размещении (см. "Область фазы") -- при
-- наложении спрайтов возвращает первую найденную в порядке pairs()
-- (недетерминированно), это принятое ограничение MVP, не баг.
function M.find_entity_at(session, world_position)
  local local_position = M.to_local_position(session, world_position)
  for internal_id, record in pairs(session.entities) do
    local prototype = prototypes.entity[record.raw.name]
    local tile_width = prototype and prototype.tile_width or 1
    local tile_height = prototype and prototype.tile_height or 1
    local pos = record.raw.position
    local half_w, half_h = tile_width / 2, tile_height / 2
    if local_position.x >= pos.x - half_w and local_position.x <= pos.x + half_w
        and local_position.y >= pos.y - half_h and local_position.y <= pos.y + half_h then
      return internal_id
    end
  end
  return nil
end

-- Ниже -- API-зависимые обёртки для тайлов (docs/sdlc.md "Тестирование":
-- верификация -- dev-loop + ручной playtest, Задача 5).

-- В отличие от place_entity, всегда ПЕРЕЗАПИСЫВАЕТ тайл в клетке -- решение,
-- зафиксированное при планировании фазы (см. phase-3-plan.md "Область
-- фазы"): на клетке физически может быть только один тайл, повторный клик --
-- "покраска", а не конфликт размещения, отклонять нечего. Preserve-
-- unknown-fields (ADR-0001 §6): новый минимальный raw ({name, position})
-- строится только для этой -- свежеразмещённой/перезаписанной -- записи;
-- импортированные TileRecord под другими ключами не трогаются.
function M.place_tile(session, name, world_position)
  if not prototypes.tile[name] then
    error(string.format("Blueprint Editor: unknown tile prototype '%s'", name))
  end
  local local_position = M.to_local_position(session, world_position)
  local coords = M.tile_coordinates(local_position)
  local key = M.tile_key(coords.x, coords.y)
  session.tiles[key] = { raw = { name = name, position = coords } }
  return key
end

function M.remove_tile(session, key)
  local record = session.tiles[key]
  if not record then
    return nil
  end
  session.tiles[key] = nil
  return record
end

-- Тайлы всегда занимают ровно одну клетку -- в отличие от find_entity_at,
-- никакого footprint-перебора не нужно, прямое попадание по ключу клетки.
function M.find_tile_at(session, world_position)
  local local_position = M.to_local_position(session, world_position)
  local coords = M.tile_coordinates(local_position)
  local key = M.tile_key(coords.x, coords.y)
  if session.tiles[key] then
    return key
  end
  return nil
end

return M
