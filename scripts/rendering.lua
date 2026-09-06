local state = require("scripts.state")

-- Ограниченная сетка вокруг канвас-региона игрока (ADR-0001 §5) -- фиксированное
-- число объектов на сессию (129 линий × 2 = 258), не зависит от размера
-- импортируемого blueprint.
local GRID_HALF_SIZE = 64
local GRID_COLOR = { r = 1, g = 1, b = 1, a = 0.15 }

-- Явный бюджет производительности (docs/sdlc.md): грубая оценка для Phase 1 --
-- порог не блокирует рендер, только логирует для последующей проверки в
-- playtest этой же фазы. Уточняется по факту (batching/LOD -- Phase 7).
local ENTITY_RENDER_WARN_THRESHOLD = 2000

-- Тот же принцип, что ENTITY_RENDER_WARN_THRESHOLD (docs/sdlc.md, "Явный
-- бюджет производительности") -- Phase 1 рисовала тайлы батчем без явного
-- порога; закрывается вместе с переходом draw_tiles на поштучный паттерн.
local TILE_RENDER_WARN_THRESHOLD = 4000

local M = {}

local function canvas_surface()
  return game.surfaces[state.canvas_surface_name()]
end

function M.draw_grid(session)
  local surface = canvas_surface()
  local offset = session.canvas_offset
  local ids = {}
  for i = -GRID_HALF_SIZE, GRID_HALF_SIZE do
    ids[#ids + 1] = rendering.draw_line{
      color = GRID_COLOR,
      width = 1,
      from = { offset.x + i, offset.y - GRID_HALF_SIZE },
      to = { offset.x + i, offset.y + GRID_HALF_SIZE },
      surface = surface,
      players = { session.player_index },
    }
    ids[#ids + 1] = rendering.draw_line{
      color = GRID_COLOR,
      width = 1,
      from = { offset.x - GRID_HALF_SIZE, offset.y + i },
      to = { offset.x + GRID_HALF_SIZE, offset.y + i },
      surface = surface,
      players = { session.player_index },
    }
  end
  session.render_ids.grid = ids
end

function M.draw_entity(session, internal_id)
  local surface = canvas_surface()
  local offset = session.canvas_offset
  local center = session.blueprint_center
  local record = session.entities[internal_id]
  local raw = record.raw
  local orientation = 0
  if raw.direction then
    -- Factorio 2.0: direction в 1/16 оборота; orientation LuaRendering -- доля оборота (0..1).
    orientation = raw.direction / 16
  end
  local sprite = "entity/" .. raw.name
  if not helpers.is_valid_sprite_path(sprite) then
    log(string.format("Blueprint Editor: no sprite for entity '%s' (mod not installed?) -- using placeholder icon.", raw.name))
    sprite = "utility/missing_icon"
  end
  session.render_ids.entities[internal_id] = rendering.draw_sprite{
    sprite = sprite,
    target = { offset.x + raw.position.x - center.x, offset.y + raw.position.y - center.y },
    orientation = orientation,
    surface = surface,
    players = { session.player_index },
  }
end

function M.draw_entities(session)
  local count = 0
  for _ in pairs(session.entities) do
    count = count + 1
  end
  if count > ENTITY_RENDER_WARN_THRESHOLD then
    log(string.format(
      "Blueprint Editor: rendering %d entities, above the Phase 1 soft threshold (%d) -- watch for perf issues.",
      count, ENTITY_RENDER_WARN_THRESHOLD
    ))
  end
  for internal_id in pairs(session.entities) do
    M.draw_entity(session, internal_id)
  end
end

function M.draw_tile(session, key)
  M.clear_tile_render(session, key)
  local surface = canvas_surface()
  local offset = session.canvas_offset
  local center = session.blueprint_center
  local record = session.tiles[key]
  local raw = record.raw
  local sprite = "tile/" .. raw.name
  if not helpers.is_valid_sprite_path(sprite) then
    log(string.format("Blueprint Editor: no sprite for tile '%s' (mod not installed?) -- using placeholder icon.", raw.name))
    sprite = "utility/missing_icon"
  end
  session.render_ids.tiles[key] = rendering.draw_sprite{
    sprite = sprite,
    target = { offset.x + raw.position.x - center.x + 0.5, offset.y + raw.position.y - center.y + 0.5 },
    surface = surface,
    players = { session.player_index },
    -- слой ниже сущностей: тайлы не закрывают сущность на той же ячейке
    render_layer = "ground-layer-1",
  }
end

function M.draw_tiles(session)
  local count = 0
  for _ in pairs(session.tiles) do
    count = count + 1
  end
  if count > TILE_RENDER_WARN_THRESHOLD then
    log(string.format(
      "Blueprint Editor: rendering %d tiles, above the Phase 3 soft threshold (%d) -- watch for perf issues.",
      count, TILE_RENDER_WARN_THRESHOLD
    ))
  end
  for key in pairs(session.tiles) do
    M.draw_tile(session, key)
  end
end

local function destroy_ids(ids)
  if not ids then
    return
  end
  for _, render_object in pairs(ids) do
    if render_object.valid then
      render_object:destroy()
    end
  end
end

function M.clear_entity_render(session, internal_id)
  local render_object = session.render_ids.entities[internal_id]
  if render_object and render_object.valid then
    render_object:destroy()
  end
  session.render_ids.entities[internal_id] = nil
end

function M.clear_tile_render(session, key)
  local render_object = session.render_ids.tiles[key]
  if render_object and render_object.valid then
    render_object:destroy()
  end
  session.render_ids.tiles[key] = nil
end

function M.clear_session_renders(session)
  destroy_ids(session.render_ids.grid)
  destroy_ids(session.render_ids.entities)
  destroy_ids(session.render_ids.tiles)
  session.render_ids = state.new_render_ids()
end

return M
