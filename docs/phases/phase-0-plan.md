# Phase 0 — Scaffold + empty canvas surface — план

- Ветка: `phase-0-scaffold`
- Базовая версия перед стартом: `info.json` отсутствует (проект — пустой scaffold), версия мода на старте фазы — `0.0.1`, по завершении фазы — `0.1.0` (`docs/sdlc.md`, раздел «Версионирование»).
- Спека: [`docs/adr/0001-baseline-architecture.md`](../adr/0001-baseline-architecture.md) (разделы 2–5), [`docs/roadmap.md`](../roadmap.md) (описание Phase 0).

## Область фазы

Из `docs/roadmap.md`: `info.json`, инициализация `state.lua`, `surface.lua` (lab-tile surface + телепорт in/out), один custom-input `eb-toggle-editor`. Два спайка: поведение `generate_with_lab_tiles`, поведение plain-click с `selection-tool`.

**Явно вне области Phase 0** (подтверждено роадмапом): `rendering.lua` (сетка/рендер — Phase 1), `input.lua` как полноценный модуль обработки кликов (Phase 2), `catalog.lua`/`palette_gui.lua` (Phase 5), любые custom-input кроме `eb-toggle-editor` (`eb-rotate`/`eb-flip`/`eb-delete`/`eb-cancel`/`eb-cycle-palette-*`/`eb-pick-entity` появляются в фазах, где реализуется их функциональность). `EntityRecord`, `Session.entities`/`tiles`/`render_ids` — не нужны, пока нет сущностей на канвасе; `Session` в Phase 0 хранит только то, что нужно для телепорта туда-обратно.

## Global Constraints

- `factorio_version = "2.0"`, зависимость `"base >= 2.0"`, Space Age — опциональная (`"? space-age"`), ADR-0001 §3.
- `storage` — только через accessors `scripts/state.lua`, никто другой не трогает `storage` напрямую (ADR-0001 §4, `docs/sdlc.md`).
- Миграции — только аддитивные, `scripts/migrations.lua` заводится с первой фазы, даже если список шагов пуст (`docs/sdlc.md`).
- Разложение файлов — строго по `docs/adr/0001-baseline-architecture.md` §3 (Project Layout).
- Для API-зависимого кода (всё, что трогает `storage`, `LuaSurface`, события) — automated-тестов нет; верификация через dev-loop + ручной playtest-чеклист (`docs/sdlc.md`, раздел «Тестирование»). Pure-logic TDD (`busted`) в Phase 0 не требуется — весь код фазы зависит от Factorio API.

## Файлы

| Файл | Назначение |
|---|---|
| `info.json` | Метаданные мода, версия, зависимости |
| `data.lua` | Точка входа data-стадии, требует `data/*` |
| `data/custom-input.lua` | Прототип `eb-toggle-editor` |
| `data/selection-tool.lua` | Прототип `eb-cursor-tool` (нужен уже в Phase 0 для спайка 2) |
| `control.lua` | Bootstrap: `require` модулей `scripts/*`, регистрация событий (`on_init`, `on_configuration_changed`, `on_load`, custom-input, спайковый `on_player_selected_area`) |
| `scripts/state.lua` | Схема `storage`, session-accessors для Phase 0 (без `entities`/`tiles`) |
| `scripts/migrations.lua` | Таблица шагов миграций (пуста в Phase 0), `on_configuration_changed` entry point |
| `scripts/surface.lua` | `ensure_canvas_surface`, `teleport_in`, `teleport_out` |

## Задачи

### Задача 1 — `info.json`

**Файлы:** создать `info.json`.

- [ ] Создать `info.json`:

```json
{
  "name": "blueprint-editor",
  "version": "0.0.1",
  "title": "Blueprint Editor",
  "author": "mmaslich",
  "description": "Edit a blueprint directly as data: add, remove, move and rotate entities/tiles without building them for real.",
  "factorio_version": "2.0",
  "dependencies": [
    "base >= 2.0",
    "? space-age"
  ]
}
```

- [ ] Проверить, что версия `0.0.1` — рабочая версия на время фазы; бамп до `0.1.0` — отдельная задача 8 (Definition of Done), не сейчас.
- [ ] Commit: `git add info.json && git commit -m "chore: add mod scaffold info.json"`.

### Задача 2 — data-стадия: `eb-toggle-editor` и `eb-cursor-tool`

**Файлы:** создать `data.lua`, `data/custom-input.lua`, `data/selection-tool.lua`.

**Обоснование `eb-cursor-tool` уже в Phase 0**: спайк 2 («plain click с selection-tool всё ещё стреляет `on_player_selected_area`») требует реального selection-tool предмета в руке игрока — без него спайк невозможно проверить в игре. Полноценная обработка клика (`input.lua`, `canvas.lua`-мутации) остаётся Phase 2; в Phase 0 предмет только выдаётся при входе в редактор и используется для однократной ручной проверки.

- [ ] `data/custom-input.lua`:

```lua
data:extend({
  {
    type = "custom-input",
    name = "eb-toggle-editor",
    key_sequence = "CONTROL + SHIFT + B",
    consuming = "none",
  },
})
```

- [ ] `data/selection-tool.lua`:

```lua
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
    selection_color = {r = 0.3, g = 0.9, b = 0.3},
    alt_selection_color = {r = 0.9, g = 0.3, b = 0.3},
    selection_mode = {"any-entity"},
    alt_selection_mode = {"any-entity"},
    selection_cursor_box_type = "copy",
    alt_selection_cursor_box_type = "not-allowed",
    draw_label_for_cursor_render = false,
  },
})
```

- [ ] `data.lua`:

```lua
require("data.custom-input")
require("data.selection-tool")
```

- [ ] Проверка: нет автоматического теста (data-стадия — чистый Factorio API); проверяется вместе с задачей 6 при полном запуске игры (прототипы валидны, если игра стартует без ошибок загрузки данных).
- [ ] Commit: `git add data.lua data/ && git commit -m "feat: add eb-toggle-editor input and eb-cursor-tool selection tool prototypes"`.

### Задача 3 — `scripts/state.lua`

**Файлы:** создать `scripts/state.lua`.

**Интерфейс, которым будут пользоваться задачи 5–6:**
- `state.init()` — инициализация `storage` в `on_init`/`on_configuration_changed`, идемпотентна.
- `state.canvas_surface_name() -> string`
- `state.get_session(player_index) -> Session|nil`
- `state.start_session(player_index, pre_edit, canvas_offset) -> Session`
- `state.clear_session(player_index)`
- `state.each_session() -> iterator` (для очистки «осиротевших» сессий в `on_load`, задача 6)

`Session` в Phase 0 — минимальная форма, без `entities`/`tiles`/`render_ids` (их вводят Phase 1–2 как аддитивные поля, ADR-0001 §4):

```lua
Session = {
  player_index,
  pre_edit = { surface_name, position, controller_type },
  canvas_offset = { x = ..., y = ... },
}
```

- [ ] Написать `scripts/state.lua`:

```lua
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
```

- [ ] Никакого прямого обращения к `storage` за пределами этого файла — проверяется в задаче 9 (`/code-review`), но держать в уме уже сейчас при написании `surface.lua`/`control.lua`.
- [ ] Commit: `git add scripts/state.lua && git commit -m "feat: add storage schema and session accessors for phase 0"`.

### Задача 4 — `scripts/migrations.lua`

**Файлы:** создать `scripts/migrations.lua`.

Заводится с первой фазы по правилу `docs/sdlc.md` («миграции только аддитивные», обязательны с самого начала), даже если сейчас список шагов пуст — мигрировать не от чего, `0.0.1` первая версия.

- [ ] Написать `scripts/migrations.lua`:

```lua
local M = {}

-- Упорядоченный список {version, fn}, применяется в on_configuration_changed,
-- если storage.mod_version меньше version шага. Пуст в Phase 0 -- мигрировать
-- ещё не от чего. Новые шаги только добавляются в конец, старые не переписываются
-- и не удаляются (docs/sdlc.md, "Миграции только аддитивные").
M.steps = {}

function M.run()
  for _, step in ipairs(M.steps) do
    if storage.mod_version ~= step.version then
      step.fn()
      storage.mod_version = step.version
    end
  end
end

return M
```

- [ ] Commit: `git add scripts/migrations.lua && git commit -m "feat: add migrations entry point scaffold"`.

### Задача 5 — `scripts/surface.lua`

**Файлы:** создать `scripts/surface.lua`.

**Интерфейс:**
- `surface.ensure_canvas_surface() -> LuaSurface` — создаёт при первом вызове, идемпотентна.
- `surface.teleport_in(player) -> boolean` — `false` и сообщение игроку, если вход отклонён (в машине/удалённый обзор).
- `surface.teleport_out(player)` — восстанавливает `pre_edit`, очищает сессию.

**API-факт, подтверждённый перед написанием кода (см. также `phase-0-implementation.md` после playtest):** `LuaSurface.generate_with_lab_tiles` — read-write `boolean`-свойство самого `LuaSurface` (не поле `MapGenSettings`), выставляется **после** `game.create_surface(...)`: «When set to true, new chunks will be generated with lab tiles, instead of using the surface's map generation settings» (lua-api.factorio.com/latest/classes/LuaSurface.html). Это отличается от того, как ADR-0001 §5 формулирует это упоминание вскользь («`generate_with_lab_tiles = true`» в списке аргументов `create_surface`) — код ниже использует подтверждённую форму (свойство поверхности), расхождение с формулировкой ADR фиксируется как найденный факт в `phase-0-implementation.md`, отдельного ADR не требует (не архитектурное отклонение, а уточнение уже верно предполагавшегося поведения).

- [ ] Написать `scripts/surface.lua`:

```lua
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
```

- [ ] Commit: `git add scripts/surface.lua && git commit -m "feat: add canvas surface lifecycle and teleport in/out"`.

### Задача 6 — `control.lua`: bootstrap, события, спайк-хук

**Файлы:** создать `control.lua`.

Помимо wiring, здесь же временный debug-хендлер для спайка 2 (пункт «плайн-клик с selection-tool»): логирует срабатывание `on_player_selected_area` для `eb-cursor-tool`. Это **не** `scripts/debug.lua` из ADR-0001 §3 (тот появится, когда будет что дампить — реальная сессия с сущностями, начиная с Phase 1/2); здесь — одноразовая проверка гипотезы прямо в `control.lua`, которая либо останется маленьким логом, либо будет удалена/заменена в Phase 2 при появлении `input.lua`.

- [ ] Написать `control.lua`:

```lua
local state = require("scripts.state")
local migrations = require("scripts.migrations")
local surface = require("scripts.surface")

local function on_init()
  state.init()
  surface.ensure_canvas_surface()
end

local function on_configuration_changed()
  state.init()
  migrations.run()
  surface.ensure_canvas_surface()
end

local function on_load()
  -- Сессии не переживают save/reload осмысленно (ADR-0001 §4, "Known MVP
  -- limitation"): если игрок сохранённой сессии сейчас не на канвас-поверхности,
  -- считаем редактор отменённым и выкидываем сессию, а не пытаемся её восстановить.
  for player_index in state.each_session() do
    local player = game.get_player(player_index)
    if not player or player.surface.name ~= state.canvas_surface_name() then
      state.clear_session(player_index)
    end
  end
end

local function on_toggle_editor(event)
  local player = game.get_player(event.player_index)
  if state.get_session(player.index) then
    surface.teleport_out(player)
  else
    surface.teleport_in(player)
  end
end

-- Спайк: подтвердить, что plain click (без drag) с equipped selection-tool
-- всё ещё стреляет on_player_selected_area с маленькой area (ADR-0001 §5,
-- §2 "Unverified"). Временный лог, результат фиксируется в
-- docs/phases/phase-0-implementation.md; полноценная обработка -- input.lua, Phase 2.
local function on_selected_area(event)
  if event.item == "eb-cursor-tool" then
    log(string.format(
      "eb spike: on_player_selected_area fired, area=%s, entities=%d",
      serpent.line(event.area), #event.entities
    ))
  end
end

script.on_init(on_init)
script.on_configuration_changed(on_configuration_changed)
script.on_load(on_load)
script.on_event("eb-toggle-editor", on_toggle_editor)
script.on_event(defines.events.on_player_selected_area, on_selected_area)
```

- [ ] Commit: `git add control.lua && git commit -m "feat: wire control.lua bootstrap, toggle-editor input and selection-tool spike hook"`.

### Задача 7 — Dev-деплой и ручной playtest (оба спайка + основной сценарий)

Нет автотестов для этого кода (Factorio API), верификация — только через dev-loop и ручной прогон (`docs/sdlc.md`, раздел «Тестирование»).

- [ ] Создать symlink мода в `%APPDATA%\Factorio\mods\blueprint-editor` на рабочую копию репозитория (PowerShell: `New-Item -ItemType SymbolicLink -Path "$env:APPDATA\Factorio\mods\blueprint-editor" -Target "<путь до репозитория>"`).
- [ ] Полный рестарт игры (обязателен — прототипы `data.lua` грузятся один раз при старте), создать новый save.
- [ ] Playtest-чеклист (переносится в `phase-0-implementation.md` с результатами):
  - [ ] Мод грузится без ошибок (нет крашей в лог/консоли при старте и при создании мира).
  - [ ] `Ctrl+Shift+B` телепортирует игрока на поверхность `eb-canvas`.
  - [ ] Поверхность `eb-canvas` — лаборторные тайлы (lab tiles), плоская, без ресурсов и врагов (визуальная проверка спайка 1 — `generate_with_lab_tiles`).
  - [ ] После входа в редактор у игрока в курсоре — `eb-cursor-tool`.
  - [ ] Одиночный клик (без зажатия/протяжки) курсором вызывает лог `eb spike: on_player_selected_area fired...` (проверка спайка 2). Если не срабатывает — задокументировать как найденный факт, откатиться на fallback из ADR-0001 §5 (`custom-input` + `cursor_position`) как решение, принятое по ходу фазы.
  - [ ] Повторный `Ctrl+Shift+B` возвращает игрока ровно на исходную позицию/поверхность/контроллер.
  - [ ] Попытка входа в редактор, сидя в машине или в remote view — отклоняется с сообщением игроку, телепорта не происходит.
  - [ ] Save-reload (закрыть/открыть сохранение) находясь внутри редактора: после `on_load` сессия либо восстанавливается корректно, либо (ожидаемо по MVP-ограничению) тихо сбрасывается без ошибок в логе.
  - [ ] Два разных игрока (или два запуска входа под разными `player_index` в MP/тестовом сценарии) получают непересекающиеся регионы на `eb-canvas` (координаты офсета отличаются на `REGION_SPACING`).
- [ ] Зафиксировать результаты (включая расхождения с ожиданиями) как черновик для `phase-0-implementation.md` (задача 8).

### Задача 8 — Закрытие фазы: документация, версия, DoD

**Definition of Done фазы** (`docs/sdlc.md`) — выполнить по порядку:

- [ ] Прогнать `/code-review` на диффе ветки `phase-0-scaffold`, закрыть найденные замечания.
- [ ] Создать `docs/phases/phase-0-implementation.md` по шаблону `docs/phases/TEMPLATE-implementation.md`: что сделано, решения по ходу (в т.ч. уточнение про `generate_with_lab_tiles` как свойство `LuaSurface`, задача 5), результат playtest-чеклиста (задача 7), известные ограничения (курсор-инструмент не «залипает» принудительно — полноценный lock через `on_player_cursor_stack_changed` только в Phase 2).
- [ ] Обновить `docs/roadmap.md`: отметить Phase 0 завершённой (дата, версия).
- [ ] Обновить `info.json.version` → `0.1.0`.
- [ ] Обновить `CHANGELOG.md` (новая секция `0.1.0`).
- [ ] Миграция в `scripts/migrations.lua` — не требуется (схема `storage` не менялась после первой версии в рамках самой фазы).
- [ ] Commit: `git add docs/roadmap.md docs/phases/phase-0-implementation.md CHANGELOG.md info.json && git commit -m "docs: close out phase 0"`.
- [ ] Смержить `phase-0-scaffold` в `main` (после ручного подтверждения пользователем — мерж не выполняется автоматически).

## Спайки (ADR-0001 §2)

- [ ] **`generate_with_lab_tiles`** — API-факт подтверждён документацией (задача 5: read-write свойство `LuaSurface`, не поле `MapGenSettings`); фактическое визуальное поведение в игре подтверждается playtest (задача 7).
- [ ] **Plain click + selection-tool → `on_player_selected_area`** — не подтверждаемо по документации без обращения к реальному ранлупу, чисто игровой спайк; проверяется исключительно playtest (задача 7). Fallback при провале описан в ADR-0001 §5 и в чеклисте задачи 7.

## Открытые вопросы

- Точный `key_sequence` для `eb-toggle-editor` (`CONTROL + SHIFT + B`) — не проверялся на конфликты с другими модами/базовой игрой; при playtest проверить, что комбинация свободна, иначе сменить в задаче 2.
- Поведение `on_load`-очистки «осиротевших» сессий (задача 6) реализовано по консервативной трактовке ADR-0001 §4; если playtest покажет иное ожидаемое поведение — зафиксировать как решение по ходу в `phase-0-implementation.md`, не как отклонение от архитектуры.
