data:extend({
  {
    type = "custom-input",
    name = "eb-toggle-editor",
    key_sequence = "CONTROL + SHIFT + K",
    consuming = "none",
  },
  {
    type = "custom-input",
    name = "eb-rotate",
    key_sequence = "R",
    consuming = "none",
  },
  {
    type = "custom-input",
    name = "eb-delete",
    key_sequence = "DELETE",
    consuming = "none",
  },
  {
    type = "custom-input",
    name = "eb-pick-entity",
    key_sequence = "Q",
    consuming = "none",
  },
  {
    type = "custom-input",
    name = "eb-cycle-palette-next",
    -- Найдено playtest'ом Phase 2: "bracketright"/"bracketleft" -- не
    -- существующие имена клавиш, список валидных проверен в реальных файлах
    -- игры (doc-html/prototype-api.json, key_sequence) -- правильно
    -- LEFTBRACKET/RIGHTBRACKET (капсом, без дефиса). Factorio не падает на
    -- невалидном имени при загрузке data-стадии, просто оставляет биндинг
    -- неназначенным -- отсюда молчаливая нерабочая клавиша без единой строки
    -- в логе.
    key_sequence = "RIGHTBRACKET",
    consuming = "none",
  },
  {
    type = "custom-input",
    name = "eb-cycle-palette-prev",
    key_sequence = "LEFTBRACKET",
    consuming = "none",
  },
})
