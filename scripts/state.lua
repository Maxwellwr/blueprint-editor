local M = {}

local function default_storage()
  return {
    mod_version = "0.0.1",
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

function M.get_session(player_index)
  return storage.sessions[player_index]
end

function M.start_session(player_index, pre_edit, canvas_offset)
  local session = {
    player_index = player_index,
    pre_edit = pre_edit,
    canvas_offset = canvas_offset,
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
