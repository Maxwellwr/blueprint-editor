local M = {}

local function default_storage()
  return {
    mod_version = script.active_mods["blueprint-editor"],
    canvas_surface_name = "eb-canvas",
    sessions = {},
  }
end

function M.init()
  if storage.mod_version == nil then
    for k, v in pairs(default_storage()) do
      storage[k] = v
    end
  end
end

function M.canvas_surface_name()
  return storage.canvas_surface_name
end

function M.get_mod_version()
  return storage.mod_version
end

function M.set_mod_version(version)
  storage.mod_version = version
end

function M.get_session(player_index)
  return storage.sessions[player_index]
end

function M.new_render_ids()
  return { grid = nil, entities = {}, tiles = {} }
end

function M.start_session(player_index, pre_edit, canvas_offset, import_data)
  local session = {
    player_index = player_index,
    pre_edit = pre_edit,
    canvas_offset = canvas_offset,
    mode = import_data and "edit" or "new",
    origin = import_data and import_data.origin or nil,
    next_internal_id = (import_data and import_data.next_internal_id) or 1,
    entities = (import_data and import_data.entities) or {},
    tiles = (import_data and import_data.tiles) or {},
    blueprint_center = (import_data and import_data.blueprint_center) or { x = 0, y = 0 },
    render_ids = M.new_render_ids(),
    label = import_data and import_data.label or nil,
    icons = import_data and import_data.icons or nil,
    blueprint_snap = import_data and import_data.blueprint_snap or nil,
  }
  storage.sessions[player_index] = session
  return session
end

function M.clear_session(player_index)
  storage.sessions[player_index] = nil
end

function M.each_session()
  return pairs(storage.sessions)
end

return M
