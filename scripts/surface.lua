local state = require("scripts.state")

local REGION_SPACING = 1024

local M = {}

function M.ensure_canvas_surface()
  local name = state.canvas_surface_name()
  local surface = game.surfaces[name]
  if surface then
    return surface
  end

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

function M.teleport_in(player)
  if state.get_session(player.index) then
    return false
  end
  if player.vehicle or player.controller_type == defines.controllers.remote then
    player.print({"", "Blueprint Editor: exit your vehicle / remote view first."})
    return false
  end

  local pre_edit = {
    surface_name = player.surface.name,
    position = player.position,
    controller_type = player.controller_type,
  }
  local canvas_offset = region_offset(player.index)
  local canvas_surface = M.ensure_canvas_surface()

  state.start_session(player.index, pre_edit, canvas_offset)
  player.teleport(canvas_offset, canvas_surface)
  player.clear_cursor()
  player.cursor_stack.set_stack({ name = "eb-cursor-tool" })
  return true
end

function M.teleport_out(player)
  local session = state.get_session(player.index)
  if not session then
    return false
  end
  player.teleport(session.pre_edit.position, session.pre_edit.surface_name)
  state.clear_session(player.index)
  return true
end

return M
