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

local M = {}

function M.draw_grid(session)
  local surface = game.surfaces[state.canvas_surface_name()]
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

function M.draw_entities(session)
  local surface = game.surfaces[state.canvas_surface_name()]
  local offset = session.canvas_offset

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

  for internal_id, record in pairs(session.entities) do
    local raw = record.raw
    local orientation = 0
    if raw.direction then
      -- Factorio 2.0: direction в 1/16 оборота; orientation LuaRendering -- доля оборота (0..1).
      orientation = raw.direction / 16
    end
    session.render_ids.entities[internal_id] = rendering.draw_sprite{
      sprite = "entity/" .. raw.name,
      target = { offset.x + raw.position.x, offset.y + raw.position.y },
      orientation = orientation,
      surface = surface,
      players = { session.player_index },
    }
  end
end

function M.draw_tiles(session)
  local surface = game.surfaces[state.canvas_surface_name()]
  local offset = session.canvas_offset
  for key, record in pairs(session.tiles) do
    local raw = record.raw
    session.render_ids.tiles[key] = rendering.draw_sprite{
      sprite = "tile/" .. raw.name,
      target = { offset.x + raw.position.x + 0.5, offset.y + raw.position.y + 0.5 },
      surface = surface,
      players = { session.player_index },
    }
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

function M.clear_session_renders(session)
  destroy_ids(session.render_ids.grid)
  destroy_ids(session.render_ids.entities)
  destroy_ids(session.render_ids.tiles)
  session.render_ids = { grid = nil, entities = {}, tiles = {} }
end

return M
