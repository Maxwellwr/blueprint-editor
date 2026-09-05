local state = require("scripts.state")
local migrations = require("scripts.migrations")
local surface = require("scripts.surface")
local blueprint_io = require("scripts.blueprint_io")
local render = require("scripts.rendering")

local function on_init()
  state.init()
  surface.ensure_canvas_surface()
end

local function on_configuration_changed()
  state.init()
  migrations.run()
  surface.ensure_canvas_surface()
end

local function on_load()
  -- Пусто намеренно: `game` недоступен внутри on_load, а запись в `storage`
  -- запрещена (lua-api.factorio.com/latest/auxiliary/data-lifecycle.html).
  -- Очистка осиротевших сессий (ADR-0001 §4, "Known MVP limitation") перенесена
  -- в on_player_joined_game, который срабатывает после on_load, когда `game`
  -- уже доступен и запись в `storage` разрешена.
end

local function on_player_joined_game()
  for player_index, session in state.each_session() do
    local player = game.get_player(player_index)
    if not player or player.surface.name ~= state.canvas_surface_name() then
      render.clear_session_renders(session)
      state.clear_session(player_index)
    end
  end
end

-- TODO(Phase 1 debug, remove before closeout): второй заход диагностики --
-- "второй чертёж рендерится пустым". Логирует cursor_stack, entity_count,
-- и позиции первых нескольких сущностей, чтобы понять расхождение с первым.
local function on_toggle_editor(event)
  local player = game.get_player(event.player_index)
  local session = state.get_session(player.index)
  if session then
    render.clear_session_renders(session)
    surface.teleport_out(player)
  else
    local cs = player.cursor_stack
    log(string.format(
      "eb debug2: cursor label=%s entity_count=%s",
      tostring(cs and cs.valid_for_read and cs.label),
      tostring(cs and cs.valid_for_read and cs.is_blueprint and cs.get_blueprint_entity_count())
    ))
    local import_data = blueprint_io.import_from_stack(cs)
    if import_data then
      local n = 0
      for internal_id, record in pairs(import_data.entities) do
        n = n + 1
        if n <= 5 then
          log(string.format(
            "eb debug2: entity[%d] name=%s position=%s direction=%s",
            internal_id, record.raw.name, serpent.line(record.raw.position), tostring(record.raw.direction)
          ))
        end
      end
      log(string.format("eb debug2: total entities=%d canvas_offset will be region_offset(%d)", n, player.index))
    else
      log("eb debug2: import_data is nil")
    end
    if surface.teleport_in(player, import_data) then
      local new_session = state.get_session(player.index)
      log(string.format("eb debug2: session.canvas_offset=%s", serpent.line(new_session.canvas_offset)))
      render.draw_grid(new_session)
      render.draw_entities(new_session)
      render.draw_tiles(new_session)
      local rendered = 0
      for _ in pairs(new_session.render_ids.entities) do rendered = rendered + 1 end
      log(string.format("eb debug2: draw_entities stored %d ids", rendered))
    end
  end
end

-- Спайк: подтвердить, что plain click (без drag) с equipped selection-tool
-- всё ещё стреляет on_player_selected_area с маленькой area (ADR-0001 §5,
-- §2 "Unverified"). Временный лог, результат зафиксирован как подтверждённый
-- факт в docs/phases/phase-0-implementation.md.
-- TODO(Phase 2): удалить этот хендлер, заменить полноценной обработкой в input.lua.
local function on_selected_area(event)
  if event.item == "eb-cursor-tool" then
    log(string.format(
      "eb spike: on_player_selected_area fired, area=%s, entities=%d",
      serpent.line(event.area), #event.entities
    ))
  end
end

script.on_init(on_init)
script.on_configuration_changed(on_configuration_changed)
script.on_load(on_load)
script.on_event(defines.events.on_player_joined_game, on_player_joined_game)
script.on_event("eb-toggle-editor", on_toggle_editor)
script.on_event(defines.events.on_player_selected_area, on_selected_area)
