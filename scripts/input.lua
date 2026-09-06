local state = require("scripts.state")
local canvas = require("scripts.canvas")
local render = require("scripts.rendering")

-- Ad-hoc минимальный список размещаемых сущностей (roadmap Phase 2: "A
-- minimal ad-hoc entity picker is fine here; the full palette UI is Phase
-- 5"). Без catalog.lua -- жёстко зашитый небольшой набор, покрывающий
-- typичные playtest-сценарии (пояс, инсертер, два вида сундуков, столб для
-- проверки wire bookkeeping, труба, сборочная машина). Полностью заменяется
-- catalog.lua в Phase 5 -- не переживает эту фазу как архитектура.
local PALETTE_ITEMS = {
  "transport-belt",
  "inserter",
  "iron-chest",
  "wooden-chest",
  "small-electric-pole",
  "pipe",
  "assembling-machine-1",
}

local function area_center(area)
  return {
    x = (area.left_top.x + area.right_bottom.x) / 2,
    y = (area.left_top.y + area.right_bottom.y) / 2,
  }
end

local function palette_index(name)
  for i, item_name in ipairs(PALETTE_ITEMS) do
    if item_name == name then
      return i
    end
  end
  return nil
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
  if not session.selected_palette_item then
    game.get_player(event.player_index).print(
      {"", "Blueprint Editor: no entity selected -- press Q on an existing entity, or [ / ] to cycle the palette."})
    return
  end
  local world_position = area_center(event.area)
  -- Не полноценная collision-детекция (см. phase-2-plan.md "Область фазы" --
  -- сознательно вне scope этой фазы), а точечная защита от самого частого
  -- случая, найденного playtest'ом: повторный клик в ту же уже занятую
  -- клетку молча ставил вторую сущность поверх первой. find_entity_at уже
  -- использует ту же локальную позицию, что place_entity сейчас снапнет.
  if canvas.find_entity_at(session, world_position) then
    game.get_player(event.player_index).print({"", "Blueprint Editor: position already occupied."})
    return
  end
  local internal_id = canvas.place_entity(session, session.selected_palette_item, world_position, 0)
  render.draw_entity(session, internal_id)
end

-- Alt-select -- удаление.
function M.on_player_alt_selected_area(event)
  if event.item ~= "eb-cursor-tool" then
    return
  end
  local session = state.get_session(event.player_index)
  if not session then
    return
  end
  local internal_id = canvas.find_entity_at(session, area_center(event.area))
  if not internal_id then
    return
  end
  render.clear_entity_render(session, internal_id)
  canvas.remove_entity(session, internal_id)
end

function M.on_rotate(event)
  local session = state.get_session(event.player_index)
  if not session then
    return
  end
  local internal_id = canvas.find_entity_at(session, event.cursor_position)
  if not internal_id then
    return
  end
  if canvas.rotate_entity(session, internal_id, 1) then
    render.clear_entity_render(session, internal_id)
    render.draw_entity(session, internal_id)
  end
end

function M.on_delete(event)
  local session = state.get_session(event.player_index)
  if not session then
    return
  end
  local internal_id = canvas.find_entity_at(session, event.cursor_position)
  if not internal_id then
    return
  end
  render.clear_entity_render(session, internal_id)
  canvas.remove_entity(session, internal_id)
end

function M.on_pick_entity(event)
  local session = state.get_session(event.player_index)
  if not session then
    return
  end
  local internal_id = canvas.find_entity_at(session, event.cursor_position)
  if not internal_id then
    return
  end
  session.selected_palette_item = session.entities[internal_id].raw.name
  game.get_player(event.player_index).print({"", "Blueprint Editor: selected " .. session.selected_palette_item})
end

local function is_placeable(name)
  return prototypes.entity[name] ~= nil
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
      player.print({"", "Blueprint Editor: selected " .. candidate})
      return
    end
  end
  player.print({"", "Blueprint Editor: no placeable entities available in the palette (missing mods?)."})
end

function M.on_cycle_palette_next(event)
  cycle_palette(event, 1)
end

function M.on_cycle_palette_prev(event)
  cycle_palette(event, -1)
end

-- ADR-0001 §5: "re-enforce it staying equipped via
-- on_player_cursor_stack_changed while a session is active" -- защита от
-- случайной потери инструмента (Q/скролл/дроп). Проверка ТЕКУЩЕГО стека
-- перед записью обязательна: on_player_cursor_stack_changed фирится и на
-- собственную script-запись (тот же тик, докемументировано как "not
-- instantly"), без этой проверки -- бесконечный цикл событий. Подтверждено
-- playtest'ом Phase 2: ванильное действие Q само чистит курсор, из-за чего
-- этот обработчик срабатывает вслед за каждым промахом Q -- безобидно,
-- переэкипировка проходит мгновенно и не залипает.
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
  end
end

return M
