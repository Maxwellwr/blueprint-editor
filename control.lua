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

local function on_toggle_editor(event)
  local player = game.get_player(event.player_index)
  local session = state.get_session(player.index)
  if session then
    render.clear_session_renders(session)
    surface.teleport_out(player)
  else
    local import_data = blueprint_io.import_from_stack(player, player.cursor_stack, player.cursor_record)
    if surface.teleport_in(player, import_data) then
      local new_session = state.get_session(player.index)
      render.draw_grid(new_session)
      render.draw_entities(new_session)
      render.draw_tiles(new_session)
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
