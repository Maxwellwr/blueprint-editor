local M = {}

local function wire_key(id_a, conn_a, id_b, conn_b)
  if id_a > id_b or (id_a == id_b and conn_a > conn_b) then
    id_a, conn_a, id_b, conn_b = id_b, conn_b, id_a, conn_a
  end
  return id_a .. ":" .. conn_a .. ":" .. id_b .. ":" .. conn_b
end

-- Чистая логика без Factorio API (ADR-0001 §6): назначает монотонный
-- internal_id каждой сущности блюпринта (не переиспользуя entity_number),
-- индексирует тайлы по "x,y" и строит EntityRecord.wires по internal_id
-- (ADR-0001 §6, docs/sdlc.md "в первую очередь Phase 2 для remap").
--
-- BlueprintWire -- позиционный кортеж {source_entity_number,
-- source_connector_id, target_entity_number, target_connector_id}
-- (подтверждённый API-факт, см. phase-2-plan.md "Найденные API-факты" --
-- расходится с формулировкой ADR-0001 §6, где поля были именованными).
-- Не задокументировано, дублирует ли игра один провод в wires ОБЕИХ сторон
-- или только одной -- сборка ниже устойчива к обоим случаям: каждый
-- уникальный провод (симметричный ключ wire_key, не зависящий от того, с
-- чьей стороны он встретился) добавляется РОВНО ОДИН РАЗ в wires каждой из
-- двух связанных сущностей, независимо от того, был ли он в исходных данных
-- перечислен раз или дважды.
function M.build_import_data(bp_entities, bp_tiles)
  local entities = {}
  local entity_number_to_internal_id = {}
  local next_internal_id = 1
  for _, bp_entity in ipairs(bp_entities) do
    local internal_id = next_internal_id
    next_internal_id = next_internal_id + 1
    entities[internal_id] = { internal_id = internal_id, raw = bp_entity, wires = {} }
    entity_number_to_internal_id[bp_entity.entity_number] = internal_id
  end

  local seen_wires = {}
  for _, bp_entity in ipairs(bp_entities) do
    if bp_entity.wires then
      for _, wire in ipairs(bp_entity.wires) do
        local source_number, source_connector, target_number, target_connector =
          wire[1], wire[2], wire[3], wire[4]
        local source_id = entity_number_to_internal_id[source_number]
        local target_id = entity_number_to_internal_id[target_number]
        if not source_id or not target_id then
          error(string.format(
            "Blueprint Editor: blueprint wire references entity_number outside the blueprint (%s -> %s)",
            tostring(source_number), tostring(target_number)
          ))
        end
        local key = wire_key(source_id, source_connector, target_id, target_connector)
        if not seen_wires[key] then
          seen_wires[key] = true
          local source_wires = entities[source_id].wires
          source_wires[#source_wires + 1] = {
            target_internal_id = target_id,
            this_connector_id = source_connector,
            target_connector_id = target_connector,
          }
          if source_id ~= target_id then
            local target_wires = entities[target_id].wires
            target_wires[#target_wires + 1] = {
              target_internal_id = source_id,
              this_connector_id = target_connector,
              target_connector_id = source_connector,
            }
          end
        end
      end
    end
  end

  local tiles = {}
  for _, bp_tile in ipairs(bp_tiles) do
    local key = string.format("%d,%d", bp_tile.position.x, bp_tile.position.y)
    tiles[key] = { raw = bp_tile }
  end

  return entities, tiles, next_internal_id
end

-- Чистая логика без Factorio API (ADR-0001 §6, phase-4-plan.md «Задача 1»):
-- детерминированный порядок сущностей для экспорта -- internal_id по
-- возрастанию. `pairs` порядок не гарантирует, а entity_number на экспорте
-- должен быть воспроизводим от запуска к запуску (no-op регрессия).
function M.stable_entity_order(entities)
  local ids = {}
  for internal_id in pairs(entities) do
    ids[#ids + 1] = internal_id
  end
  table.sort(ids)
  return ids
end

-- Чистая логика без Factorio API (ADR-0001 §6, phase-4-plan.md «Задача 1»,
-- вопрос 7 -- принят вариант (а)): для каждой сущности массив BlueprintWire
-- `{own_number, this_connector_id, target_number, target_connector_id}`
-- по export_map (internal_id -> entity_number). Возвращает таблицу
-- internal_id -> array[BlueprintWire]; у сущности без проводов записи нет.
--
-- Каждый уникальный провод эмитится РОВНО ОДИН РАЗ -- на той стороне, чей
-- entity_number меньше (при равенстве, т.е. провод сущности на саму себя, --
-- на меньшем connector_id). Так результат не зависит от того, лежит ли провод
-- в EntityRecord.wires обеих сторон (build_import_data кладёт в обе) или
-- только одной (наследие, ручная сборка), и воспроизводит форму
-- «один кортеж на провод». Решение подлежит проверке спайком S2
-- (phase-4-plan.md «Спайки»): если игра на вставке ожидает провод в wires
-- обеих сторон, переключение -- в этой функции (класть кортеж обеим
-- сторонам вместо одной), тесты правятся вместе.
--
-- Fail-fast: target_internal_id, которого нет в entities, -- нарушение
-- инварианта canvas.remove_wire_references, error() с обоими id.
function M.build_export_wires(entities, export_map)
  local wires_by_id = {}
  local seen = {}
  for _, internal_id in ipairs(M.stable_entity_order(entities)) do
    local own_number = export_map[internal_id]
    for _, wire in ipairs(entities[internal_id].wires or {}) do
      local target_id = wire.target_internal_id
      if not entities[target_id] then
        error(string.format(
          "Blueprint Editor: wire of internal_id %s references internal_id %s missing from session.entities (canvas.remove_wire_references invariant broken)",
          tostring(internal_id), tostring(target_id)
        ))
      end
      local target_number = export_map[target_id]
      local a_number, a_connector, a_id = own_number, wire.this_connector_id, internal_id
      local b_number, b_connector = target_number, wire.target_connector_id
      if a_number > b_number or (a_number == b_number and a_connector > b_connector) then
        a_number, a_connector, a_id, b_number, b_connector =
          b_number, b_connector, target_id, a_number, a_connector
      end
      local key = a_number .. ":" .. a_connector .. ":" .. b_number .. ":" .. b_connector
      if not seen[key] then
        seen[key] = true
        local owner_wires = wires_by_id[a_id]
        if not owner_wires then
          owner_wires = {}
          wires_by_id[a_id] = owner_wires
        end
        owner_wires[#owner_wires + 1] = { a_number, a_connector, b_number, b_connector }
      end
    end
  end
  return wires_by_id
end

-- Явный бюджет производительности (docs/sdlc.md): экспорт -- O(N + W) без
-- render-объектов, порог ничего не блокирует, только логирует размеры сессии
-- для разбора по логу. Значение -- то же, что ENTITY_RENDER_WARN_THRESHOLD в
-- scripts/rendering.lua (phase-4-plan.md, «Global Constraints»); меняются
-- вместе. Константа продублирована, а не импортирована: blueprint_io не
-- должен зависеть от rendering, а тот тянет state/storage.
local EXPORT_SIZE_LOG_THRESHOLD = 2000

-- Чистая логика без Factorio API (ADR-0001 §6, phase-4-plan.md «Задача 1»):
-- array[BlueprintEntity] для set_blueprint_entities из session.entities.
-- entity_number -- плотная нумерация 1..N в порядке stable_entity_order
-- (самый консервативный вариант, спайк S4). Preserve-unknown-fields: shallow
-- copy raw, перекладываются только entity_number и wires -- остальные поля
-- (recipe, control_behavior, items, tags, mirror, quality...) уходят той же
-- ссылкой. У импортированной сущности raw хранит entity_number и wires
-- исходного blueprint'а -- оба обязательно перезаписываются, wires -- в nil,
-- если проводов нет (не пустая таблица: совпадает с формой импорта и не
-- раздувает blueprint). raw и session.entities не мутируются: сессия должна
-- остаться валидной, если запись в предмет провалилась. Позиции не трогаются:
-- raw.position уже в blueprint-пространстве (canvas.place_entity переводит
-- клик через to_local_position), canvas_offset/blueprint_center в экспорте
-- не участвуют.
--
-- Контракт результата: копия shallow, поэтому вложенные таблицы (position,
-- control_behavior, tags, items...) результат ДЕЛИТ с session.entities.
-- Результат нельзя мутировать -- только передать в set_blueprint_entities;
-- если вызывающему нужно его менять, он копирует сам.
function M.export_to_entities_array(session_entities)
  local order = M.stable_entity_order(session_entities)
  local export_map = {}
  for number, internal_id in ipairs(order) do
    export_map[internal_id] = number
  end
  local wires_by_id = M.build_export_wires(session_entities, export_map)

  local result = {}
  local wire_count = 0
  for number, internal_id in ipairs(order) do
    local bp_entity = {}
    for field, value in pairs(session_entities[internal_id].raw) do
      bp_entity[field] = value
    end
    bp_entity.entity_number = number
    local wires = wires_by_id[internal_id]
    if wires and #wires > 0 then
      bp_entity.wires = wires
      wire_count = wire_count + #wires
    else
      bp_entity.wires = nil
    end
    result[number] = bp_entity
  end

  if #result > EXPORT_SIZE_LOG_THRESHOLD then
    log(string.format(
      "Blueprint Editor: exporting a large session (%d entities, %d wires) -- above the %d threshold",
      #result, wire_count, EXPORT_SIZE_LOG_THRESHOLD
    ))
  end
  return result
end

-- Чистая логика без Factorio API (phase-4-plan.md «Задача 1»): массив Tile
-- для set_blueprint_tiles. Tile :: {name, position} -- ровно то, что лежит в
-- TileRecord.raw (API-факт 7 плана), поэтому raw передаётся как есть, той же
-- ссылкой. Порядок -- по position.y, затем position.x: детерминирован и не
-- зависит от порядка `pairs` по ключам "x,y".
--
-- Контракт результата: элементы -- сами raw из session.tiles, результат
-- нельзя мутировать -- только передать в set_blueprint_tiles; нужно менять --
-- копировать на стороне вызывающего.
function M.export_to_tiles_array(session_tiles)
  local records = {}
  for _, record in pairs(session_tiles) do
    records[#records + 1] = record
  end
  table.sort(records, function(a, b)
    local pa, pb = a.raw.position, b.raw.position
    if pa.y ~= pb.y then
      return pa.y < pb.y
    end
    return pa.x < pb.x
  end)
  local tiles = {}
  for index, record in ipairs(records) do
    tiles[index] = record.raw
  end
  return tiles
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
  -- page_path -- active_index каждой пройденной книги, от внешней к внутренней:
  -- ссылку на сам LuaItemStack страницы хранить нельзя (книгу прячут в
  -- mod-owned инвентарь swap_stack'ом), а путь индексов позволяет найти ту же
  -- страницу в запиненной книге при сохранении (phase-4-plan.md «Задача 3»,
  -- вопрос 3).
  local page_path = {}
  while stack and stack.valid_for_read and stack.is_blueprint_book do
    local main_inventory = stack.get_inventory(defines.inventory.item_main)
    if not main_inventory then
      return nil, nil
    end
    page_path[#page_path + 1] = stack.active_index
    stack = main_inventory[stack.active_index]
  end
  if stack and stack.valid_for_read and stack.is_blueprint and stack.is_blueprint_setup() then
    return stack, "cursor", page_path
  end

  return nil, nil
end

-- Чистая логика без Factorio API (phase-4-plan.md «Задача 3»): Session.origin
-- для исходника импорта. Для записи библиотеки -- сама запись и writable
-- (valid_for_write: false для превью и полки «My blueprints», API-факт 2
-- плана); поля аддитивны и nil-safe, код сохранения обязан читать
-- origin.record == nil как «писать нельзя, сохранить как новый». Для
-- инвентарного blueprint'а -- page_path пройденных книг (nil, если исходник не
-- в книге). `valid` проверяется здесь же: невалидная ссылка = не writable.
function M.build_origin(source_kind, source, page_path)
  if source_kind == "cursor_record" then
    return {
      kind = "cursor_record",
      record = source,
      writable = (source.valid and source.valid_for_write) and true or false,
    }
  end
  local origin = { kind = source_kind }
  if page_path and #page_path > 0 then
    origin.page_path = page_path
  end
  return origin
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
-- `get_blueprint_tiles()` есть на обоих типах. Метаданные (label,
-- preview_icons, три snap-поля) читаются одинаково у LuaItemStack и LuaRecord:
-- в целевой версии 2.1.24 у LuaRecord есть RW `label` (API-факт 3 плана; в
-- 2.0.77 его не было -- падение Phase 1), переносить его решено вопросом 9
-- phase-4-plan.md -- иначе фолбэк «сохранить как новый» для read-only записи
-- терял бы её имя.
function M.import_from_stack(player, cursor_stack, cursor_record)
  local source, source_kind, page_path = unwrap_actual_blueprint(player, cursor_stack, cursor_record)
  if not source then
    return nil
  end

  local bp_entities = source.get_blueprint_entities() or {}
  local bp_tiles = source.get_blueprint_tiles() or {}
  local entities, tiles, next_internal_id = M.build_import_data(bp_entities, bp_tiles)
  -- draw_grid (rendering.lua) рисует линии сетки на целых мировых координатах;
  -- рендер сущностей/тайлов и canvas.to_local_position используют
  -- blueprint_center как офсет. Если оставить его дробным (обычный случай --
  -- bounding-box middle почти никогда не целый), офсет сдвигает раскладку на
  -- дробную величину, и сущности перестают попадать в клетки видимой сетки
  -- (найдено playtest'ом Phase 2). Округляем до целого -- сдвиг видимого
  -- центра максимум на полтайла, зато позиции остаются на тех же
  -- чётность-зависимых узлах (.0/.5), что и сетка. compute_bounding_box_center
  -- сам остаётся точным (его busted-тесты не трогаем) -- округление только
  -- здесь, в точке использования.
  local raw_center = M.compute_bounding_box_center(entities, tiles)
  local blueprint_center = { x = math.floor(raw_center.x + 0.5), y = math.floor(raw_center.y + 0.5) }

  -- Метаданные переносятся с исходника как есть (phase-4-plan.md, вопросы 4
  -- и 9) -- и у предмета, и у записи библиотеки одни и те же поля.
  local label = source.label
  local icons = source.preview_icons
  local blueprint_snap = {
    snap_to_grid = source.blueprint_snap_to_grid,
    absolute_snapping = source.blueprint_absolute_snapping,
    position_relative_to_grid = source.blueprint_position_relative_to_grid,
  }

  return {
    entities = entities,
    tiles = tiles,
    next_internal_id = next_internal_id,
    blueprint_center = blueprint_center,
    label = label,
    icons = icons,
    blueprint_snap = blueprint_snap,
    origin = M.build_origin(source_kind, source, page_path),
  }
end

-- ===== Сохранение (phase-4-plan.md «Задача 4») =====

-- Чистая логика без Factorio API: сводка уже построенных массивов
-- BlueprintEntity/Tile -- для решения «пусто / не пусто» (вопрос 5 плана:
-- пустой результат не сохраняется) и для строки лога о большом экспорте.
-- Считает по массивам, а не по сессии: функции экспорта тайлы не видят
-- (ревью Задачи 1), общая сводка N сущностей / W проводов / T тайлов
-- собирается здесь. large -- тот же порог EXPORT_SIZE_LOG_THRESHOLD, по
-- сущностям или по тайлам.
function M.summarize_export(entities, tiles)
  local wires = 0
  for _, bp_entity in ipairs(entities) do
    if bp_entity.wires then
      wires = wires + #bp_entity.wires
    end
  end
  local entity_count, tile_count = #entities, #tiles
  return {
    entities = entity_count,
    wires = wires,
    tiles = tile_count,
    empty = entity_count == 0 and tile_count == 0,
    large = entity_count > EXPORT_SIZE_LOG_THRESHOLD or tile_count > EXPORT_SIZE_LOG_THRESHOLD,
  }
end

-- Чистая логика без Factorio API: куда писать результат. Возвращает target
-- ("stack" | "record" | "new") и reason для сообщения игроку (nil у записи
-- на месте). Решения владельца (phase-4-plan.md «Вопросы владельцу»):
--   * вопрос 2 -- в запись библиотеки пишем на месте, только если В МОМЕНТ
--     ЗАПИСИ record.valid and record.valid_for_write: ссылку могли
--     инвалидировать после входа (спайк S1), поэтому origin.writable с момента
--     входа здесь не решает ничего; иначе -- новый blueprint в руку;
--   * record == nil -- сессия из сохранения старой версии (Global
--     Constraints): «писать нельзя, сохранить как новый»;
--   * kind == "cursor" (swap при входе не удался, исходник остался в руке) --
--     на месте писать некуда: god-курсор не видит руку character-контроллера
--     (phase-1-implementation.md), поэтому новый blueprint; каскад
--     teleport_out положит его в инвентарь, раз курсор занят исходником.
-- record читается как таблица с полями valid/valid_for_write -- тесты
-- подкладывают обычные таблицы. Неизвестный kind -- error() (fail-fast).
function M.choose_save_target(session)
  local origin = session.origin
  if session.mode == "new" or origin == nil then
    return "new", "new_mode"
  end
  if origin.kind == "pinned_stack" then
    return "stack", nil
  end
  if origin.kind == "cursor_record" then
    local record = origin.record
    if record == nil then
      return "new", "record_missing"
    end
    if not record.valid then
      return "new", "record_invalid"
    end
    if not record.valid_for_write then
      return "new", "record_read_only"
    end
    return "record", nil
  end
  if origin.kind == "cursor" then
    return "new", "source_in_hand"
  end
  error("Blueprint Editor: unknown session origin kind " .. tostring(origin.kind))
end

-- Чистая логика без Factorio API: метаданные для write_blueprint_data из
-- полей сессии; ключи -- имена RW-атрибутов LuaItemStack/LuaRecord (API-факты
-- 1, 3, 4 плана). Поля nil-safe: отсутствующее не записывается, чтобы не
-- затирать значения исходника отсутствием данных; у new-режима всё nil --
-- label не задаётся, иконки игра выберет сама (default_icons, вопрос 4).
-- absolute_snapping = false -- значение, а не отсутствие, переносится.
function M.build_save_metadata(session)
  local snap = session.blueprint_snap or {}
  return {
    label = session.label,
    preview_icons = session.icons,
    blueprint_snap_to_grid = snap.snap_to_grid,
    blueprint_absolute_snapping = snap.absolute_snapping,
    blueprint_position_relative_to_grid = snap.position_relative_to_grid,
  }
end

-- Тексты фолбэка «сохранён как новый» по reason из choose_save_target.
local NEW_BLUEPRINT_MESSAGES = {
  new_mode = "Blueprint Editor: saved %d entities and %d tiles as a new blueprint.",
  record_read_only = "Blueprint Editor: the Blueprint Library record is read-only (My blueprints or a preview) -- saved %d entities and %d tiles as a new blueprint in hand instead.",
  record_invalid = "Blueprint Editor: the Blueprint Library record is no longer valid -- saved %d entities and %d tiles as a new blueprint in hand instead.",
  record_missing = "Blueprint Editor: the Blueprint Library record was not remembered for this session -- saved %d entities and %d tiles as a new blueprint in hand instead.",
  source_in_hand = "Blueprint Editor: the source blueprint stayed in your hand -- saved %d entities and %d tiles as a new blueprint instead.",
}

-- Чистая логика без Factorio API: сообщение игроку после успешной записи.
-- Для записи библиотеки на месте -- nil: о ней при выходе сообщает
-- teleport_out по origin.record_updated (заготовка Задачи 3), второе
-- сообщение было бы дублем. Неизвестный target/reason -- error() (fail-fast).
function M.save_result_message(target, reason, summary)
  if target == "stack" then
    return string.format(
      "Blueprint Editor: saved %d entities and %d tiles back to your blueprint.",
      summary.entities, summary.tiles
    )
  elseif target == "record" then
    return nil
  elseif target == "new" then
    local template = NEW_BLUEPRINT_MESSAGES[reason]
    if not template then
      error("Blueprint Editor: unknown save fallback reason " .. tostring(reason))
    end
    return string.format(template, summary.entities, summary.tiles)
  end
  error("Blueprint Editor: unknown save target " .. tostring(target))
end

-- Snap-поля пишутся ДО сущностей (см. write_blueprint_data); порядок важен
-- и для самих полей: position_relative_to_grid имеет смысл только при
-- включённом absolute_snapping.
local SNAP_FIELDS = {
  "blueprint_snap_to_grid",
  "blueprint_absolute_snapping",
  "blueprint_position_relative_to_grid",
}

-- Единая запись в LuaItemStack ИЛИ LuaRecord: у обоих одинаковые
-- set_blueprint_entities/set_blueprint_tiles и RW preview_icons, label,
-- snap-поля (API-факты 1, 3, 4 плана, перепроверены по runtime-api.json
-- 2.1.24). Порядок: snap-поля -> set_blueprint_entities(entities, false) ->
-- set_blueprint_tiles(tiles) -> label -> preview_icons.
--   * fix_positions = false (вопрос 10): позиции остаются как в экспорте
--     «unless invalid for the current snapping» -- поэтому snap выставляется
--     до сущностей, чтобы новый blueprint и перезаписываемый исходник (где
--     snap уже стоит) вели себя одинаково; сдвиг позиций игрой при включённом
--     snap фиксирует спайк S4, ошибкой экспорта не считается.
--   * set_blueprint_tiles вызывается всегда, даже с пустым массивом: игрок мог
--     удалить все тайлы (или все сущности -- set_blueprint_entities тоже
--     всегда). clear_blueprint() не используем: не задокументировано, чистит
--     ли он label/иконки/snap -- проверяется playtest'ом по пунктам
--     «только тайлы» / «только сущности».
--   * metadata-поле nil -- значение цели не трогается.
--   * export нельзя мутировать (контракт export_to_*) -- передаётся как есть.
-- Весь блок -- в pcall: единственная точка, где ошибка API ловится, чтобы не
-- потерять исходник (Global Constraints плана); возвращает ok, err_text.
function M.write_blueprint_data(target, export, metadata)
  local ok, err = pcall(function()
    for _, field in ipairs(SNAP_FIELDS) do
      if metadata[field] ~= nil then
        target[field] = metadata[field]
      end
    end
    target.set_blueprint_entities(export.entities, false)
    target.set_blueprint_tiles(export.tiles)
    if metadata.label ~= nil then
      target.label = metadata.label
    end
    if metadata.preview_icons ~= nil then
      target.preview_icons = metadata.preview_icons
    end
  end)
  log("eb playtest: write_blueprint_data pcall ok=" .. tostring(ok) ..
    " target_type=" .. tostring(target.object_name) ..
    " entities=" .. #export.entities .. " tiles=" .. #export.tiles ..
    " label=" .. tostring(metadata.label) .. " icons=" .. tostring(metadata.preview_icons ~= nil) ..
    " snap=" .. tostring(metadata.blueprint_snap_to_grid ~= nil) ..
    " absolute=" .. tostring(metadata.blueprint_absolute_snapping) ..
    (ok and "" or (" err=" .. tostring(err))))
  if not ok then
    return false, tostring(err)
  end
  return true
end

-- Временное playtest-логирование: export_stack()/export_record() цели для
-- сравнения «до/после» (no-op регрессия) -- под pcall, чтобы диагностика
-- не могла сломать сохранение.
local function playtest_export_string(target)
  local ok, result = pcall(function()
    if target.object_name == "LuaRecord" then
      return target.export_record()
    end
    return target.export_stack()
  end)
  if not ok then
    return "<export failed: " .. tostring(result) .. ">"
  end
  return result
end

-- Страница книги внутри pinned-стека по origin.page_path (active_index
-- каждой пройденной книги, от внешней к внутренней -- unwrap_actual_blueprint):
-- тот же путь, что при импорте (вопрос 3 плана, вариант (а)). Пока книга
-- лежит в mod-owned инвентаре, игрок её не видит и active_index сменить не
-- может. Пустой page_path -- сам корневой стек.
local function resolve_pinned_page(root_stack, page_path)
  local stack = root_stack
  for depth, index in ipairs(page_path or {}) do
    if not (stack.valid_for_read and stack.is_blueprint_book) then
      return nil, string.format("page_path step %d is not a blueprint book", depth)
    end
    local inventory = stack.get_inventory(defines.inventory.item_main)
    if not inventory then
      return nil, string.format("page_path step %d: the book has no item inventory", depth)
    end
    stack = inventory[index]
    if not stack then
      return nil, string.format("page_path step %d: slot %s is out of range", depth, tostring(index))
    end
  end
  return stack
end

local RETRY_HINT = " Your original blueprint is kept; fix and save again, or exit without saving (eb-discard)."

-- origin.kind == "pinned_stack": запись в заколотый стек (или страницу книги
-- в нём) ДО возврата в курсор -- стек лежит в mod-owned инвентаре, контроллер
-- игрока не важен. Неподходящая цель -- false, message (сессия остаётся).
function M.save_back_to_stack(session, export, metadata)
  local origin = session.origin
  local inventory = origin.inventory
  if not (inventory and inventory.valid) then
    return false, "Blueprint Editor: the inventory holding your blueprint is gone -- nothing was written." .. RETRY_HINT
  end
  local stack, why = resolve_pinned_page(inventory[1], origin.page_path)
  if not stack then
    return false, "Blueprint Editor: could not find the blueprint page to write to (" .. why .. ")." .. RETRY_HINT
  end
  if not (stack.valid_for_read and stack.is_blueprint) then
    return false, "Blueprint Editor: the pinned item is not a blueprint -- nothing was written." .. RETRY_HINT
  end
  log("eb playtest: save_back_to_stack page_path=" .. serpent.line(origin.page_path) ..
    " is_book_root=" .. tostring(inventory[1].is_blueprint_book) ..
    " before=" .. playtest_export_string(stack))
  local ok, err = M.write_blueprint_data(stack, export, metadata)
  if not ok then
    return false, "Blueprint Editor: writing the blueprint failed: " .. err .. RETRY_HINT
  end
  log("eb playtest: save_back_to_stack after=" .. playtest_export_string(stack))
  return true
end

-- origin.kind == "cursor_record", запись valid и valid_for_write в момент
-- записи (проверено choose_save_target): запись на месте; record_updated --
-- для сообщения teleport_out (Задача 3).
function M.save_back_to_record(session, export, metadata)
  local record = session.origin.record
  log("eb playtest: save_back_to_record before=" .. playtest_export_string(record))
  local ok, err = M.write_blueprint_data(record, export, metadata)
  if not ok then
    return false, "Blueprint Editor: writing the Blueprint Library record failed: " .. err .. RETRY_HINT
  end
  session.origin.record_updated = true
  log("eb playtest: save_back_to_record after=" .. playtest_export_string(record) ..
    " valid=" .. tostring(record.valid) .. " valid_for_write=" .. tostring(record.valid_for_write))
  return true
end

-- New-режим и все фолбэки: новый предмет blueprint во временном mod-owned
-- инвентаре. Курсор здесь не трогаем -- god-контроллер имеет собственный
-- курсор (phase-1-implementation.md), поэтому origin подменяется на
-- pinned_stack, и готовый blueprint доставляет каскад teleport_out
-- «курсор -> инвентарь -> земля» уже после восстановления
-- character-контроллера (ADR-0001 §8(a).2, вопрос 6). Прежний origin
-- (cursor_record / cursor) при этом отбрасывается: запись библиотеки и рука
-- игрока не трогаются, о фолбэке сообщает save_session. При ошибке записи
-- временный инвентарь уничтожается, origin остаётся прежним.
function M.save_new_blueprint(session, export, metadata)
  local inventory = game.create_inventory(1)
  local stack = inventory[1]
  if not stack.set_stack({ name = "blueprint" }) then
    inventory.destroy()
    return false, "Blueprint Editor: could not create a new blueprint item -- nothing was saved." .. RETRY_HINT
  end
  local ok, err = M.write_blueprint_data(stack, export, metadata)
  if not ok then
    inventory.destroy()
    return false, "Blueprint Editor: writing the new blueprint failed: " .. err .. RETRY_HINT
  end
  log("eb playtest: save_new_blueprint previous_origin=" .. tostring(session.origin and session.origin.kind) ..
    " is_blueprint_setup=" .. tostring(stack.is_blueprint_setup()) ..
    " export=" .. playtest_export_string(stack))
  session.origin = { kind = "pinned_stack", inventory = inventory }
  return true
end

-- Диспетчер сохранения при выходе (control.lua, выход по eb-toggle-editor --
-- вопрос 1). Возвращает ok, message: на false сессия НЕ закрывается, игрок
-- видит сообщение и может исправить или выйти через eb-discard. Запись идёт
-- после успешного экспорта и до возврата pinned-стека в курсор (Global
-- Constraints плана). Пустой экспорт -- отказ без записи (вопрос 5).
function M.save_session(session)
  local entities = M.export_to_entities_array(session.entities)
  local tiles = M.export_to_tiles_array(session.tiles)
  local summary = M.summarize_export(entities, tiles)
  if summary.empty then
    return false, "Blueprint Editor: nothing to save (no entities and no tiles) -- the source was left untouched; keep editing or exit without saving (eb-discard)."
  end
  if summary.large then
    log(string.format(
      "Blueprint Editor: saving a large session (%d entities, %d wires, %d tiles) -- above the %d threshold",
      summary.entities, summary.wires, summary.tiles, EXPORT_SIZE_LOG_THRESHOLD
    ))
  end

  local export = { entities = entities, tiles = tiles }
  local metadata = M.build_save_metadata(session)
  local target, reason = M.choose_save_target(session)
  -- Спайк S1 в момент записи: живые valid/valid_for_write записи против
  -- writable, запомненного на входе.
  local origin = session.origin or {}
  local record = origin.record
  log("eb playtest: save_session player=" .. tostring(session.player_index) ..
    " mode=" .. tostring(session.mode) .. " origin.kind=" .. tostring(origin.kind) ..
    " origin.writable=" .. tostring(origin.writable) ..
    " record.valid=" .. tostring(record and record.valid) ..
    " record.valid_for_write=" .. tostring(record and record.valid and record.valid_for_write) ..
    " target=" .. target .. " reason=" .. tostring(reason) ..
    " entities=" .. summary.entities .. " wires=" .. summary.wires .. " tiles=" .. summary.tiles)
  local ok, err
  if target == "stack" then
    ok, err = M.save_back_to_stack(session, export, metadata)
  elseif target == "record" then
    ok, err = M.save_back_to_record(session, export, metadata)
  else
    ok, err = M.save_new_blueprint(session, export, metadata)
  end
  log("eb playtest: save_session result ok=" .. tostring(ok) .. (ok and "" or (" err=" .. tostring(err))))
  if not ok then
    return false, err
  end
  return true, M.save_result_message(target, reason, summary)
end

-- Временное playtest-логирование, спайк S4 (phase-4-plan.md «Спайки»,
-- вопрос 10): один и тот же экспорт пишется в два временных blueprint'а --
-- set_blueprint_entities(e, false) и set_blueprint_entities(e) (умолчание) --
-- и сравниваются export_stack(). Снап-поля сессии переносятся на оба, чтобы
-- оговорка «unless invalid for the current snapping» действовала одинаково.
-- Ничего в сессии и исходнике не трогает; вызывается из /eb-dump-export.
function M.playtest_compare_fix_positions(session)
  local entities = M.export_to_entities_array(session.entities)
  local tiles = M.export_to_tiles_array(session.tiles)
  local metadata = M.build_save_metadata(session)
  local results = {}
  for _, variant in ipairs({ "false", "default" }) do
    local inventory = game.create_inventory(1)
    local stack = inventory[1]
    local ok, err = pcall(function()
      assert(stack.set_stack({ name = "blueprint" }), "set_stack blueprint failed")
      for _, field in ipairs(SNAP_FIELDS) do
        if metadata[field] ~= nil then
          stack[field] = metadata[field]
        end
      end
      if variant == "false" then
        stack.set_blueprint_entities(entities, false)
      else
        stack.set_blueprint_entities(entities)
      end
      stack.set_blueprint_tiles(tiles)
    end)
    if ok then
      results[variant] = stack.export_stack()
      log("eb playtest: S4 fix_positions=" .. variant .. " entities=" ..
        serpent.line(stack.get_blueprint_entities() or {}, { comment = false }))
    else
      results[variant] = "<failed: " .. tostring(err) .. ">"
    end
    inventory.destroy()
  end
  log("eb playtest: S4 fix_positions=false export=" .. results["false"])
  log("eb playtest: S4 fix_positions=default export=" .. results["default"])
  log("eb playtest: S4 identical=" .. tostring(results["false"] == results["default"]))
end

return M
