local state = require("scripts.state")
local migrations = require("scripts.migrations")
local surface = require("scripts.surface")

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

local function on_player_joined_game(event)
  local player = game.get_player(event.player_index)
  local session = state.get_session(player.index)
  if session and player.surface.name ~= state.canvas_surface_name() then
    state.clear_session(player.index)
  end
end

local function on_toggle_editor(event)
  local player = game.get_player(event.player_index)
  if state.get_session(player.index) then
    surface.teleport_out(player)
  else
    surface.teleport_in(player)
  end
end

-- Спайк: подтвердить, что plain click (без drag) с equipped selection-tool
-- всё ещё стреляет on_player_selected_area с маленькой area (ADR-0001 §5,
-- §2 "Unverified"). Временный лог, результат фиксируется в
-- docs/phases/phase-0-implementation.md; полноценная обработка -- input.lua, Phase 2.
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
