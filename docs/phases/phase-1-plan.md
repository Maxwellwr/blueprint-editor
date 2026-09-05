# Phase 1 — Read-only render of an existing blueprint — план

- Ветка: `phase-1-render`
- Базовая версия перед стартом: `info.json` `0.1.0`, по завершении фазы — `0.2.0` (`docs/sdlc.md`, раздел «Версионирование»).
- Спека: [`docs/adr/0001-baseline-architecture.md`](../adr/0001-baseline-architecture.md) (разделы 2, 4, 6 частично, 8(b) пп. 1–2, 4), [`docs/roadmap.md`](../roadmap.md) (описание Phase 1).

## Область фазы

Из `docs/roadmap.md`: `blueprint_io.import_from_stack` (read-only), `rendering.lua` (сетка/сущности/тайлы). Спайк: перенос blueprint из Blueprint Library через `cursor_stack` (ADR-0001 §2, §8(b).7).

Сценарий фазы: игрок держит в курсоре валидный, настроенный blueprint и жмёт `eb-toggle-editor` — мод копирует его содержимое как данные (ничего не двигая физически из курсора игрока), телепортирует на `eb-canvas` и рисует сетку + иконки сущностей/тайлов на своих позициях. Повторное нажатие `eb-toggle-editor` возвращает игрока обратно; blueprint как был, так и остаётся у него в руке — фаза read-only, никаких записей в стек не производится.

**Явно вне области Phase 1** (подтверждено роадмапом):
- Любые мутации канваса (`canvas.lua`, place/remove/move/rotate) — Phase 2.
- Полноценная обработка кликов/`input.lua` — Phase 2.
- Provider бухгалтерия проводов (`EntityRecord.wires`, remap ссылок при удалении) — Phase 2 (роадмап явно называет её частью Phase 2: «entity_number/wire bookkeeping»); в Phase 1 `EntityRecord` не хранит `wires` вообще — поле добавится аддитивно, когда появится логика, которая его использует.
- `catalog.lua`/`palette_gui.lua` — Phase 5.
- Экспорт/сохранение (`export_to_entities_array`, `save_new_blueprint`, `save_back_to_stack`) — Phase 4. Из этого следует: исходный blueprint в Phase 1 никуда не «пинится» (не переносится в скрытый инвентарь, ADR-0001 §8(b).3) — он читается на месте, пока лежит в курсоре игрока. Полноценный pinning нужен, только когда появляется риск потери данных при реальном редактировании/сохранении — то есть с Phase 2 (правки) и обязательно к Phase 4 (сохранение). Это сознательное сужение объёма см. «Открытые вопросы».
- Настоящая графика сущностей/анимации — Phase 7 («entity render fidelity pass»). Phase 1 рисует плоские иконки прототипа (`entity/<name>`, `tile/<name>`), не полноценный спрайт в мире.
- Каталог тегов blueprint-книг (`is_blueprint_book`) — не рассматривается, вне сценария (игрок держит одиночный blueprint).

## Global Constraints

- `factorio_version = "2.0"` (ADR-0001 §3) — без изменений в этой фазе.
- `storage` — только через `scripts/state.lua`. Уточнение границы (по факту финального ревью Phase 0): правило касается прямого обращения к глобалу `storage` (`storage.sessions`, `storage.mod_version`, ...) — только `state.lua`. Модуль, уже получивший ссылку на конкретный `Session` через `state.get_session()`/возврат `state.start_session()`, свободно читает и пишет **поля этого объекта** напрямую (`session.entities[id] = ...`) — так делает и сам ADR-0001 §6 в псевдокоде импорта. Это не нарушение инкапсуляции, а обычная работа с уже полученными данными.
- Миграции — только аддитивные (ADR-0001 §4, `docs/sdlc.md`). Схема `Session` меняется только добавлением nil-safe полей; для этой фазы, поскольку сессии Phase 0 теоретически могут пережить границу обновления мода (игрок был на канвасе в момент update), обязателен реальный шаг миграции `0.2.0` — не просто «пусто, мигрировать не от чего», как было в Phase 0.
- Pure-logic TDD (`docs/sdlc.md`, DoD п.6, ADR-0001 §10): любой код без зависимости от Factorio API, принимающий/возвращающий обычные Lua-таблицы, обязан быть покрыт `busted`-тестами, написанными до реализации. В этой фазе такой код впервые появляется — назначение `internal_id` и индексация тайлов в `blueprint_io.build_import_data` (чистая функция, без `storage`/`game`). Правило безусловно про модули «затронутые фазой» — не привязано к тому, что где-то в `docs/sdlc.md` этот же код упомянут как пример «в первую очередь Phase 2» (та фраза — про полноценный remap с проводами при удалении, который остаётся в Phase 2; см. «Открытые вопросы»).
- Preserve-unknown-fields (ADR-0001 §6): `EntityRecord.raw`/`TileRecord.raw` — нетронутая таблица из `get_blueprint_entities()`/`get_blueprint_tiles()`, никаких хардкод-пересборок по списку полей.
- Явный бюджет производительности (`docs/sdlc.md`): рендер сетки — фиксированное число объектов на сессию (не зависит от размера blueprint); рендер сущностей — мягкий порог с логом, если сущностей больше эмпирической оценки для этой фазы (см. Задача 4).
- Для API-зависимого кода — automated-тестов нет; верификация через dev-loop + ручной playtest-чеклист (`docs/sdlc.md`).

## Файлы

| Файл | Назначение |
|---|---|
| `scripts/state.lua` | Изменить: `Session` — новые аддитивные поля (`mode`, `origin`, `next_internal_id`, `entities`, `tiles`, `render_ids`, `label`, `icons`, `blueprint_snap`) |
| `scripts/migrations.lua` | Изменить: первый реальный шаг `0.2.0` — нормализация старых (Phase 0) сессий |
| `scripts/surface.lua` | Изменить: `teleport_in` принимает опциональный `import_data`, не трогает курсор, если он есть |
| `scripts/blueprint_io.lua` | Новый: `import_from_stack` (API-обёртка) + `build_import_data` (чистая логика, TDD) |
| `spec/blueprint_io_spec.lua` | Новый: `busted`-тесты `build_import_data` |
| `.busted` | Новый: конфиг `busted` (`lpath` для `require("scripts.*")` из корня репозитория) |
| `scripts/rendering.lua` | Новый: `draw_grid`, `draw_entities`, `draw_tiles`, `clear_session_renders` |
| `control.lua` | Изменить: `on_toggle_editor` — оркестрация import → teleport_in → render / render-cleanup → teleport_out |

## Задачи

### Задача 1 — `scripts/state.lua` и `scripts/migrations.lua`: расширение схемы `Session`

**Файлы:** изменить `scripts/state.lua`, `scripts/migrations.lua`.

**Текущий `scripts/state.lua`** (после Phase 0, для контекста — редактировать именно этот файл):

```lua
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

- [ ] Заменить `M.start_session` на версию с опциональным 4-м параметром `import_data` (форма `import_data`, если передан: `{ entities, tiles, next_internal_id, label, icons, blueprint_snap, origin }` — эту форму строит `blueprint_io.import_from_stack`, Задача 3):

```lua
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
    render_ids = { grid = nil, entities = {}, tiles = {} },
    label = import_data and import_data.label or nil,
    icons = import_data and import_data.icons or nil,
    blueprint_snap = import_data and import_data.blueprint_snap or nil,
  }
  storage.sessions[player_index] = session
  return session
end
```

- [ ] Остальные функции `state.lua` (`init`, `canvas_surface_name`, `get_mod_version`, `set_mod_version`, `get_session`, `clear_session`, `each_session`) — без изменений.
- [ ] Commit: `git add scripts/state.lua && git commit -m "feat: extend Session schema for blueprint import (entities, tiles, render_ids)"`.

**Текущий `scripts/migrations.lua`** (после Phase 0):

```lua
local state = require("scripts.state")

local M = {}

-- Упорядоченный список {version, fn}, применяется в on_configuration_changed,
-- если storage.mod_version меньше version шага. Пуст в Phase 0 -- мигрировать
-- ещё не от чего. Новые шаги только добавляются в конец, старые не переписываются
-- и не удаляются (docs/sdlc.md, "Миграции только аддитивные").
M.steps = {}

local function parse_version(version)
  local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)$")
  return tonumber(major), tonumber(minor), tonumber(patch)
end

local function version_less_than(a, b)
  local a_major, a_minor, a_patch = parse_version(a)
  local b_major, b_minor, b_patch = parse_version(b)
  if a_major ~= b_major then
    return a_major < b_major
  end
  if a_minor ~= b_minor then
    return a_minor < b_minor
  end
  return a_patch < b_patch
end

function M.run()
  local current = state.get_mod_version()
  for _, step in ipairs(M.steps) do
    if version_less_than(current, step.version) then
      step.fn()
      current = step.version
    end
  end
  state.set_mod_version(current)
end

return M
```

**Почему нужен реальный шаг, а не пустой список как в Phase 0:** сессии не переживают save/reload осмысленно (ADR-0001 §4), но `on_player_joined_game` (Phase 0) сбрасывает только те сессии, чей игрок **не** на `eb-canvas` в момент рестарта. Игрок, оставшийся на канвасе ровно в момент обновления мода 0.1.0→0.2.0, сохранит сессию старой (Phase 0) формы — без `entities`/`tiles`/`render_ids`. Первый же вызов `rendering.clear_session_renders(session)` (Задача 4, вызывается из `control.lua` при выходе) упадёт на `session.render_ids.grid` (`nil.grid`) — тот же класс краша, что был в Phase 0 с `on_load`. Миграция обязана нормализовать форму сессии до того, как это код увидит.

- [ ] Добавить первый шаг в `M.steps` (список остаётся пустым только до этой правки):

```lua
M.steps = {
  {
    version = "0.2.0",
    fn = function()
      for _, session in state.each_session() do
        session.mode = session.mode or "new"
        session.next_internal_id = session.next_internal_id or 1
        session.entities = session.entities or {}
        session.tiles = session.tiles or {}
        session.render_ids = session.render_ids or { grid = nil, entities = {}, tiles = {} }
      end
    end,
  },
}
```

- [ ] Проверить, что `state.each_session()` (уже существует, `return pairs(storage.sessions)`) корректно даёт пары `player_index, session` в `for _, session in state.each_session() do` — да, это тот же `pairs()`, просто с двумя именованными переменными вместо одной, как в `control.lua`.
- [ ] Commit: `git add scripts/migrations.lua && git commit -m "feat: add 0.2.0 migration step normalizing Session shape for blueprint import"`.

### Задача 2 — `scripts/surface.lua`: `teleport_in` принимает `import_data`

**Файлы:** изменить `scripts/surface.lua`.

**Текущий файл** (после Phase 0, для контекста):

```lua
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

function M.teleport_in(player)
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

  if player.clear_cursor() then
    player.cursor_stack.set_stack({ name = "eb-cursor-tool" })
  else
    player.print({"", "Blueprint Editor: could not equip the cursor tool (cursor full) -- entered editor without it."})
  end

  state.start_session(player.index, pre_edit, canvas_offset)
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
```

**Единственное изменение — `teleport_in`.** Когда `import_data` передан (игрок держит валидный blueprint, `blueprint_io.import_from_stack` уже прочитал его на месте — см. Задача 3), курсор **не трогаем вообще**: blueprint остаётся у игрока в руке ровно как был, читаем его данные, но не перекладываем никуда (Phase 1 — read-only, pinning в скрытый инвентарь ADR-0001 §8(b).3 не нужен, пока нечего защищать от потери — см. «Открытые вопросы»). `teleport_out` не меняется — ему нечего возвращать, курсор никогда не трогался.

- [ ] Заменить сигнатуру и тело `teleport_in`:

```lua
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
```

- [ ] `M.ensure_canvas_surface`, `region_offset`, `M.teleport_out` — без изменений (не трогать).
- [ ] Commit: `git add scripts/surface.lua && git commit -m "feat: teleport_in accepts optional import_data, skips cursor tool equip when importing"`.

### Задача 3 — `scripts/blueprint_io.lua` + `busted`-тесты (TDD)

**Файлы:** создать `scripts/blueprint_io.lua`, `spec/blueprint_io_spec.lua`, `.busted`.

**Интерфейс:**
- `blueprint_io.build_import_data(bp_entities, bp_tiles) -> entities, tiles, next_internal_id` — чистая функция, без обращения к `storage`/`game`/любому Factorio API. Принимает и возвращает обычные Lua-таблицы (массивы `BlueprintEntity`/`Tile`, как их отдаёт `get_blueprint_entities()`/`get_blueprint_tiles()`). Назначает монотонный `internal_id`, начиная с 1, каждой сущности (ADR-0001 §6) — `entity_number` из блюпринта используется только для чтения, не переносится как `internal_id`. Индексирует тайлы по ключу `"x,y"` (ADR-0001 §4, форма `Session.tiles`).
- `blueprint_io.import_from_stack(player, cursor_stack) -> import_data | nil` — API-обёртка. `nil`, если в `cursor_stack` не лежит настроенный blueprint (это не ошибка — обычный вход в "new"-режим Phase 0, тихий фолбэк). Иначе — таблица `{ entities, tiles, next_internal_id, label, icons, blueprint_snap, origin }`, которую `state.start_session` (Задача 1) принимает как 4-й параметр.

**Задача 1 — красный тест.** Создать `.busted`:

```lua
return {
  default = {
    lpath = "./?.lua;./?/init.lua",
  },
}
```

Создать `spec/blueprint_io_spec.lua`:

```lua
local blueprint_io = require("scripts.blueprint_io")

describe("blueprint_io.build_import_data", function()
  it("assigns sequential internal_id starting at 1, independent of entity_number", function()
    local entities, _, next_id = blueprint_io.build_import_data({
      { entity_number = 7, name = "iron-chest", position = { x = 0, y = 0 } },
      { entity_number = 12, name = "wooden-chest", position = { x = 1, y = 0 } },
    }, {})
    assert.are.equal(1, entities[1].internal_id)
    assert.are.equal("iron-chest", entities[1].raw.name)
    assert.are.equal(2, entities[2].internal_id)
    assert.are.equal("wooden-chest", entities[2].raw.name)
    assert.is_nil(entities[7])
    assert.is_nil(entities[12])
    assert.are.equal(3, next_id)
  end)

  it("returns empty tables and next_internal_id = 1 for an empty blueprint", function()
    local entities, tiles, next_id = blueprint_io.build_import_data({}, {})
    assert.are.same({}, entities)
    assert.are.same({}, tiles)
    assert.are.equal(1, next_id)
  end)

  it("indexes tiles by an \"x,y\" position key", function()
    local _, tiles = blueprint_io.build_import_data({}, {
      { name = "lab-dark-1", position = { x = -2, y = 3 } },
    })
    assert.is_not_nil(tiles["-2,3"])
    assert.are.equal("lab-dark-1", tiles["-2,3"].raw.name)
  end)

  it("preserves the raw entity table untouched (preserve-unknown-fields)", function()
    local bp_entity = {
      entity_number = 1,
      name = "assembling-machine-2",
      position = { x = 0, y = 0 },
      recipe = "iron-gear-wheel",
      request_filters = { { index = 1, name = "iron-plate", count = 100 } },
    }
    local entities = blueprint_io.build_import_data({ bp_entity }, {})
    assert.are.equal(bp_entity, entities[1].raw)
  end)
end)
```

- [ ] Запустить `busted` из корня репозитория. Ожидаемо: FAIL (`module 'scripts.blueprint_io' not found`) — модуля ещё нет. Если `busted` не установлен в этом окружении — установить (`luarocks install busted`); если `luarocks`/Lua недоступны в песочнице вовсе, это блокер инфраструктуры — сообщить статусом `BLOCKED`, не имитировать TDD без реального прогона.

**Задача 2 — минимальная реализация:**

```lua
local M = {}

-- Чистая логика без Factorio API (ADR-0001 §6): назначает монотонный
-- internal_id каждой сущности блюпринта (не переиспользуя entity_number)
-- и индексирует тайлы по "x,y". Обязательный TDD (docs/sdlc.md, DoD п.6) --
-- тесты в spec/blueprint_io_spec.lua написаны до этой реализации.
function M.build_import_data(bp_entities, bp_tiles)
  local entities = {}
  local next_internal_id = 1
  for _, bp_entity in ipairs(bp_entities) do
    local internal_id = next_internal_id
    next_internal_id = next_internal_id + 1
    entities[internal_id] = { internal_id = internal_id, raw = bp_entity }
  end

  local tiles = {}
  for _, bp_tile in ipairs(bp_tiles) do
    local key = bp_tile.position.x .. "," .. bp_tile.position.y
    tiles[key] = { raw = bp_tile }
  end

  return entities, tiles, next_internal_id
end

-- API-факт (проверено lua-api.factorio.com перед написанием кода): свойство
-- называется `preview_icons`, а не `blueprint_icons` (последнее нигде не
-- существует в текущей версии API -- расхождение с формулировкой ADR-0001
-- §8(b).2, зафиксировано как найденный факт в phase-1-implementation.md).
function M.import_from_stack(player, cursor_stack)
  if not (cursor_stack and cursor_stack.valid_for_read and cursor_stack.is_blueprint and cursor_stack.is_blueprint_setup()) then
    return nil
  end

  local bp_entities = cursor_stack.get_blueprint_entities() or {}
  local bp_tiles = cursor_stack.get_blueprint_tiles() or {}
  local entities, tiles, next_internal_id = M.build_import_data(bp_entities, bp_tiles)

  return {
    entities = entities,
    tiles = tiles,
    next_internal_id = next_internal_id,
    label = cursor_stack.label,
    icons = cursor_stack.preview_icons,
    blueprint_snap = {
      snap_to_grid = cursor_stack.blueprint_snap_to_grid,
      absolute_snapping = cursor_stack.blueprint_absolute_snapping,
      position_relative_to_grid = cursor_stack.blueprint_position_relative_to_grid,
    },
    origin = { kind = "cursor" },
  }
end

return M
```

- [ ] Запустить `busted` снова. Ожидаемо: 4/4 PASS.
- [ ] `import_from_stack` не покрывается `busted` (зависит от `LuaItemStack`) — проверяется вместе с Задачей 6 при реальном playtest.
- [ ] Commit: `git add scripts/blueprint_io.lua spec/blueprint_io_spec.lua .busted && git commit -m "feat: add blueprint_io.import_from_stack with TDD-covered internal_id assignment"`.

### Задача 4 — `scripts/rendering.lua`: сетка, сущности, тайлы

**Файлы:** создать `scripts/rendering.lua`.

**Интерфейс:**
- `rendering_module.draw_grid(session)` — рисует ограниченную сетку 128×128 тайлов вокруг `session.canvas_offset` (ADR-0001 §5), сохраняет id в `session.render_ids.grid`.
- `rendering_module.draw_entities(session)` — по одной иконке-спрайту на сущность в `session.entities`, сохраняет id в `session.render_ids.entities[internal_id]`.
- `rendering_module.draw_tiles(session)` — по одной иконке-спрайту на тайл в `session.tiles`, сохраняет id в `session.render_ids.tiles[key]`.
- `rendering_module.clear_session_renders(session)` — уничтожает все id из `session.render_ids`, обнуляет структуру.

Модуль называется `rendering.lua`, но само имя `rendering` в Lua уже занято глобалом Factorio (`LuaRendering` API) — **не** называть локальную переменную модуля `rendering` при `require` в других файлах (использовать, например, `local render = require("scripts.rendering")`), иначе она заслонит глобал внутри файла, где сделан `require`. Внутри самого `scripts/rendering.lua` конфликта нет — файл возвращает таблицу `M`, не связывая идентификатор `rendering`, поэтому глобал `rendering.draw_sprite`/`rendering.draw_line`/`rendering.destroy` остаётся доступен как обычно.

**Рендер сущностей — плоские иконки прототипа, не полноценная графика.** `sprite = "entity/" .. raw.name` — тот же принцип динамического sprite-пути, что уже используется для `item/<name>` в ADR-0001 §7 (палитра). Полноценная графика/анимация — Phase 7 («entity render fidelity pass», `docs/roadmap.md`), сознательно не в этой фазе. Подтвердить путём playtest (Задача 6): валидные ли иконки рисуются для обычных сущностей блюпринта.

```lua
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
  for _, id in pairs(ids) do
    if rendering.is_valid(id) then
      rendering.destroy(id)
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
```

- [ ] Не покрывается `busted` — весь модуль зависит от `LuaRendering`/`game.surfaces`. Верификация — Задача 6 (playtest).
- [ ] Commit: `git add scripts/rendering.lua && git commit -m "feat: add rendering.lua for grid/entity/tile draw and cleanup"`.

### Задача 5 — `control.lua`: оркестрация import → teleport_in → render

**Файлы:** изменить `control.lua`.

**Текущий файл** (после Phase 0, для контекста):

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
  -- Пусто намеренно: `game` недоступен внутри on_load, а запись в `storage`
  -- запрещена (lua-api.factorio.com/latest/auxiliary/data-lifecycle.html).
  -- Очистка осиротевших сессий (ADR-0001 §4, "Known MVP limitation") перенесена
  -- в on_player_joined_game, который срабатывает после on_load, когда `game`
  -- уже доступен и запись в `storage` разрешена.
end

local function on_player_joined_game()
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
-- §2 "Unverified"). Временный лог, результат зафиксирован как подтверждённый
-- факт в docs/phases/phase-0-implementation.md.
-- TODO(Phase 2): удалить этот хендлер, заменить полноценной обработкой в input.lua.
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
script.on_event(defines.events.on_player_joined_game, on_player_joined_game)
script.on_event("eb-toggle-editor", on_toggle_editor)
script.on_event(defines.events.on_player_selected_area, on_selected_area)
```

**Изменения:** добавить `require` для `blueprint_io` и `rendering` (как `render`, см. Задача 4 — не заслонять глобал `rendering`). Переписать только `on_toggle_editor`. Всё остальное (`on_init`, `on_configuration_changed`, `on_load`, `on_player_joined_game`, спайковый `on_selected_area`, регистрации событий) — без изменений, не трогать.

- [ ] Добавить в начало файла:

```lua
local blueprint_io = require("scripts.blueprint_io")
local render = require("scripts.rendering")
```

- [ ] Заменить `on_toggle_editor`:

```lua
local function on_toggle_editor(event)
  local player = game.get_player(event.player_index)
  local session = state.get_session(player.index)
  if session then
    render.clear_session_renders(session)
    surface.teleport_out(player)
  else
    local import_data = blueprint_io.import_from_stack(player, player.cursor_stack)
    if surface.teleport_in(player, import_data) then
      local new_session = state.get_session(player.index)
      render.draw_grid(new_session)
      if import_data then
        render.draw_entities(new_session)
        render.draw_tiles(new_session)
      end
    end
  end
end
```

- [ ] Проверить порядок при выходе: `render.clear_session_renders(session)` вызывается **до** `surface.teleport_out(player)` (который стирает сессию из `storage`) — иначе `session.render_ids` будет уже недостижим. Не менять порядок.
- [ ] Commit: `git add control.lua && git commit -m "feat: wire blueprint import and rendering into toggle-editor flow"`.

### Задача 6 — Dev-деплой и ручной playtest (основной сценарий + спайк Blueprint Library)

Нет автотестов для этого кода (Factorio API), верификация — только через dev-loop и ручной прогон (`docs/sdlc.md`, раздел «Тестирование»). Symlink мода уже существует с Phase 0 (`%APPDATA%\Factorio\mods\blueprint-editor`) — новый не нужен. `control.lua`/`scripts/*` подхватываются save-reload'ом, `data.lua` в этой фазе не менялся — полный рестарт не обязателен, но сделать его один раз для чистоты (новая версия мода в списке).

- [ ] Обновить `info.json.version` → `0.2.0` временно для теста, либо дождаться Задачи 7 (миграция сработает и на dev-версии — `on_configuration_changed` триггерится любым изменением `info.json.version`, включая dev-итерации).
- [ ] Playtest-чеклист «new»-режим (регрессия Phase 0):
  - [ ] `Ctrl+Shift+K` с пустым курсором — тот же сценарий, что в Phase 0 (телепорт, `eb-cursor-tool` в руке, сетка Phase 0 отсутствовала — теперь должна появиться: сетка рисуется всегда, даже в "new"-режиме).
  - [ ] Повторный `Ctrl+Shift+K` — выход, без ошибок в логе.
- [ ] Playtest-чеклист «edit»-режим (основной сценарий фазы):
  - [ ] Построить в обычном мире небольшую тестовую конструкцию (5–10 разнотипных сущностей: сундук, сборочная машина с рецептом, несколько поясов/труб, один повёрнутый). Захватить как blueprint обычным способом (не через Blueprint Library).
  - [ ] Взять blueprint в курсор, нажать `Ctrl+Shift+K`.
  - [ ] Игрок телепортируется на `eb-canvas`; blueprint остаётся у него в руке (не пропадает, не заменяется на `eb-cursor-tool`).
  - [ ] На канвасе видна сетка и иконки всех сущностей на позициях, соответствующих исходной раскладке (относительные расстояния и повороты совпадают с оригиналом).
  - [ ] Тайлы (если были в захваченной области) отрисованы иконками на правильных позициях.
  - [ ] Повторный `Ctrl+Shift+K` — игрок возвращается на исходную позицию; blueprint как был у него в руке (тот же `label`, то же число сущностей через `/c game.player.print(game.player.cursor_stack.get_blueprint_entity_count())` в консоли, если нужна ручная проверка), рендер-объекты не остаются висеть на канвасе (проверить `/c game.player.print(#rendering.get_all_ids())` до входа и после выхода — должно совпадать).
  - [ ] Save-reload находясь внутри "edit"-сессии — не крашит (проверка миграции/нормализации из Задачи 1, хотя реальный сценарий требует апгрейда версии мода между сохранением и загрузкой — при отсутствии такого сценария в рамках одной dev-итерации проверить хотя бы штатный `on_load` не ломается на новых полях сессии).
- [ ] Спайк: перенос из Blueprint Library (ADR-0001 §2, §8(b).7):
  - [ ] Открыть Blueprint Library (`Shift+B` или аналог), перетащить существующий blueprint прямо на курсор (не через промежуточный инвентарь).
  - [ ] Нажать `Ctrl+Shift+K` — проверить, что `is_blueprint`/`is_blueprint_setup()`/`get_blueprint_entities()` отрабатывают нормально (рендер появляется корректно, как и для обычного blueprint).
  - [ ] Если перенос ломается (сущности не читаются, ошибка в логе) — задокументировать как найденный факт в `phase-1-implementation.md`: известное ограничение ADR-0001 подтвердилось даже для чистого чтения (не только переноса между инвентарями); зафиксировать workaround «сначала перетащить в инвентарь/блокнот», без обходного кода в MVP (ADR-0001 §8(b).7 уже допускает этот исход).
- [ ] Зафиксировать результаты (включая расхождения с ожиданиями) как черновик для `phase-1-implementation.md` (Задача 7).

### Задача 7 — Закрытие фазы: документация, версия, DoD

**Definition of Done фазы** (`docs/sdlc.md`) — выполнить по порядку:

- [ ] Прогнать `/code-review` на диффе ветки `phase-1-render`, закрыть найденные замечания.
- [ ] Создать `docs/phases/phase-1-implementation.md` по шаблону `docs/phases/TEMPLATE-implementation.md`: что сделано, решения по ходу (найденный факт `preview_icons` вместо `blueprint_icons`, решение не пинить исходный blueprint в Phase 1, решение завести TDD раньше ожидаемого в `docs/sdlc.md` примера, итог спайка Blueprint Library, фактический замер бюджета рендера), результат playtest-чеклиста (Задача 6), известные ограничения (курсор с blueprint не защищён от ручных действий игрока во время read-only сессии — не risk потери данных, пока нет записи; полноценный pinning — Phase 2+).
- [ ] Обновить `docs/roadmap.md`: отметить Phase 1 завершённой (дата, версия).
- [ ] Обновить `info.json.version` → `0.2.0`.
- [ ] Обновить `CHANGELOG.md` (новая секция `0.2.0`).
- [ ] Миграция в `scripts/migrations.lua` — уже добавлена в Задаче 1 (шаг `0.2.0`), доп. действий не требуется.
- [ ] `busted spec/` зелёный (Задача 3) — приложить итог прогона в implementation-doc.
- [ ] Commit: `git add docs/roadmap.md docs/phases/phase-1-implementation.md CHANGELOG.md info.json && git commit -m "docs: close out phase 1"`.
- [ ] Смержить `phase-1-render` в `main` (после ручного подтверждения пользователем — мерж не выполняется автоматически).

## Спайки (ADR-0001 §2, §8(b).7)

- [ ] **Blueprint Library → `cursor_stack`** — не проверяемо по документации, чисто игровой спайк; проверяется исключительно playtest (Задача 6). Поскольку Phase 1 только читает стек на месте (не переносит его никуда), риск может оказаться уже неактуальным по сравнению с формулировкой ADR (та описывает провал именно *переноса/transfer* через `cursor_stack`) — фактический результат фиксируется как найденный факт независимо от исхода.

## Открытые вопросы

- **Почему TDD уже в Phase 1, хотя `docs/sdlc.md` называет Phase 2 первым примером.** `docs/sdlc.md`, раздел «Тестирование», говорит: «обязательный TDD... начиная с той фазы, где такой код впервые появляется (в первую очередь Phase 2 для remap...)» — это иллюстративная оценка, а не исключение из правила DoD п.6, которое сформулировано безусловно («для модулей... затронутых фазой»). `blueprint_io.build_import_data` (назначение `internal_id`, индексация тайлов) — чистая логика без Factorio API, появляющаяся уже в Phase 1 для импорта. Полноценный remap с проводами (`EntityRecord.wires`, переброс ссылок при удалении) — по-прежнему Phase 2, как и в роадмапе; название «Phase 2 для remap» в `docs/sdlc.md`, по всей видимости, имело в виду именно эту (более сложную) часть, а не назначение id как таковое.
- **Почему `EntityRecord` в Phase 1 без поля `wires`.** ADR-0001 §6 показывает `EntityRecord.wires` как часть общей архитектуры, но роадмап явно относит «wire bookkeeping» к Phase 2. Аддитивная миграция (ADR-0001 §4) означает, что поле можно добавить в Phase 2, не трогая уже импортированные Phase-1-сессии задним числом — сами сессии и так не переживают save/reload содержательно.
- **Почему blueprint не «пинится» в скрытый инвентарь (ADR-0001 §8(b).3) уже в Phase 1.** Пиннинг защищает от потери данных при реальном редактировании/сохранении — до тех пор, пока фаза ничего не записывает обратно и не мутирует канвас, стек в курсоре игрока не в опасности сильнее, чем был бы всё равно (ADR прямо описывает происхождение `origin = { kind = "cursor" }` как отдельный, более простой вариант рядом с `{ kind = "inventory_pinned", ... }` — Phase 1 использует первый, Phase 2+ при необходимости перейдёт на второй). Если playtest (Задача 6) покажет, что игрок легко и незаметно для себя роняет/меняет blueprint во время read-only сессии способом, который путает UX — зафиксировать как решение по ходу, не блокирует Phase 1.
- **Название поля иконок blueprint.** ADR-0001 §8(b).2 называет его `blueprint_icons` — в текущей версии Factorio 2.0 API такого свойства нет; правильное имя — `preview_icons` (подтверждено lua-api.factorio.com перед написанием кода, см. Задачу 3). Расхождение с ADR фиксируется как найденный факт, не архитектурное отклонение (аналогично находке `generate_with_lab_tiles` в Phase 0).
- **Точная формула порога `ENTITY_RENDER_WARN_THRESHOLD = 2000`** (Задача 4) — грубая оценка на старте фазы, не основана на профилировании; уточнить по факту playtest (Задача 6), если тестовая конструкция достаточно большая, иначе перенести уточнение на первую фазу, где реально понадобится blueprint такого размера.
