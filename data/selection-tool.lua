data:extend({
  {
    type = "selection-tool",
    name = "eb-cursor-tool",
    icon = "__base__/graphics/icons/blueprint.png",
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
    draw_label_for_cursor_render = false,
  },
})
