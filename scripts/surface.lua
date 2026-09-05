local state = require("scripts.state")

-- > 1000 tiles apart (ADR-0001 §5) so two players' canvas regions never
-- visually overlap regardless of blueprint size.
local REGION_SPACING = 1024

local M = {}

function M.ensure_canvas_surface()
  local name = state.canvas_surface_name()
  local surface = game.surfaces[name]
  if surface then
    return surface
  end

  -- width/height only bound the initial chunk the map generator fills before
  -- generate_with_lab_tiles (set below) takes over; every chunk actually
  -- visited on this surface is lab tiles regardless of this value.
  surface = game.create_surface(name, {
    width = 2,
    height = 2,
    autoplace_controls = {},
    default_enable_all_autoplace_controls = false,
    peaceful_mode = true,
    no_enemies_mode = true,
    starting_area = "none",
  })
  surface.generate_with_lab_tiles = true
  surface.always_day = true
  surface.freeze_daytime = true
  surface.show_clouds = false
  return surface
end

local function region_offset(player_index)
  return { x = player_index * REGION_SPACING, y = 0 }
end

function M.teleport_in(player, import_data)
  if state.get_session(player.index) then
    return false
  end
  if player.vehicle or player.controller_type == defines.controllers.remote then
    player.print({"", "Blueprint Editor: exit your vehicle / remote view first."})
    return false
  end
  if not player.cursor_stack then
    player.print({"", "Blueprint Editor: cannot enter the editor from this controller."})
    return false
  end

  local pre_edit = {
    surface_name = player.surface.name,
    position = player.position,
    controller_type = player.controller_type,
  }
  local canvas_offset = region_offset(player.index)
  local canvas_surface = M.ensure_canvas_surface()

  if not player.teleport(canvas_offset, canvas_surface) then
    return false
  end

  if import_data then
    -- Blueprint остаётся у игрока в руке нетронутым -- Phase 1 только читает
    -- его данные, ничего не перекладывает (см. phase-1-plan.md, Задача 2).
  elseif player.clear_cursor() then
    player.cursor_stack.set_stack({ name = "eb-cursor-tool" })
  else
    player.print({"", "Blueprint Editor: could not equip the cursor tool (cursor full) -- entered editor without it."})
  end

  state.start_session(player.index, pre_edit, canvas_offset, import_data)
  return true
end

function M.teleport_out(player)
  local session = state.get_session(player.index)
  if not session then
    return false
  end
  local pre_edit_surface = game.surfaces[session.pre_edit.surface_name]
  if not pre_edit_surface then
    state.clear_session(player.index)
    return false
  end

  player.teleport(session.pre_edit.position, pre_edit_surface)
  player.clear_cursor()
  state.clear_session(player.index)
  return true
end

return M
