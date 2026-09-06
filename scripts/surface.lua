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
    character = player.character,
  }
  local canvas_offset = region_offset(player.index)
  local canvas_surface = M.ensure_canvas_surface()

  -- Освобождаем курсор игрока ДО переключения на god-режим и до телепорта --
  -- god-контроллер, судя по всему, имеет собственный, независимый от
  -- character курсор: попытка прочитать/обменять player.cursor_stack ПОСЛЕ
  -- переключения на god видит его пустым, даже если реальный предмет всё ещё
  -- "в руке" character-контроллера (обнаружено playtest'ом -- см.
  -- phase-1-implementation.md; изначально пин был написан после переключения
  -- и терял blueprint-книгу целиком). Держать в руках реальный blueprint
  -- внутри редактора и так мешает (нативный превью-режим размещения путается
  -- под ногами, попытка клика роняет "Невозможно построить в неизведанной
  -- области") -- поэтому чистим курсор независимо от того, войдём ли мы в
  -- god-режим. Обычный (инвентарный) blueprint прячем в скрытый инвентарь
  -- (ADR-0001 §8(b).3) и вернём при выходе. Blueprint из Blueprint Library
  -- (`cursor_record`) восстановить программно нельзя -- `cursor_record`
  -- read-only, API не даёт способа заново прикрепить LuaRecord к курсору --
  -- поэтому просто чистим курсор (то же самое действие, что игрок и так
  -- делает через `Q`); сама запись остаётся целой в библиотеке, сообщение
  -- об этом -- при выходе.
  local pinned_origin = nil
  if import_data then
    if import_data.origin.kind == "cursor" then
      local pinned = game.create_inventory(1)
      local swapped = player.cursor_stack.swap_stack(pinned[1])
      log(string.format("eb debug3: pin swap_stack=%s pinned_stack_name=%s",
        tostring(swapped), tostring(pinned[1].valid_for_read and pinned[1].name)))
      if swapped then
        pinned_origin = { kind = "pinned_stack", inventory = pinned }
        import_data.origin = pinned_origin
      else
        -- swap_stack не сработал -- НЕ уничтожаем pinned (он всё равно пуст,
        -- раз обмен не удался), оставляем blueprint как есть в руке игрока.
        pinned.destroy()
        player.print({"", "Blueprint Editor: could not free up your cursor -- entered editor with the blueprint still in hand."})
      end
    elseif import_data.origin.kind == "cursor_record" then
      player.clear_cursor()
    end
  end

  -- God-режим -- playtest-фикс (не было в исходном docs/phases/phase-1-plan.md,
  -- зафиксировано как отклонение от ADR-0001 §5 "restore exactly" в
  -- docs/phases/phase-1-implementation.md): свободный облёт вместо коллизий
  -- персонажа. Переключаем ДО телепортации, чтобы персонаж остался в реальном
  -- мире, а не переехал на канвас перед отсоединением. Только если вход идёт
  -- из обычного character-контроллера -- иначе нечего сохранять/восстанавливать,
  -- телепортируем как есть в текущем контроллере.
  if pre_edit.character then
    player.set_controller({ type = defines.controllers.god })
  end

  if not player.teleport(canvas_offset, canvas_surface) then
    if pre_edit.character and pre_edit.character.valid then
      player.set_controller({ type = defines.controllers.character, character = pre_edit.character })
    end
    if pinned_origin then
      player.cursor_stack.swap_stack(pinned_origin.inventory[1])
      pinned_origin.inventory.destroy()
      import_data.origin = { kind = "cursor" }
    end
    return false
  end

  if not import_data then
    if player.clear_cursor() then
      player.cursor_stack.set_stack({ name = "eb-cursor-tool" })
    else
      player.print({"", "Blueprint Editor: could not equip the cursor tool (cursor full) -- entered editor without it."})
    end
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

  local character = session.pre_edit.character
  if character then
    if character.valid and character.surface == pre_edit_surface then
      player.set_controller({ type = defines.controllers.character, character = character })
    else
      player.print({"", "Blueprint Editor: could not restore your character -- it may have been destroyed or moved while you were in the editor."})
    end
  end

  local origin = session.origin
  if origin and origin.kind == "pinned_stack" then
    local pinned_stack = origin.inventory[1]
    local swapped = player.cursor_stack and player.cursor_stack.swap_stack(pinned_stack)
    log(string.format("eb debug3: restore swap_stack=%s pinned_still_has=%s",
      tostring(swapped), tostring(pinned_stack.valid_for_read and pinned_stack.name)))
    if pinned_stack.valid_for_read then
      -- swap_stack не сработал или курсор недоступен -- роняем на землю,
      -- не теряем содержимое молча.
      player.surface.spill_item_stack{ position = player.position, stack = pinned_stack, enable_looted = true }
    end
    if pinned_stack.valid_for_read then
      -- Даже spill не сработал (не должно случаться) -- НЕ уничтожаем
      -- инвентарь, чтобы не потерять blueprint; сообщаем и оставляем
      -- как известную проблему для разбора по логу.
      player.print({"", "Blueprint Editor: could not return your blueprint -- it is safely held, please report this bug."})
    else
      origin.inventory.destroy()
    end
  elseif origin and origin.kind == "cursor_record" then
    player.print({"", "Blueprint Editor: your Blueprint Library blueprint stayed in the library -- select it again if you need it in hand."})
  else
    -- "new"-режим: чистим только свой инструмент, не что попало в курсоре.
    local cursor_stack = player.cursor_stack
    if cursor_stack and cursor_stack.valid_for_read and cursor_stack.name == "eb-cursor-tool" then
      cursor_stack.clear()
    end
  end

  state.clear_session(player.index)
  return true
end

return M
