data:extend({
  {
    type = "selection-tool",
    name = "eb-cursor-tool",
    -- Раньше был blueprint.png -- игрок не мог отличить "держу свой
    -- инструмент редактора" от "держу настоящий чертёж" (найдено playtest'ом
    -- Phase 2). copy-paste-tool.png -- такой же 120x64 mip-набор (64+32+16+8),
    -- что и blueprint.png, existing icon_size=64 продолжает работать без
    -- дополнительных полей.
    icon = "__base__/graphics/icons/copy-paste-tool.png",
    icon_size = 64,
    subgroup = "tool",
    order = "z[eb-cursor-tool]",
    stack_size = 1,
    hidden = true,
    flags = {"only-in-cursor", "not-stackable", "spawnable"},
    select = {
      border_color = {r = 0.3, g = 0.9, b = 0.3},
      cursor_box_type = "copy",
      mode = {"any-entity"},
    },
    alt_select = {
      border_color = {r = 0.9, g = 0.3, b = 0.3},
      cursor_box_type = "not-allowed",
      mode = {"any-entity"},
    },
    -- Даёт удаление и по обычному right-click (не только Shift+левый клик
    -- alt_select) -- найдено playtest'ом Phase 2: правая кнопка была
    -- интуитивным первым выбором для удаления, но reverse_select не был
    -- определён, и Factorio просто ничего не делала. Те же параметры, что у
    -- alt_select -- оба маршрута ведут в один и тот же обработчик удаления
    -- (control.lua регистрирует on_player_reverse_selected_area на ту же
    -- функцию, что и on_player_alt_selected_area).
    reverse_select = {
      border_color = {r = 0.9, g = 0.3, b = 0.3},
      cursor_box_type = "not-allowed",
      mode = {"any-entity"},
    },
    draw_label_for_cursor_render = false,
  },
})
