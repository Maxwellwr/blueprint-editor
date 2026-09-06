local state = require("scripts.state")
local canvas = require("scripts.canvas")
local render = require("scripts.rendering")

-- Ad-hoc единый список размещаемых сущностей и тайлов (roadmap Phase 3:
-- "tile catalog basics" -- та же ad-hoc-костыльная конструкция, что
-- PALETTE_ITEMS в Phase 2, теперь вперемешку {kind, name}. [ / ] листают весь
-- список без отдельного режима entity/tile (решение, зафиксированное при
-- планировании фазы, см. phase-3-plan.md "Область фазы"). Полностью
-- заменяется catalog.lua в Phase 5. Имена тайлов проверены в файлах
-- установленной игры (см. phase-3-plan.md "Найденные API-факты"), не по
-- памяти.
local PALETTE_ITEMS = {
  { kind = "entity", name = "transport-belt" },
  { kind = "entity", name = "inserter" },
  { kind = "entity", name = "iron-chest" },
  { kind = "entity", name = "wooden-chest" },
  { kind = "entity", name = "small-electric-pole" },
  { kind = "entity", name = "pipe" },
  { kind = "entity", name = "assembling-machine-1" },
  { kind = "tile", name = "concrete" },
  { kind = "tile", name = "stone-path" },
  { kind = "tile", name = "refined-concrete" },
  { kind = "tile", name = "landfill" },
}

local function area_center(area)
  return {
    x = (area.left_top.x + area.right_bottom.x) / 2,
    y = (area.left_top.y + area.right_bottom.y) / 2,
  }
end

local function palette_index(selected)
  if not selected then
    return nil
  end
  for i, item in ipairs(PALETTE_ITEMS) do
    if item.kind == selected.kind and item.name == selected.name then
      return i
    end
  end
  return nil
end

local function is_placeable(item)
  if item.kind == "entity" then
    return prototypes.entity[item.name] ~= nil
  end
  return prototypes.tile[item.name] ~= nil
end

-- Общий паттерн для eb-rotate (найдено code review Phase 2) -- найти сессию
-- игрока, затем СУЩНОСТЬ на указанной позиции. Только сущности: у тайлов нет
-- вращения (ADR-0001, тайлы без direction -- см. phase-3-plan.md "Найденные
-- API-факты"), поэтому eb-rotate остаётся entity-only и этой функцией не
-- расширяется на тайлы.
local function get_session_and_entity(player_index, position)
  local session = state.get_session(player_index)
  if not session then
    return nil, nil
  end
  return session, canvas.find_entity_at(session, position)
end

-- Общий паттерн для удаления/подбора (Задача 4, Phase 3) -- сначала ищет
-- сущность под позицией, затем (если сущности нет) тайл. Приоритет
-- "сущность, потом тайл" зафиксирован при планировании фазы (см.
-- phase-3-plan.md "Область фазы") -- один обработчик на оба случая, без
-- привязки к тому, что сейчас выбрано в палитре.
local function get_session_and_target(player_index, position)
  local session = state.get_session(player_index)
  if not session then
    return nil, nil, nil
  end
  local internal_id = canvas.find_entity_at(session, position)
  if internal_id then
    return session, "entity", internal_id
  end
  local tile_key = canvas.find_tile_at(session, position)
  if tile_key then
    return session, "tile", tile_key
  end
  return session, nil, nil
end

local function remove_at(player_index, position)
  local session, kind, target = get_session_and_target(player_index, position)
  if not session or not kind then
    return
  end
  if kind == "entity" then
    render.clear_entity_render(session, target)
    canvas.remove_entity(session, target)
    log(string.format("eb playtest: removed entity id=%s", tostring(target)))
  else
    render.clear_tile_render(session, target)
    canvas.remove_tile(session, target)
    log(string.format("eb playtest: removed tile key=%s", tostring(target)))
  end
end

local M = {}

-- Primary select (клик/драг с eb-cursor-tool) -- размещение. event.entities
-- на eb-canvas всегда пуст (подтверждено playtest'ом Phase 2 -- канвас
-- никогда не содержит реальных сущностей), поэтому вся логика опирается
-- только на event.area.
function M.on_player_selected_area(event)
  if event.item ~= "eb-cursor-tool" then
    return
  end
  local session = state.get_session(event.player_index)
  if not session then
    return
  end
  local selected = session.selected_palette_item
  if not selected then
    game.get_player(event.player_index).print(
      {"", "Blueprint Editor: nothing selected -- press Q on an existing entity/tile, or [ / ] to cycle the palette."})
    return
  end
  local world_position = area_center(event.area)
  if selected.kind == "entity" then
    -- Не полноценная collision-детекция (см. phase-2-plan.md "Область
    -- фазы" -- сознательно вне scope), а точечная защита от повторного
    -- клика в занятую клетку (найдено playtest'ом Phase 2).
    if canvas.find_entity_at(session, world_position) then
      game.get_player(event.player_index).print({"", "Blueprint Editor: position already occupied."})
      return
    end
    local internal_id = canvas.place_entity(session, selected.name, world_position, 0)
    render.draw_entity(session, internal_id)
    log(string.format("eb playtest: placed entity '%s' id=%d at (%.2f,%.2f)", selected.name, internal_id, world_position.x, world_position.y))
  else
    -- Тайлы перезаписываются без occupied-guard (см. phase-3-plan.md
    -- "Область фазы") -- place_tile и draw_tile сами корректно обрабатывают
    -- уже занятую клетку.
    local key = canvas.place_tile(session, selected.name, world_position)
    render.draw_tile(session, key)
    log(string.format("eb playtest: placed tile '%s' key=%s at (%.2f,%.2f)", selected.name, key, world_position.x, world_position.y))
  end
end

-- Alt-select -- удаление (сущность, иначе тайл).
function M.on_player_alt_selected_area(event)
  if event.item ~= "eb-cursor-tool" then
    return
  end
  remove_at(event.player_index, area_center(event.area))
end

function M.on_rotate(event)
  local session, internal_id = get_session_and_entity(event.player_index, event.cursor_position)
  if not session or not internal_id then
    return
  end
  if canvas.rotate_entity(session, internal_id, 1) then
    render.clear_entity_render(session, internal_id)
    render.draw_entity(session, internal_id)
  end
end

-- Удаление по хоткею (альтернатива alt-клику) -- та же логика "сущность,
-- иначе тайл".
function M.on_delete(event)
  remove_at(event.player_index, event.cursor_position)
end

-- Подбор в палитру того, что под курсором -- сущность, иначе тайл (тот же
-- приоритет, что и у удаления).
function M.on_pick_entity(event)
  local session, kind, target = get_session_and_target(event.player_index, event.cursor_position)
  if not session or not kind then
    return
  end
  local name
  if kind == "entity" then
    name = session.entities[target].raw.name
  else
    name = session.tiles[target].raw.name
  end
  session.selected_palette_item = { kind = kind, name = name }
  game.get_player(event.player_index).print({"", "Blueprint Editor: selected " .. name})
  log(string.format("eb playtest: picked %s '%s'", kind, name))
end

local function cycle_palette(event, delta)
  local session = state.get_session(event.player_index)
  if not session then
    return
  end
  local player = game.get_player(event.player_index)
  local current_index = palette_index(session.selected_palette_item) or 0
  for _ = 1, #PALETTE_ITEMS do
    current_index = ((current_index - 1 + delta) % #PALETTE_ITEMS) + 1
    local candidate = PALETTE_ITEMS[current_index]
    if is_placeable(candidate) then
      session.selected_palette_item = candidate
      player.print({"", "Blueprint Editor: selected " .. candidate.name})
      log(string.format("eb playtest: palette cycled to %s '%s'", candidate.kind, candidate.name))
      return
    end
  end
  player.print({"", "Blueprint Editor: nothing placeable available in the palette (missing mods?)."})
end

function M.on_cycle_palette_next(event)
  cycle_palette(event, 1)
end

function M.on_cycle_palette_prev(event)
  cycle_palette(event, -1)
end

-- ADR-0001 §5: "re-enforce it staying equipped via
-- on_player_cursor_stack_changed while a session is active" -- без изменений
-- относительно Phase 2.
function M.on_cursor_stack_changed(event)
  local session = state.get_session(event.player_index)
  if not session then
    return
  end
  local player = game.get_player(event.player_index)
  local cursor_stack = player.cursor_stack
  if not cursor_stack then
    return
  end
  if cursor_stack.valid_for_read and cursor_stack.name == "eb-cursor-tool" then
    return
  end
  if player.clear_cursor() then
    cursor_stack.set_stack({ name = "eb-cursor-tool" })
  else
    player.print({"", "Blueprint Editor: could not re-equip the cursor tool (cursor full)."})
  end
end

return M
