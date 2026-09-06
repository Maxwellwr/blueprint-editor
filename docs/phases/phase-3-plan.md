# Phase 3 — Tiles — план

- Ветка: `phase-3-tiles`
- Базовая версия перед стартом: `info.json` `0.3.0`, по завершении фазы — `0.4.0` (`docs/sdlc.md`, раздел «Версионирование»).
- Спека: [`docs/adr/0001-baseline-architecture.md`](../adr/0001-baseline-architecture.md) (разделы 4, 5, 6 частично — принцип preserve-unknown-fields распространяется и на тайлы, 9), [`docs/roadmap.md`](../roadmap.md) (описание Phase 3).

## Область фазы

Из `docs/roadmap.md`: «`place_tile`/`remove_tile`, tile catalog basics, tile rendering.» Рендер тайлов (`rendering.draw_tiles`, батчем на весь импорт) и хранение (`session.tiles`, ключ `"x,y"`) уже существуют с Phase 1 (read-only показ импортированного чертежа) — новизна этой фазы: **мутация** (разместить/убрать тайл на канвасе) и поштучный (не батчевый) рендер под неё, по тому же паттерну, что `canvas.place_entity`/`remove_entity` и `rendering.draw_entity`/`clear_entity_render` в Phase 2.

Сценарий фазы: игрок в редакторе выбирает в ad-hoc палитре (расширенной этой фазой — теперь список из сущностей **и** тайлов) либо сущность, либо тайл; клик (primary select) размещает выбранное; правый клик (alt/reverse select) или `Delete` убирает то, что под курсором — сущность, если она там есть, иначе тайл; `Q` подбирает в палитру то, что под курсором (сущность или тайл, тем же приоритетом). Решения по объёму, зафиксированные с пользователем при брейнсторминге фазы (см. также «Открытые вопросы»):

- **Единый список палитры**, не отдельный режим entity/tile — `[`/`]` листают вперемешку сущности и тайлы, размещение диспетчеризуется по `kind` текущего выбора. Не нужен ни новый хоткей режима, ни отдельный список — та же ad-hoc-костыльная конструкция, что `PALETTE_ITEMS` в Phase 2, целиком заменяется `catalog.lua` в Phase 5.
- **Тайл перезаписывается** при повторном клике в уже занятую тайлом клетку (не отклоняется, в отличие от occupied-guard у сущностей) — на клетке физически может быть только один тайл, отклонение было бы бесполезным трением; семантика «покраски», а не «постройки».
- **Приоритет удаления**: правый клик/`Delete` сначала ищет сущность под курсором и убирает её; если сущности нет — ищет и убирает тайл. Один и тот же обработчик для обоих случаев, без привязки к тому, что сейчас выбрано в палитре.

**Явно вне области Phase 3** (по аналогии с сужениями `phase-2-plan.md`):

- **Вращение/`mirror` тайлов** — у `Tile`/`TilePosition` (см. «Найденные API-факты») нет понятия направления; тайлы всегда 1×1 без ориентации. `eb-rotate` остаётся сущность-only, как и было (не трогается этой фазой).
- **Collision/occupied-guard для тайлов** — сознательно инвертировано относительно сущностей (см. выше, «перезаписывается», не «отклоняется»); отдельной защиты не требуется по определению задачи.
- **`catalog.lua`/`palette_gui.lua`** — по-прежнему Phase 5. Ad-hoc список этой фазы (Задача 4) расширяется 4 тайлами, жёстко прописанными по именам, найденным в реальных файлах установленной игры (не по памяти) — см. «Найденные API-факты». Полностью заменяется каталогом в Phase 5.
- **Новые custom-input'ы** — не добавляются. Существующие хоткеи (`eb-rotate` игнорирует тайлы, `eb-delete`/alt-select/`eb-pick-entity`/`eb-cycle-palette-*`) расширяются логически, набор клавиш не растёт.
- **Экспорт/`export_to_entities_array`** — Phase 4, без изменений; тайлы уже присутствуют в `session.tiles` в форме, готовой для будущего экспорта (preserve-unknown-fields, см. Global Constraints).
- **`quality` для тайлов** — у `Tile`/`LuaTilePrototype` нет понятия quality в API; неприменимо, не игнорируемая функциональность, а физически отсутствующая.

## Global Constraints

- `factorio_version = "2.0"` (ADR-0001 §3) — без изменений.
- `storage` — только через `scripts/state.lua`-accessors для самой сессии; поля уже полученного `Session`/`EntityRecord`/`TileRecord` объекта читаются/пишутся напрямую (граница, уточнённая в `phase-1-plan.md`/`phase-2-plan.md`).
- **Миграция `0.4.0` обязательна**: `Session.selected_palette_item` меняет форму с голой строки (Phase 2) на таблицу `{kind, name}` — это не аддитивное расширение поля, а смена формы уже существующего, поэтому требует явного шага миграции (ADR-0001 §4, «только добавляются... переиспользование без миграции запрещено»), даже притом что в остальном все новые поля этой фазы (`TileRecord.raw` для свежеразмещённых тайлов) аддитивны сами по себе.
- **Pure-logic TDD обязателен** (`docs/sdlc.md`, DoD п.6) для `canvas.tile_coordinates`/`canvas.tile_key` — первая чистая логика тайлов, по аналогии с `canvas.snap_position` в Phase 2.
- Preserve-unknown-fields (ADR-0001 §6, распространяется на тайлы по аналогии с сущностями): `place_tile` строит **новый минимальный** `raw` (`name`, `position`) только для свежеразмещённых/перезаписанных тайлов — импортированные `TileRecord.raw`, которых игрок не тронул, остаются нетронутыми per-`key`.
- Fail-fast (`docs/sdlc.md`): неизвестный тайловый прототип в `place_tile` — `error()` (не должно случаться: имя всегда из `PALETTE_ITEMS` или уже стоящего тайла, но защита остаётся, как и в `place_entity`).
- **Явный бюджет производительности** (`docs/sdlc.md`): у `rendering.draw_tiles` с Phase 1 нет явного порога предупреждения (пропуск, унаследованный от read-only фазы, где тайлы никогда не менялись поштучно) — раз эта фаза переписывает `draw_tiles` под поштучный паттерн, заодно закрывается и этот пробел: добавляется `TILE_RENDER_WARN_THRESHOLD` по образцу существующего `ENTITY_RENDER_WARN_THRESHOLD`.
- Для API-зависимого кода (`canvas.place_tile`/`remove_tile`/`find_tile_at`, `rendering.draw_tile`/`clear_tile_render`, весь `input.lua`) — автотестов нет, верификация через dev-loop + ручной playtest-чеклист.

## Найденные API-факты (проверены на `lua-api.factorio.com/2.0.77/`-эквивалентной локальной документации — `doc-html/runtime-api.json` установленной игры (`Program Files (x86)\Steam\steamapps\common\Factorio`, версия базового мода подтверждена как `2.0.77` перед проверкой), `docs/sdlc.md` «Версия Factorio и проверка API-фактов»)

- **`Tile` (концепт blueprint-тайла, `get_blueprint_tiles`/`set_blueprint_tiles`) — `{ name: string, position: TilePosition }`.** Подтверждено по `runtime-api.json`. Никакого `direction`/`orientation`/`quality` — у тайлов этих полей нет вообще, а не «есть, но не используются» (обосновывает исключение вращения/quality из области фазы выше).
- **`TilePosition`** — «rounds any non-integer x/y down to whole numbers» (дословно из документации): целочисленные координаты клетки, получаемые **округлением вниз (`floor`)**, не централизацией по чётности размера, как `MapPosition` у сущностей (`canvas.snap_position`). Тайлы всегда 1×1 — не нужен аналог `tile_width`/`tile_height`. Отсюда `canvas.tile_coordinates` — просто `math.floor` по обеим осям, без ветвления odd/even.
- **Имена тайловых прототипов ad-hoc-списка проверены в файлах установленной игры** (`data/base/prototypes/tile/tiles.lua`), не по памяти: `concrete`, `stone-path`, `refined-concrete`, `landfill` — все четыре существуют как `type = "tile"` прототипы в базовой игре `2.0.77`. (Рядом существуют `hazard-concrete-left/right`, `refined-hazard-concrete-left/right` — не включены в ad-hoc-список, чтобы не раздувать его сверх того же порядка величины, что 7-элементный список сущностей Phase 2.)
- **Наличие тайлового прототипа проверяется как `prototypes.tile[name]`**, по прямой аналогии с `prototypes.entity[name]` у сущностей (не отдельно задокументированный новый факт, но явно подтверждён тем же паттерном — `LuaTilePrototype` индексируется в `prototypes.tile` так же, как `LuaEntityPrototype` в `prototypes.entity`).

## Файлы

| Файл | Назначение |
|---|---|
| `scripts/migrations.lua` | Изменить: шаг `0.4.0` — нормализация формы `Session.selected_palette_item` (строка → `{kind, name}`) |
| `scripts/canvas.lua` | Изменить: `tile_coordinates`, `tile_key` (чистая логика, TDD), `place_tile`, `remove_tile`, `find_tile_at` (API-зависимые) |
| `spec/canvas_spec.lua` | Изменить: новые тесты на `tile_coordinates`/`tile_key` |
| `scripts/rendering.lua` | Изменить: `draw_tile`/`clear_tile_render` (поштучные аналоги, `draw_tiles` рефакторится в цикл по ним), `TILE_RENDER_WARN_THRESHOLD` |
| `scripts/input.lua` | Изменить: `PALETTE_ITEMS` — единый список `{kind, name}` (7 сущностей + 4 тайла); обработчики размещения/удаления/подбора диспетчеризуются по `kind` |
| `locale/en/controls.cfg` | Изменить: уточнить подписи `eb-delete`/`eb-pick-entity` («entity/tile», раз поведение расширено на тайлы) |

## Задачи

### Задача 1 — `scripts/migrations.lua`: миграция `0.4.0`

**Файлы:** изменить `scripts/migrations.lua`.

Текущий `Session.selected_palette_item` (добавлен в Phase 2, шаг `0.3.0`) хранит голую строку с именем сущности. Эта фаза меняет его форму на `{kind = "entity"|"tile", name = ...}` — сессия, пережившая обновление мода `0.3.x -> 0.4.0` ровно в момент нахождения игрока в редакторе, унаследует старую строковую форму, и первый же `cycle_palette`/`on_player_selected_area` упадёт на `selected.kind` (`attempt to index a string value`).

- [ ] В `scripts/migrations.lua`, в `M.steps`, добавить новый шаг в конец списка (после существующего `0.3.0`, не трогая его):

```lua
  {
    version = "0.4.0",
    fn = function()
      for _, session in state.each_session() do
        if type(session.selected_palette_item) == "string" then
          session.selected_palette_item = { kind = "entity", name = session.selected_palette_item }
        end
      end
    end,
  },
```

- [ ] Commit: `git add scripts/migrations.lua && git commit -m "feat: add 0.4.0 migration normalizing selected_palette_item to {kind, name}"`.

### Задача 2 — `scripts/canvas.lua`: мутационное API для тайлов (TDD для чистой логики)

**Файлы:** изменить `scripts/canvas.lua`, `spec/canvas_spec.lua`.

**Шаг 1 — красные тесты.** Добавить в `spec/canvas_spec.lua` (после существующего `describe("canvas.to_local_position", ...)`, перед концом файла):

```lua
describe("canvas.tile_coordinates", function()
  it("floors a fractional local position down to the containing cell", function()
    assert.are.same({ x = 3, y = 4 }, canvas.tile_coordinates({ x = 3.7, y = 4.1 }))
  end)

  it("floors negative fractional coordinates towards negative infinity", function()
    assert.are.same({ x = -4, y = -1 }, canvas.tile_coordinates({ x = -3.2, y = -0.5 }))
  end)

  it("leaves an already-integer position untouched", function()
    assert.are.same({ x = 5, y = -2 }, canvas.tile_coordinates({ x = 5, y = -2 }))
  end)
end)

describe("canvas.tile_key", function()
  it("formats coordinates as the same \"x,y\" key blueprint_io uses", function()
    assert.are.equal("3,4", canvas.tile_key(3, 4))
  end)

  it("formats negative coordinates without losing the sign", function()
    assert.are.equal("-4,-1", canvas.tile_key(-4, -1))
  end)
end)
```

- [ ] Запустить `busted` из корня репозитория. Ожидаемо: FAIL — `attempt to call a nil value (field 'tile_coordinates')` / `'tile_key'`.

**Шаг 2 — реализация.** В `scripts/canvas.lua`, после `M.to_local_position` (перед `M.find_entity_at`), добавить:

```lua
-- Чистая логика (API-факт: TilePosition "rounds any non-integer x/y down to
-- whole numbers", doc-html/runtime-api.json -- см. phase-3-plan.md "Найденные
-- API-факты") -- в отличие от snap_position у сущностей, тайлы всегда 1x1 и
-- без odd/even-центрирования, просто floor по обеим осям.
function M.tile_coordinates(local_position)
  return { x = math.floor(local_position.x), y = math.floor(local_position.y) }
end

-- Тот же формат "x,y", что уже использует blueprint_io.build_import_data для
-- ключей session.tiles -- не создаём второй несовместимый способ индексации
-- одной и той же таблицы.
function M.tile_key(x, y)
  return string.format("%d,%d", x, y)
end
```

- [ ] Запустить `busted` снова. Ожидаемо: новые тесты PASS, все прежние тесты `canvas_spec.lua`/`blueprint_io_spec.lua` по-прежнему PASS.

**Шаг 3 — API-зависимые обёртки (без busted-покрытия, зависят от `prototypes.tile`).** Добавить в `scripts/canvas.lua`, после `M.find_entity_at`:

```lua
-- Ниже -- API-зависимые обёртки для тайлов (docs/sdlc.md "Тестирование":
-- верификация -- dev-loop + ручной playtest, Задача 5).

-- В отличие от place_entity, всегда ПЕРЕЗАПИСЫВАЕТ тайл в клетке -- решение,
-- зафиксированное при планировании фазы (см. phase-3-plan.md "Область
-- фазы"): на клетке физически может быть только один тайл, повторный клик --
-- "покраска", а не конфликт размещения, отклонять нечего. Preserve-
-- unknown-fields (ADR-0001 §6): новый минимальный raw ({name, position})
-- строится только для этой -- свежеразмещённой/перезаписанной -- записи;
-- импортированные TileRecord под другими ключами не трогаются.
function M.place_tile(session, name, world_position)
  if not prototypes.tile[name] then
    error(string.format("Blueprint Editor: unknown tile prototype '%s'", name))
  end
  local local_position = M.to_local_position(session, world_position)
  local coords = M.tile_coordinates(local_position)
  local key = M.tile_key(coords.x, coords.y)
  session.tiles[key] = { raw = { name = name, position = coords } }
  return key
end

function M.remove_tile(session, key)
  local record = session.tiles[key]
  if not record then
    return nil
  end
  session.tiles[key] = nil
  return record
end

-- Тайлы всегда занимают ровно одну клетку -- в отличие от find_entity_at,
-- никакого footprint-перебора не нужно, прямое попадание по ключу клетки.
function M.find_tile_at(session, world_position)
  local local_position = M.to_local_position(session, world_position)
  local coords = M.tile_coordinates(local_position)
  local key = M.tile_key(coords.x, coords.y)
  if session.tiles[key] then
    return key
  end
  return nil
end
```

- [ ] `place_tile`/`remove_tile`/`find_tile_at` не покрыты `busted` (зависят от `prototypes.tile`) — верификация Задача 5.
- [ ] Commit: `git add scripts/canvas.lua spec/canvas_spec.lua && git commit -m "feat: add tile mutation API to canvas.lua with TDD-covered coordinate logic"`.

### Задача 3 — `scripts/rendering.lua`: поштучный рендер тайла

**Файлы:** изменить `scripts/rendering.lua`.

Текущий `M.draw_tiles` (не менялся с Phase 1) рисует все тайлы сессии за один вызов и не имеет собственного порога `*_WARN_THRESHOLD`, в отличие от `M.draw_entities`. Эта фаза добавляет мутацию тайлов поштучно (Задача 2) — нужен способ (пере)рисовать/уничтожить **один** тайл, не перерисовывая всю сессию, по тому же паттерну, что `draw_entity`/`clear_entity_render` в Phase 2. Заодно закрывается пробел с порогом (см. Global Constraints).

- [ ] Добавить константу рядом с `ENTITY_RENDER_WARN_THRESHOLD`:

```lua
-- Тот же принцип, что ENTITY_RENDER_WARN_THRESHOLD (docs/sdlc.md, "Явный
-- бюджет производительности") -- Phase 1 рисовала тайлы батчем без явного
-- порога; закрывается вместе с переходом draw_tiles на поштучный паттерн.
local TILE_RENDER_WARN_THRESHOLD = 4000
```

- [ ] Заменить текущее тело `M.draw_tiles` на:

```lua
function M.draw_tile(session, key)
  M.clear_tile_render(session, key)
  local surface = canvas_surface()
  local offset = session.canvas_offset
  local center = session.blueprint_center
  local record = session.tiles[key]
  local raw = record.raw
  local sprite = "tile/" .. raw.name
  if not helpers.is_valid_sprite_path(sprite) then
    log(string.format("Blueprint Editor: no sprite for tile '%s' (mod not installed?) -- using placeholder icon.", raw.name))
    sprite = "utility/missing_icon"
  end
  session.render_ids.tiles[key] = rendering.draw_sprite{
    sprite = sprite,
    target = { offset.x + raw.position.x - center.x + 0.5, offset.y + raw.position.y - center.y + 0.5 },
    surface = surface,
    players = { session.player_index },
  }
end

function M.draw_tiles(session)
  local count = 0
  for _ in pairs(session.tiles) do
    count = count + 1
  end
  if count > TILE_RENDER_WARN_THRESHOLD then
    log(string.format(
      "Blueprint Editor: rendering %d tiles, above the Phase 3 soft threshold (%d) -- watch for perf issues.",
      count, TILE_RENDER_WARN_THRESHOLD
    ))
  end
  for key in pairs(session.tiles) do
    M.draw_tile(session, key)
  end
end
```

  (`M.draw_tile` вызывает `M.clear_tile_render` первой строкой — обязательно для перезаписи: `place_tile` (Задача 2) переиспользует тот же ключ клетки при повторном клике, старый render-объект под этим ключом иначе останется висячим, невидимым, но живым `LuaRenderObject`, накапливающимся при многократной перекраске одной клетки.)

- [ ] Добавить рядом с `M.clear_entity_render`:

```lua
function M.clear_tile_render(session, key)
  local render_object = session.render_ids.tiles[key]
  if render_object and render_object.valid then
    render_object:destroy()
  end
  session.render_ids.tiles[key] = nil
end
```

- [ ] `draw_grid`/`draw_entity`/`draw_entities`/`clear_entity_render`/`clear_session_renders` — без изменений.
- [ ] Не покрыто `busted` (зависит от `LuaRendering`) — верификация Задача 5.
- [ ] Commit: `git add scripts/rendering.lua && git commit -m "feat: extract draw_tile/clear_tile_render for single-tile render updates"`.

### Задача 4 — `scripts/input.lua` + `locale/en/controls.cfg`: единая палитра сущностей и тайлов

**Файлы:** изменить `scripts/input.lua`, `locale/en/controls.cfg`.

Полностью заменить `scripts/input.lua` (текущее содержимое — результат Phase 2 + code review) на:

```lua
local state = require("scripts.state")
local canvas = require("scripts.canvas")
local render = require("scripts.rendering")

-- Ad-hoc единый список размещаемых сущностей и тайлов (roadmap Phase 3:
-- "tile catalog basics" -- та же ad-hoc-костыльная конструкция, что
-- PALETTE_ITEMS в Phase 2, теперь вперемешку {kind, name}. [ / ] листают весь
-- список без отдельного режима entity/tile (решение, зафиксированное при
-- планировании фазы, см. phase-3-plan.md "Область фазы"). Полностью
-- заменяется catalog.lua в Phase 5. Имена тайлов проверены в файлах
-- установленной игры (см. phase-3-plan.md "Найденные API-факты"), не по
-- памяти.
local PALETTE_ITEMS = {
  { kind = "entity", name = "transport-belt" },
  { kind = "entity", name = "inserter" },
  { kind = "entity", name = "iron-chest" },
  { kind = "entity", name = "wooden-chest" },
  { kind = "entity", name = "small-electric-pole" },
  { kind = "entity", name = "pipe" },
  { kind = "entity", name = "assembling-machine-1" },
  { kind = "tile", name = "concrete" },
  { kind = "tile", name = "stone-path" },
  { kind = "tile", name = "refined-concrete" },
  { kind = "tile", name = "landfill" },
}

local function area_center(area)
  return {
    x = (area.left_top.x + area.right_bottom.x) / 2,
    y = (area.left_top.y + area.right_bottom.y) / 2,
  }
end

local function palette_index(selected)
  if not selected then
    return nil
  end
  for i, item in ipairs(PALETTE_ITEMS) do
    if item.kind == selected.kind and item.name == selected.name then
      return i
    end
  end
  return nil
end

local function is_placeable(item)
  if item.kind == "entity" then
    return prototypes.entity[item.name] ~= nil
  end
  return prototypes.tile[item.name] ~= nil
end

-- Общий паттерн для eb-rotate (найдено code review Phase 2) -- найти сессию
-- игрока, затем СУЩНОСТЬ на указанной позиции. Только сущности: у тайлов нет
-- вращения (ADR-0001, тайлы без direction -- см. phase-3-plan.md "Найденные
-- API-факты"), поэтому eb-rotate остаётся entity-only и этой функцией не
-- расширяется на тайлы.
local function get_session_and_entity(player_index, position)
  local session = state.get_session(player_index)
  if not session then
    return nil, nil
  end
  return session, canvas.find_entity_at(session, position)
end

-- Общий паттерн для удаления/подбора (Задача 4, Phase 3) -- сначала ищет
-- сущность под позицией, затем (если сущности нет) тайл. Приоритет
-- "сущность, потом тайл" зафиксирован при планировании фазы (см.
-- phase-3-plan.md "Область фазы") -- один обработчик на оба случая, без
-- привязки к тому, что сейчас выбрано в палитре.
local function get_session_and_target(player_index, position)
  local session = state.get_session(player_index)
  if not session then
    return nil, nil, nil
  end
  local internal_id = canvas.find_entity_at(session, position)
  if internal_id then
    return session, "entity", internal_id
  end
  local tile_key = canvas.find_tile_at(session, position)
  if tile_key then
    return session, "tile", tile_key
  end
  return session, nil, nil
end

local function remove_at(player_index, position)
  local session, kind, target = get_session_and_target(player_index, position)
  if not session or not kind then
    return
  end
  if kind == "entity" then
    render.clear_entity_render(session, target)
    canvas.remove_entity(session, target)
  else
    render.clear_tile_render(session, target)
    canvas.remove_tile(session, target)
  end
end

local M = {}

-- Primary select (клик/драг с eb-cursor-tool) -- размещение. event.entities
-- на eb-canvas всегда пуст (подтверждено playtest'ом Phase 2 -- канвас
-- никогда не содержит реальных сущностей), поэтому вся логика опирается
-- только на event.area.
function M.on_player_selected_area(event)
  if event.item ~= "eb-cursor-tool" then
    return
  end
  local session = state.get_session(event.player_index)
  if not session then
    return
  end
  local selected = session.selected_palette_item
  if not selected then
    game.get_player(event.player_index).print(
      {"", "Blueprint Editor: nothing selected -- press Q on an existing entity/tile, or [ / ] to cycle the palette."})
    return
  end
  local world_position = area_center(event.area)
  if selected.kind == "entity" then
    -- Не полноценная collision-детекция (см. phase-2-plan.md "Область
    -- фазы" -- сознательно вне scope), а точечная защита от повторного
    -- клика в занятую клетку (найдено playtest'ом Phase 2).
    if canvas.find_entity_at(session, world_position) then
      game.get_player(event.player_index).print({"", "Blueprint Editor: position already occupied."})
      return
    end
    local internal_id = canvas.place_entity(session, selected.name, world_position, 0)
    render.draw_entity(session, internal_id)
  else
    -- Тайлы перезаписываются без occupied-guard (см. phase-3-plan.md
    -- "Область фазы") -- place_tile и draw_tile сами корректно обрабатывают
    -- уже занятую клетку.
    local key = canvas.place_tile(session, selected.name, world_position)
    render.draw_tile(session, key)
  end
end

-- Alt-select -- удаление (сущность, иначе тайл).
function M.on_player_alt_selected_area(event)
  if event.item ~= "eb-cursor-tool" then
    return
  end
  remove_at(event.player_index, area_center(event.area))
end

function M.on_rotate(event)
  local session, internal_id = get_session_and_entity(event.player_index, event.cursor_position)
  if not session or not internal_id then
    return
  end
  if canvas.rotate_entity(session, internal_id, 1) then
    render.clear_entity_render(session, internal_id)
    render.draw_entity(session, internal_id)
  end
end

-- Удаление по хоткею (альтернатива alt-клику) -- та же логика "сущность,
-- иначе тайл".
function M.on_delete(event)
  remove_at(event.player_index, event.cursor_position)
end

-- Подбор в палитру того, что под курсором -- сущность, иначе тайл (тот же
-- приоритет, что и у удаления).
function M.on_pick_entity(event)
  local session, kind, target = get_session_and_target(event.player_index, event.cursor_position)
  if not session or not kind then
    return
  end
  local name
  if kind == "entity" then
    name = session.entities[target].raw.name
  else
    name = session.tiles[target].raw.name
  end
  session.selected_palette_item = { kind = kind, name = name }
  game.get_player(event.player_index).print({"", "Blueprint Editor: selected " .. name})
end

local function cycle_palette(event, delta)
  local session = state.get_session(event.player_index)
  if not session then
    return
  end
  local player = game.get_player(event.player_index)
  local current_index = palette_index(session.selected_palette_item) or 0
  for _ = 1, #PALETTE_ITEMS do
    current_index = ((current_index - 1 + delta) % #PALETTE_ITEMS) + 1
    local candidate = PALETTE_ITEMS[current_index]
    if is_placeable(candidate) then
      session.selected_palette_item = candidate
      player.print({"", "Blueprint Editor: selected " .. candidate.name})
      return
    end
  end
  player.print({"", "Blueprint Editor: nothing placeable available in the palette (missing mods?)."})
end

function M.on_cycle_palette_next(event)
  cycle_palette(event, 1)
end

function M.on_cycle_palette_prev(event)
  cycle_palette(event, -1)
end

-- ADR-0001 §5: "re-enforce it staying equipped via
-- on_player_cursor_stack_changed while a session is active" -- без изменений
-- относительно Phase 2.
function M.on_cursor_stack_changed(event)
  local session = state.get_session(event.player_index)
  if not session then
    return
  end
  local player = game.get_player(event.player_index)
  local cursor_stack = player.cursor_stack
  if not cursor_stack then
    return
  end
  if cursor_stack.valid_for_read and cursor_stack.name == "eb-cursor-tool" then
    return
  end
  if player.clear_cursor() then
    cursor_stack.set_stack({ name = "eb-cursor-tool" })
  else
    player.print({"", "Blueprint Editor: could not re-equip the cursor tool (cursor full)."})
  end
end

return M
```

- [ ] `control.lua`/`data/custom-input.lua` — **без изменений**: все хоткеи/события этой фазы переиспользуют регистрацию Phase 2 (`on_player_alt_selected_area` уже подключён и к `on_player_alt_selected_area`, и к `on_player_reverse_selected_area`; `eb-rotate`/`eb-delete`/`eb-pick-entity`/`eb-cycle-palette-next/prev` — те же обработчики по тем же именам функций в `M`).
- [ ] В `locale/en/controls.cfg` уточнить две строки (поведение расширено на тайлы, подписи хоткеев должны это отражать):

```
eb-delete=Delete entity/tile under cursor
eb-pick-entity=Pick entity/tile under cursor as current palette selection
```

- [ ] Не покрыто `busted` целиком (зависит от `game`/`LuaPlayer`/событий) — верификация Задача 5.
- [ ] Commit: `git add scripts/input.lua locale/en/controls.cfg && git commit -m "feat: unify palette across entities and tiles, add tile place/remove/pick"`.

### Задача 5 — Dev-деплой и ручной playtest

Нет автотестов для API-зависимого кода этой фазы — верификация только через dev-loop + ручной прогон (`docs/sdlc.md`). `data/custom-input.lua` не менялся — **достаточно save-reload**, полный рестарт Factorio не требуется (в отличие от Phase 2).

Перед передачей чеклиста — добавить временное диагностическое логирование под префиксом `eb playtest:` в затронутые обработчики `input.lua` (`docs/sdlc.md`, «Порядок ручного playtest'а с Claude Code») и попросить пользователя прогнать чеклист один раз, отдав `factorio-current.log`; логирование убирается отдельным коммитом перед Задачей 6.

- [ ] `busted spec/` зелёный целиком (`blueprint_io_spec.lua` + `canvas_spec.lua`, включая новые тесты Задачи 2) перед стартом playtest.
- [ ] Save-reload (закрыть/открыть сохранение) — забирает изменения `control.lua`/`scripts/*` (только `input.lua`/`rendering.lua`/`canvas.lua`/`migrations.lua` в этой фазе, `control.lua` не менялся, но save-reload всё равно обязателен, т.к. меняется поведение уже загруженных модулей).
- [ ] Playtest-чеклист:
  - [ ] `Ctrl+Shift+K` — вход в редактор (любой режим).
  - [ ] `]` несколько раз подряд — сообщение в чате циклирует сначала по 7 сущностям, затем по 4 тайлам (`concrete`, `stone-path`, `refined-concrete`, `landfill`), затем оборачивается обратно на первую сущность. `[` — тот же цикл в обратном порядке.
  - [ ] Выбрав тайл, клик на канвасе — на клетке появляется спрайт тайла, привязанный к сетке (клетка целиком, не половина/со сдвигом).
  - [ ] Повторный клик тем же (или другим) тайлом в ту же клетку — старый спрайт заменяется новым, **без** визуального наложения/мерцания двух спрайтов друг на друга (проверка того, что `draw_tile` корректно уничтожает старый render-id перед перезаписью).
  - [ ] Выбрав сущность, клик в клетку, где уже стоит тайл — сущность размещается поверх тайла как обычно (тайлы и сущности — независимые слои, occupied-guard сущностей не должен видеть тайлы).
  - [ ] `Q`, наведясь на клетку с тайлом (без сущности) — палитра переключается на этот тайл (сообщение в чате подтверждает), следующий клик красит таким же тайлом.
  - [ ] `Q`, наведясь на клетку, где есть и сущность, и тайл — подбирается **сущность**, не тайл (проверка приоритета).
  - [ ] Правый клик (alt-select) по клетке с сущностью И тайлом одновременно — исчезает **сущность**, тайл остаётся видимым. Повторный правый клик по той же клетке (сущности уже нет) — теперь исчезает тайл.
  - [ ] `Delete`, наведясь на клетку только с тайлом (без сущности) — тайл исчезает (альтернативный путь удаления, та же логика, что alt-select).
  - [ ] Правый клик/`Delete` на полностью пустой клетке — ничего не происходит, ошибок в логе нет.
  - [ ] Импортировать в edit-режиме реальный blueprint с уложенными тайлами (например, `concrete` под частью построек) — тайлы отрисовываются на импорте (регрессия Phase 1, `draw_tiles` при входе в редактор), позиции визуально совпадают с оригиналом.
  - [ ] На импортированном чертеже перезаписать один из импортированных тайлов новым (тем же или другим типом) — старый `TileRecord`/render на этой клетке заменяется, соседние импортированные тайлы, которых клик не коснулся, остаются как были (preserve-unknown-fields — по факту в этой фазе тайлы либо не тронуты, либо полностью пересозданы, частичных полей нет, но регрессия на «соседей не задело» всё равно стоит проверить).
  - [ ] `/eb-dump-session` до и после операций выше — в логе видно ожидаемое состояние `session.tiles` (новые ключи появляются/пропадают, `raw.position` совпадает с местом клика).
  - [ ] Выход (`Ctrl+Shift+K`) — без ошибок, поведение выхода не регрессировало относительно Phase 2.
- [ ] Зафиксировать все результаты (включая расхождения с ожиданиями) как черновик для `phase-3-implementation.md` (Задача 6).
- [ ] Убрать временное диагностическое логирование отдельным коммитом (`chore: remove temporary playtest diagnostic logging`, по образцу Phase 2) после подтверждения чеклиста по логу.

### Задача 6 — Закрытие фазы: документация, версия, DoD

**Definition of Done фазы** (`docs/sdlc.md`) — выполнить по порядку:

- [ ] Прогнать `/code-review` на диффе ветки `phase-3-tiles`, закрыть найденные замечания.
- [ ] Создать `docs/phases/phase-3-implementation.md` по шаблону `docs/phases/TEMPLATE-implementation.md`: что сделано, решения по ходу (found facts из раздела «Найденные API-факты» выше; решения по единой палитре/перезаписи тайлов/приоритету удаления, зафиксированные при планировании), результат playtest-чеклиста (Задача 5), известные ограничения (нет вращения тайлов, нет отдельного tile-каталога — ad-hoc список из 4 типов, экспорт всё ещё Phase 4).
- [ ] Обновить `docs/roadmap.md`: отметить Phase 3 завершённой (дата, версия `0.4.0`).
- [ ] Обновить `info.json.version` → `0.4.0`.
- [ ] Обновить `CHANGELOG.md` (новая секция `0.4.0`).
- [ ] Миграция в `scripts/migrations.lua` — уже добавлена в Задаче 1 (шаг `0.4.0`), доп. действий не требуется.
- [ ] `busted spec/` зелёный (Задача 2) — приложить итог прогона в implementation-doc.
- [ ] Commit: `git add docs/roadmap.md docs/phases/phase-3-implementation.md CHANGELOG.md info.json && git commit -m "docs: close out phase 3"`.
- [ ] Смержить `phase-3-tiles` в `main` (после ручного подтверждения пользователем — мерж не выполняется автоматически).

## Спайки

Нет отдельных архитектурных неизвестных, требующих спайка — эта фаза целиком зеркалирует уже подтверждённый в Phase 2 паттерн мутации/поштучного рендера, применяя его к тайлам вместо сущностей. Единственный ранее непроверенный факт (форма `Tile`/`TilePosition`, округление `floor` вместо odd/even-центрирования) проверен документацией до написания кода (см. «Найденные API-факты»), не требует игрового спайка.

## Открытые вопросы

- **Почему тайлы перезаписываются, а сущности — нет (occupied-guard).** Разные физические ограничения: на клетке может стоять только один тайл (сама природа данных — `session.tiles` ключуется по клетке, второй тайл на той же клетке структурно невозможен, только замена), тогда как сущности разного размера в принципе могут (пусть и некорректно) сосуществовать на пересекающихся клетках — occupied-guard там страхует от случайного дубля, а не от структурной невозможности. У тайлов дублировать нечего, значит и отклонять нечего — перезапись логичнее по семантике «покраски», принятой пользователем при планировании.
- **Почему у `eb-rotate` не появилось tile-ветки.** `Tile`/`TilePosition` не имеют полей direction/orientation в принципе (см. «Найденные API-факты») — не отложенный нюанс, а отсутствующая в API концепция; расширять `get_session_and_entity` на тайлы означало бы либо no-op ветку без смысла, либо API, которого не существует.
- **Почему `find_tile_at` не учитывает multi-tile прототипы (в духе footprint-перебора `find_entity_at`).** Тайлы в Factorio всегда занимают ровно одну клетку (нет аналога `tile_width`/`tile_height` у `LuaTilePrototype`) — не сужение объёма, а точное соответствие модели данных.
