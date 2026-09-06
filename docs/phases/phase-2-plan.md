# Phase 2 — Add/remove/rotate entities + entity_number/wire bookkeeping — план

- Ветка: `phase-2-mutate`
- Базовая версия перед стартом: `info.json` `0.2.1`, по завершении фазы — `0.3.0` (`docs/sdlc.md`, раздел «Версионирование»).
- Спека: [`docs/adr/0001-baseline-architecture.md`](../adr/0001-baseline-architecture.md) (разделы 3, 4, 5, 6, 8(b).3 частично), [`docs/roadmap.md`](../roadmap.md) (описание Phase 2).

## Область фазы

Из `docs/roadmap.md`: `canvas.lua` mutation API, `input.lua`, cursor-tool equip, entity_number/wire bookkeeping. «A minimal ad-hoc entity picker is fine here; the full palette UI is Phase 5.» Test фазы: удалить провод-соединённый столб, сдампить сессию через debug-команду, убедиться, что удалённый id пропал из `wires` всех остальных сущностей.

Сценарий фазы: игрок внутри редактора (после Phase 1 — либо «new», либо «edit» режим) экипирован `eb-cursor-tool`. Клик (primary select) на канвасе размещает сущность выбранного в ad-hoc «палитре» типа; alt-клик удаляет сущность под курсором; `R` вращает сущность под мышью; `Delete` удаляет сущность под мышью (альтернатива alt-клику); `Q` подбирает тип уже стоящей на канвасе сущности как текущий выбор для размещения; `[`/`]` циклируют по небольшому жёстко зашитому списку типов. Импортированные (Phase 1) сущности с проводными соединениями (`BlueprintEntity.wires`) при импорте превращаются в `EntityRecord.wires` (по `internal_id`, не по `entity_number`); удаление любой такой сущности вычищает ссылки на неё из `wires` всех остальных.

**Явно вне области Phase 2** (сужение, зафиксированное явно, как и в `phase-1-plan.md`):

- **Move/перемещение существующей сущности** — роадмап Phase 2 называет только три глагола («Add/remove/rotate»), move не входит. Workaround на эту фазу: remove + place заново тем же выбранным типом. Полноценный drag-move — не запланирован явно ни для одной фазы; если понадобится, потребует отдельного ADR-дополнения (не тривиальное аддитивное расширение — меняет модель ввода).
- **Collision-детекция при размещении** (проверка занятости позиции перед `place_entity`) — ADR-0001 не требует её для canvas-механики явно, роадмап Phase 2 не называет её тестом фазы. Наложение спрайтов друг на друга визуально некрасиво, но не ломает корректность экспорта (Phase 4) и не мешает DoD-тесту фазы. Отложено; если станет проблемой в playtest — фиксируется как решение по ходу, не блокер.
- **Полноценная гранулярность вращения** («cycle step depends on the entity's own rotation granularity», ADR-0001 §5) — Phase 2 вращает фиксированным шагом в четверть оборота (`direction + 4`, по модулю 16) для любой сущности с `prototype.supports_direction == true`, без учёта диагональных рельс/особых сущностей с другим шагом. Явно отложенный нюанс той же строки ADR.
- **`catalog.lua`/`palette_gui.lua`** — Phase 5, как и было. Вместо генерик-каталога (`item.place_result`) — жёстко зашитый список из 7 типов сущностей в `input.lua` (см. Задача 5), явно поименованный как ad-hoc-костыль конкретно для этой фазы (роадмап прямо разрешает: «A minimal ad-hoc entity picker is fine here»). Это единственное осознанное отступление от принципа «generic-каталог без хардкода имён» (`docs/sdlc.md`, «Архитектурные принципы») в этой фазе — оправдано явной формулировкой роадмапа и тем, что список полностью заменяется каталогом в Phase 5, не переживает эту фазу как постоянная архитектура.
- **`quality`** — `Session.selected_quality`/`EntityRecord.raw.quality` при размещении не устанавливаются (остаётся отсутствующим = `"normal"` по умолчанию движка). ADR-0001 §7 явно привязывает quality-функциональность к каталогу (Phase 5) и к наличию Space Age.
- **Wire-редактирование игроком** (создание/удаление проводов через UI) — Phase 6, как и в роадмапе. Phase 2 только строит и поддерживает корректность существующей (импортированной) проводной топологии при удалении сущностей; создавать новые провода на канвасе в этой фазе нельзя (у свежеразмещённых сущностей `wires = {}` и остаётся пустым).
- **`export_to_entities_array`/сохранение** — Phase 4, без изменений.
- **`eb-cancel`/`eb-flip`** — оба custom-input упомянуты в `data/custom-input.lua`-заголовке ADR-0001 §3 как часть полного будущего набора мода, но ни один явно не назван в тесте/скоупе Phase 2. `eb-flip` (`mirror`) не имеет назначения без полноценной палитры (нечего листать/отменять) — отложен вместе с ней. `eb-cancel` не добавляется: у Phase 2 нет многошагового режима размещения (клик — сразу размещение), отменять нечего.

## Global Constraints

- `factorio_version = "2.0"` (ADR-0001 §3) — без изменений.
- `storage` — только через `scripts/state.lua` (см. уточнение границы в `phase-1-plan.md`: код, уже получивший `Session` через `state.get_session()`, свободно читает/пишет поля этого объекта напрямую).
- Миграции — только аддитивные (ADR-0001 §4, `docs/sdlc.md`). Новые поля: `Session.selected_palette_item`, `EntityRecord.wires`. Обязателен шаг миграции `0.3.0` для той же причины, что и `0.2.0` в Phase 1 (сессия могла пережить границу обновления мода).
- **Pure-logic TDD обязателен** (`docs/sdlc.md`, DoD п.6) для: `blueprint_io.build_import_data` (расширение — сборка `wires`), `canvas.snap_position`, `canvas.next_direction`, `canvas.remove_wire_references`. Это флагманский пример из `docs/sdlc.md`: «обязательный TDD... в первую очередь Phase 2 для remap» — буквально код этой фазы.
- Preserve-unknown-fields (ADR-0001 §6): `place_entity` строит **новый минимальный** `raw` (`name`, `position`, `direction`) только для свежеразмещённых сущностей — импортированные `raw`-таблицы, которых Phase 2 не коснулась (не удалены/не повёрнуты), остаются нетронутыми. Повёрнутая сущность получает только оверлей `raw.direction`, остальные поля не пересобираются.
- Fail-fast для данных API (`docs/sdlc.md`): провод, ссылающийся на `entity_number` вне текущего blueprint'а (после сборки `entity_number -> internal_id` map отсутствует ключ) — `error()`, не тихий пропуск. Неизвестный `place_result`-прототип в `place_entity` — тоже `error()` (не должно случаться: имя всегда берётся из `PALETTE_ITEMS`/уже размещённой сущности, но защита остаётся).
- Явный бюджет производительности (`docs/sdlc.md`): без новых render-структур сверх Phase 1 (`draw_entity`/`clear_entity_render` работают поштучно, не массово) — существующий `ENTITY_RENDER_WARN_THRESHOLD` не меняется.
- Для API-зависимого кода (`canvas.place_entity`/`remove_entity`/`rotate_entity`/`find_entity_at`, весь `input.lua`, `debug.lua`) — automated-тестов нет, верификация через dev-loop + ручной playtest-чеклист.

## Найденные API-факты (проверены на `lua-api.factorio.com/2.0.77/` перед написанием кода, `docs/sdlc.md` «Версия Factorio и проверка API-фактов»)

Эти факты **расходятся** с формулировкой псевдокода в ADR-0001 §6 (который писался как design-only, до проверки по документации) — зафиксировать в `phase-2-implementation.md` по аналогии с находками `preview_icons`/`cursor_record` в Phase 1:

- **`BlueprintWire` — позиционный кортеж, не именованная таблица.** `{source_entity_number, source_wire_connector_id, target_entity_number, target_wire_connector_id}` (4 элемента по индексу), а не `{wire_type=, this_conn=, target_conn=}`, как предполагал псевдокод ADR. `wire_connector_id` — значение `defines.wire_connector_id` (`circuit_red`, `circuit_green`, `pole_copper`, и т.д. — непрозрачное число для мода, не интерпретируется, только хранится и позже пойдёт на экспорт в Phase 4).
- **`BlueprintEntity.wires`** — опциональный массив `BlueprintWire`, поле на **каждой** сущности отдельно (не общий список на уровне blueprint'а — такого метода/поля в API нет: `get_blueprint_entities()`/`get_blueprint_tiles()` задокументированы, отдельного `get_blueprint_wires()` нет).
- **Не задокументировано и не проверено**, дублирует ли игра одну и ту же проводную связь в `wires` **обеих** связанных сущностей, или пишет её только у одной (произвольной) стороны. Задача 2 строит импорт устойчиво к обоим случаям (см. ниже) — итог фиксируется как найденный факт по результатам playtest (Задача 9), не как допущение.
- **`LuaEntityPrototype.tile_width`/`tile_height`** подтверждают формулировку ADR-0001 §5 дословно: нечётный размер — центр сущности на центре тайла (`x.5`), чётный — на границе тайлов (`x.0`). `canvas.snap_position` (Задача 3) реализует ровно это правило.
- **`LuaEntityPrototype.supports_direction`** (bool) — используется в `canvas.rotate_entity`, чтобы не пытаться вращать сущности, которые в принципе не вращаются (не было в ADR, найдено при подготовке этой фазы).
- **`BoundingBox`** — `{left_top: MapPosition, right_bottom: MapPosition, orientation?}`. `on_player_selected_area`/`on_player_alt_selected_area` дают `area` этой формы; `entities`/`tiles` в этих событиях — `array[LuaEntity]`/`array[LuaTile]` **реальных** объектов на поверхности. Поскольку канвас никогда не содержит настоящих сущностей (ADR-0001 §1, «Chosen architecture» — данные + `LuaRendering`, никогда не instantiated как реальные объекты), эти массивы на `eb-canvas` **всегда пустые** — вся логика Задачи 5 обязана опираться только на `event.area`/`event.item`, никогда на `event.entities`. Это прямое следствие архитектуры, но помечено как спайк (см. «Спайки» ниже) — подтвердить логом на реальном канвасе, не полагаться только на рассуждение.
- **`on_player_cursor_stack_changed`** — поля только `{player_index, name, tick}`, никакого содержимого стека. «Fired... in the same tick... but not instantly» — важно для Задачи 6: скриптовая запись `cursor_stack.set_stack(...)` внутри обработчика этого же события сама вызовет его повторно (в том же тике), поэтому обработчик обязан проверять текущее содержимое стека **до** записи и не писать, если там уже `eb-cursor-tool` — иначе потенциальный бесконечный цикл событий.
- **`CustomCommandData`** — `{name, tick, player_index?, parameter?}`; `player_index` — `nil`, если команда вызвана из серверной консоли (`scripts/debug.lua`, Задача 8, обязан это учитывать).

## Файлы

| Файл | Назначение |
|---|---|
| `scripts/state.lua` | Изменить: `Session.selected_palette_item` (новое аддитивное поле) |
| `scripts/migrations.lua` | Изменить: шаг `0.3.0` — backfill `EntityRecord.wires` для сессий, переживших Phase 1 |
| `scripts/blueprint_io.lua` | Изменить: `build_import_data` строит `EntityRecord.wires` из `BlueprintEntity.wires` (двунаправленно, с дедупликацией) |
| `spec/blueprint_io_spec.lua` | Изменить: новые тесты на сборку `wires` |
| `scripts/canvas.lua` | Новый: мутационное API — `snap_position`, `next_direction`, `remove_wire_references` (чистая логика, TDD), `place_entity`, `remove_entity`, `rotate_entity`, `find_entity_at` (API-зависимые) |
| `spec/canvas_spec.lua` | Новый: `busted`-тесты чистой логики `canvas.lua` |
| `scripts/rendering.lua` | Изменить: `draw_entity`/`clear_entity_render` (поштучные аналоги существующих `draw_entities`/`clear_session_renders`) |
| `scripts/input.lua` | Новый: обработчики `on_player_selected_area`/`alt`/custom-input → вызовы `canvas.lua`/`rendering.lua`; ad-hoc `PALETTE_ITEMS` |
| `scripts/surface.lua` | Изменить: `teleport_in` экипирует `eb-cursor-tool` и в «edit»-режиме тоже (не только «new») |
| `scripts/debug.lua` | Новый: команда `eb-dump-session` — `serpent.block()`-дамп сессии в лог |
| `control.lua` | Изменить: подключить `input.lua`/`debug.lua`, зарегистрировать новые события/команду, убрать спайковый `on_selected_area` |
| `data/custom-input.lua` | Изменить: 5 новых custom-input (`eb-rotate`, `eb-delete`, `eb-pick-entity`, `eb-cycle-palette-next/prev`) |
| `locale/en/controls.cfg` | Изменить: подписи для новых custom-input |

## Задачи

### Задача 1 — `scripts/state.lua` и `scripts/migrations.lua`: `selected_palette_item` + миграция `0.3.0`

**Файлы:** изменить `scripts/state.lua`, `scripts/migrations.lua`.

- [ ] В `M.start_session` (текущее тело — см. `scripts/state.lua`, актуально после Phase 1 patch `0.2.1`) добавить поле в конструируемую таблицу `session`:

```lua
    blueprint_snap = import_data and import_data.blueprint_snap or nil,
    selected_palette_item = nil,
```

  (Добавляется после существующей строки `blueprint_snap = ...`; `import_data` никогда не задаёт выбор палитры — это чисто runtime-состояние редактирования, не часть импортированных данных.)

- [ ] Остальной `state.lua` — без изменений.
- [ ] Commit: `git add scripts/state.lua && git commit -m "feat: add Session.selected_palette_item for the ad-hoc entity picker"`.

- [ ] В `scripts/migrations.lua`, в `M.steps`, добавить новый шаг в конец списка (после существующего `0.2.0`, не трогая его):

```lua
  {
    version = "0.3.0",
    fn = function()
      for _, session in state.each_session() do
        for _, entity in pairs(session.entities) do
          entity.wires = entity.wires or {}
        end
      end
    end,
  },
```

  Обоснование (по аналогии с комментарием у шага `0.2.0`): игрок, оставшийся на канвасе ровно в момент обновления мода `0.2.x -> 0.3.0`, унаследует `EntityRecord`-ы Phase-1-формы без поля `wires`. Первый же `canvas.remove_entity` на такой сессии упадёт на `record.wires` (nil, если бы `remove_wire_references` не было defensive) или тихо не вычистит несуществующие связи — миграция нормализует форму до того, как код это увидит.
- [ ] Commit: `git add scripts/migrations.lua && git commit -m "feat: add 0.3.0 migration step backfilling EntityRecord.wires"`.

### Задача 2 — `scripts/blueprint_io.lua`: сборка `wires` при импорте (TDD)

**Файлы:** изменить `scripts/blueprint_io.lua`, `spec/blueprint_io_spec.lua`.

**Шаг 1 — красные тесты.** Добавить в `spec/blueprint_io_spec.lua`, внутрь существующего `describe("blueprint_io.build_import_data", ...)` (после последнего `it`, перед закрывающим `end)` блока):

```lua
  it("gives every entity an empty wires table when the blueprint has no wires", function()
    local entities = blueprint_io.build_import_data({
      { entity_number = 1, name = "iron-chest", position = { x = 0, y = 0 } },
    }, {})
    assert.are.same({}, entities[1].wires)
  end)

  it("builds a bidirectional wire entry from a one-sided BlueprintWire tuple", function()
    local entities = blueprint_io.build_import_data({
      { entity_number = 1, name = "small-electric-pole", position = { x = 0, y = 0 },
        wires = { { 1, defines.wire_connector_id.pole_copper, 2, defines.wire_connector_id.pole_copper } } },
      { entity_number = 2, name = "small-electric-pole", position = { x = 5, y = 0 } },
    }, {})
    assert.are.same({
      { target_internal_id = 2, this_connector_id = defines.wire_connector_id.pole_copper, target_connector_id = defines.wire_connector_id.pole_copper },
    }, entities[1].wires)
    assert.are.same({
      { target_internal_id = 1, this_connector_id = defines.wire_connector_id.pole_copper, target_connector_id = defines.wire_connector_id.pole_copper },
    }, entities[2].wires)
  end)

  it("dedups when the same wire is listed on both connected entities", function()
    local entities = blueprint_io.build_import_data({
      { entity_number = 1, name = "small-electric-pole", position = { x = 0, y = 0 },
        wires = { { 1, defines.wire_connector_id.pole_copper, 2, defines.wire_connector_id.pole_copper } } },
      { entity_number = 2, name = "small-electric-pole", position = { x = 5, y = 0 },
        wires = { { 2, defines.wire_connector_id.pole_copper, 1, defines.wire_connector_id.pole_copper } } },
    }, {})
    assert.are.equal(1, #entities[1].wires)
    assert.are.equal(1, #entities[2].wires)
  end)

  it("errors on a wire referencing an entity_number outside the blueprint", function()
    assert.has_error(function()
      blueprint_io.build_import_data({
        { entity_number = 1, name = "small-electric-pole", position = { x = 0, y = 0 },
          wires = { { 1, defines.wire_connector_id.pole_copper, 99, defines.wire_connector_id.pole_copper } } },
      }, {})
    end)
  end)
```

  `defines.wire_connector_id` не существует вне игрового рантайма — `busted` запускается вне Factorio (`docs/sdlc.md`, «Тестирование»). Добавить минимальный stub в `spec/blueprint_io_spec.lua`, **до** `require("scripts.blueprint_io")` в начале файла:

```lua
_G.defines = _G.defines or { wire_connector_id = { pole_copper = 5, circuit_red = 1, circuit_green = 2 } }

local blueprint_io = require("scripts.blueprint_io")
```

  (Значения самих чисел неважны для теста — важна их согласованность между обеими сторонами провода; реальные значения приходят из игры в рантайме, стаб нужен только чтобы тестовый файл не падал на неопределённой глобальной переменной.)

- [ ] Запустить `busted` из корня репозитория. Ожидаемо: FAIL — `attempt to index a nil value (field 'wires')` или `entities[1].wires` не существует (текущая реализация не строит `wires` вовсе).

**Шаг 2 — реализация.** Текущий `scripts/blueprint_io.lua` (после Phase 1) уже прочитан этой сессией — редактируется `M.build_import_data`. Заменить тело функции целиком:

```lua
local function wire_key(id_a, conn_a, id_b, conn_b)
  if id_a > id_b or (id_a == id_b and conn_a > conn_b) then
    id_a, conn_a, id_b, conn_b = id_b, conn_b, id_a, conn_a
  end
  return id_a .. ":" .. conn_a .. ":" .. id_b .. ":" .. conn_b
end

-- Чистая логика без Factorio API (ADR-0001 §6): назначает монотонный
-- internal_id каждой сущности блюпринта (не переиспользуя entity_number),
-- индексирует тайлы по "x,y" и строит EntityRecord.wires по internal_id
-- (ADR-0001 §6, docs/sdlc.md "в первую очередь Phase 2 для remap").
--
-- BlueprintWire -- позиционный кортеж {source_entity_number,
-- source_connector_id, target_entity_number, target_connector_id}
-- (подтверждённый API-факт, см. phase-2-plan.md "Найденные API-факты" --
-- расходится с формулировкой ADR-0001 §6, где поля были именованными).
-- Не задокументировано, дублирует ли игра один провод в wires ОБЕИХ сторон
-- или только одной -- сборка ниже устойчива к обоим случаям: каждый
-- уникальный провод (симметричный ключ wire_key, не зависящий от того, с
-- чьей стороны он встретился) добавляется РОВНО ОДИН РАЗ в wires каждой из
-- двух связанных сущностей, независимо от того, был ли он в исходных данных
-- перечислен раз или дважды.
function M.build_import_data(bp_entities, bp_tiles)
  local entities = {}
  local entity_number_to_internal_id = {}
  local next_internal_id = 1
  for _, bp_entity in ipairs(bp_entities) do
    local internal_id = next_internal_id
    next_internal_id = next_internal_id + 1
    entities[internal_id] = { internal_id = internal_id, raw = bp_entity, wires = {} }
    entity_number_to_internal_id[bp_entity.entity_number] = internal_id
  end

  local seen_wires = {}
  for _, bp_entity in ipairs(bp_entities) do
    if bp_entity.wires then
      for _, wire in ipairs(bp_entity.wires) do
        local source_number, source_connector, target_number, target_connector =
          wire[1], wire[2], wire[3], wire[4]
        local source_id = entity_number_to_internal_id[source_number]
        local target_id = entity_number_to_internal_id[target_number]
        if not source_id or not target_id then
          error(string.format(
            "Blueprint Editor: blueprint wire references entity_number outside the blueprint (%s -> %s)",
            tostring(source_number), tostring(target_number)
          ))
        end
        local key = wire_key(source_id, source_connector, target_id, target_connector)
        if not seen_wires[key] then
          seen_wires[key] = true
          local source_wires = entities[source_id].wires
          source_wires[#source_wires + 1] = {
            target_internal_id = target_id,
            this_connector_id = source_connector,
            target_connector_id = target_connector,
          }
          if source_id ~= target_id then
            local target_wires = entities[target_id].wires
            target_wires[#target_wires + 1] = {
              target_internal_id = source_id,
              this_connector_id = target_connector,
              target_connector_id = source_connector,
            }
          end
        end
      end
    end
  end

  local tiles = {}
  for _, bp_tile in ipairs(bp_tiles) do
    local key = string.format("%d,%d", bp_tile.position.x, bp_tile.position.y)
    tiles[key] = { raw = bp_tile }
  end

  return entities, tiles, next_internal_id
end
```

- [ ] Запустить `busted` снова. Ожидаемо: все тесты `blueprint_io_spec.lua` (старые + новые) PASS.
- [ ] Проверить, что `M.import_from_stack` не требует изменений — она уже вызывает `M.build_import_data` и прозрачно прокидывает результат дальше; `wires` появляется в `entities` автоматически.
- [ ] Commit: `git add scripts/blueprint_io.lua spec/blueprint_io_spec.lua && git commit -m "feat: build EntityRecord.wires from BlueprintWire on import (TDD)"`.

### Задача 3 — `scripts/canvas.lua`: мутационное API (TDD для чистой логики)

**Файлы:** создать `scripts/canvas.lua`, `spec/canvas_spec.lua`.

**Шаг 1 — красные тесты.** Создать `spec/canvas_spec.lua`:

```lua
local canvas = require("scripts.canvas")

describe("canvas.snap_position", function()
  it("centers odd-sized entities on the tile center", function()
    assert.are.same({ x = 3.5, y = 4.5 }, canvas.snap_position(1, 1, { x = 3.2, y = 4.9 }))
  end)

  it("centers even-sized entities on the tile border", function()
    assert.are.same({ x = 3, y = 5 }, canvas.snap_position(2, 2, { x = 3.2, y = 4.9 }))
  end)

  it("handles mixed odd/even dimensions independently per axis", function()
    assert.are.same({ x = 3, y = 4.5 }, canvas.snap_position(2, 3, { x = 3.2, y = 4.9 }))
  end)

  it("leaves an already-snapped position untouched", function()
    assert.are.same({ x = 2.5, y = 2.5 }, canvas.snap_position(1, 1, { x = 2.5, y = 2.5 }))
    assert.are.same({ x = 5, y = 5 }, canvas.snap_position(2, 2, { x = 5, y = 5 }))
  end)
end)

describe("canvas.next_direction", function()
  it("steps a quarter turn forward by default", function()
    assert.are.equal(4, canvas.next_direction(0))
  end)

  it("wraps around at a full turn (16)", function()
    assert.are.equal(0, canvas.next_direction(12, 1))
  end)

  it("treats a nil current direction as north (0)", function()
    assert.are.equal(4, canvas.next_direction(nil, 1))
  end)

  it("steps backwards and wraps for negative steps", function()
    assert.are.equal(12, canvas.next_direction(0, -1))
  end)
end)

describe("canvas.remove_wire_references", function()
  it("removes references to the deleted entity from every other entity's wires", function()
    local entities = {
      [1] = { internal_id = 1, wires = { { target_internal_id = 2, this_connector_id = 5, target_connector_id = 5 } } },
      [2] = { internal_id = 2, wires = {
        { target_internal_id = 1, this_connector_id = 5, target_connector_id = 5 },
        { target_internal_id = 3, this_connector_id = 5, target_connector_id = 5 },
      } },
      [3] = { internal_id = 3, wires = { { target_internal_id = 2, this_connector_id = 5, target_connector_id = 5 } } },
    }
    canvas.remove_wire_references(entities, 2)
    assert.are.same({}, entities[1].wires)
    assert.are.same({}, entities[3].wires)
  end)

  it("leaves unrelated wires on other entities untouched", function()
    local entities = {
      [1] = { internal_id = 1, wires = { { target_internal_id = 3, this_connector_id = 5, target_connector_id = 5 } } },
      [2] = { internal_id = 2, wires = {} },
      [3] = { internal_id = 3, wires = { { target_internal_id = 1, this_connector_id = 5, target_connector_id = 5 } } },
    }
    canvas.remove_wire_references(entities, 2)
    assert.are.same({ { target_internal_id = 3, this_connector_id = 5, target_connector_id = 5 } }, entities[1].wires)
    assert.are.same({ { target_internal_id = 1, this_connector_id = 5, target_connector_id = 5 } }, entities[3].wires)
  end)

  it("is a no-op when the removed id has no incoming references", function()
    local entities = { [1] = { internal_id = 1, wires = {} } }
    canvas.remove_wire_references(entities, 99)
    assert.are.same({}, entities[1].wires)
  end)
end)
```

- [ ] Запустить `busted`. Ожидаемо: FAIL (`module 'scripts.canvas' not found`).

**Шаг 2 — реализация.** Создать `scripts/canvas.lua`:

```lua
local M = {}

-- Чистая логика без Factorio API (ADR-0001 §5, подтверждено
-- LuaEntityPrototype.tile_width/tile_height, см. phase-2-plan.md "Найденные
-- API-факты"): нечётный размер -- центр сущности на центре тайла (x.5),
-- чётный -- на границе тайлов (x.0).
local function snap_axis(value, size)
  if size % 2 == 1 then
    return math.floor(value) + 0.5
  end
  return math.floor(value + 0.5)
end

function M.snap_position(tile_width, tile_height, raw_position)
  return {
    x = snap_axis(raw_position.x, tile_width),
    y = snap_axis(raw_position.y, tile_height),
  }
end

-- Чистая логика: direction в Factorio 2.0 -- 1/16 оборота (0..15). Phase 2
-- MVP вращает фиксированным шагом в четверть оборота вне зависимости от
-- собственной гранулярности сущности (осознанно отложенный нюанс, см.
-- phase-2-plan.md "Область фазы").
function M.next_direction(current_direction, steps)
  local step_count = steps or 1
  return ((current_direction or 0) + step_count * 4) % 16
end

-- Чистая логика (ADR-0001 §6, флагманский TDD-пример из docs/sdlc.md): при
-- удалении сущности вычищает ссылки на неё из wires всех ОСТАЛЬНЫХ сущностей.
-- Мутирует `entities` на месте -- вызывающая сторона (M.remove_entity) уже
-- удалила саму запись под removed_internal_id до вызова этой функции.
function M.remove_wire_references(entities, removed_internal_id)
  for id, record in pairs(entities) do
    if id ~= removed_internal_id and record.wires then
      local kept = {}
      for _, wire in ipairs(record.wires) do
        if wire.target_internal_id ~= removed_internal_id then
          kept[#kept + 1] = wire
        end
      end
      record.wires = kept
    end
  end
end

-- Ниже -- API-зависимые обёртки (docs/sdlc.md "Тестирование": не покрыты
-- busted, верификация -- dev-loop + ручной playtest, Задача 9).

-- Только для свежеразмещённых сущностей строится новый минимальный raw
-- (preserve-unknown-fields, ADR-0001 §6) -- импортированные сущности этой
-- функцией не создаются.
function M.place_entity(session, name, position, direction)
  local prototype = prototypes.entity[name]
  if not prototype then
    error(string.format("Blueprint Editor: unknown entity prototype '%s'", name))
  end
  local internal_id = session.next_internal_id
  session.next_internal_id = internal_id + 1
  session.entities[internal_id] = {
    internal_id = internal_id,
    raw = {
      name = name,
      position = M.snap_position(prototype.tile_width, prototype.tile_height, position),
      direction = direction or 0,
    },
    wires = {},
  }
  return internal_id
end

function M.remove_entity(session, internal_id)
  local record = session.entities[internal_id]
  if not record then
    return nil
  end
  session.entities[internal_id] = nil
  M.remove_wire_references(session.entities, internal_id)
  return record
end

-- nil, если сущность не найдена или её прототип не поддерживает вращение
-- (LuaEntityPrototype.supports_direction, найденный API-факт).
function M.rotate_entity(session, internal_id, steps)
  local record = session.entities[internal_id]
  if not record then
    return nil
  end
  local prototype = prototypes.entity[record.raw.name]
  if not prototype or not prototype.supports_direction then
    return nil
  end
  record.raw.direction = M.next_direction(record.raw.direction, steps)
  return record.raw.direction
end

-- Обратная операция офсета из rendering.lua (target = canvas_offset +
-- raw.position - blueprint_center) -- переводит мировую (target-space)
-- позицию клика обратно в локальные координаты blueprint'а.
local function to_local_position(session, world_position)
  local offset = session.canvas_offset
  local center = session.blueprint_center
  return {
    x = world_position.x - offset.x + center.x,
    y = world_position.y - offset.y + center.y,
  }
end

-- Первая сущность, чей footprint (tile_width/tile_height вокруг raw.position,
-- то же правило центрирования, что и snap_position) содержит world_position.
-- Коллизии не проверяются при размещении (см. "Область фазы") -- при
-- наложении спрайтов возвращает первую найденную в порядке pairs()
-- (недетерминированно), это принятое ограничение MVP, не баг.
function M.find_entity_at(session, world_position)
  local local_position = to_local_position(session, world_position)
  for internal_id, record in pairs(session.entities) do
    local prototype = prototypes.entity[record.raw.name]
    local tile_width = prototype and prototype.tile_width or 1
    local tile_height = prototype and prototype.tile_height or 1
    local pos = record.raw.position
    local half_w, half_h = tile_width / 2, tile_height / 2
    if local_position.x >= pos.x - half_w and local_position.x <= pos.x + half_w
        and local_position.y >= pos.y - half_h and local_position.y <= pos.y + half_h then
      return internal_id
    end
  end
  return nil
end

return M
```

- [ ] Запустить `busted` снова. Ожидаемо: все тесты `canvas_spec.lua` PASS (12 тестов), `blueprint_io_spec.lua` по-прежнему PASS.
- [ ] `place_entity`/`remove_entity`/`rotate_entity`/`find_entity_at` не покрыты `busted` (зависят от `prototypes.entity`) — верификация Задача 9.
- [ ] Commit: `git add scripts/canvas.lua spec/canvas_spec.lua && git commit -m "feat: add canvas.lua mutation API with TDD-covered snap/rotation/wire-cleanup logic"`.

### Задача 4 — `scripts/rendering.lua`: поштучный рендер сущности

**Файлы:** изменить `scripts/rendering.lua`.

Текущий `M.draw_entities` (после Phase 1 patch `0.2.1`) рисует все сущности сессии за один вызов. Задача 5/6 нужно уметь рисовать/уничтожать **одну** сущность за раз (после `place_entity`/`remove_entity`/`rotate_entity`), не перерисовывая всю сессию. Рефакторинг: вынести тело цикла в `M.draw_entity(session, internal_id)`, `M.draw_entities` вызывает её в цикле (DRY, без дублирования логики построения спрайта).

- [ ] Заменить `M.draw_entities` (текущее тело — см. `scripts/rendering.lua`) на:

```lua
function M.draw_entity(session, internal_id)
  local surface = canvas_surface()
  local offset = session.canvas_offset
  local center = session.blueprint_center
  local record = session.entities[internal_id]
  local raw = record.raw
  local orientation = 0
  if raw.direction then
    -- Factorio 2.0: direction в 1/16 оборота; orientation LuaRendering -- доля оборота (0..1).
    orientation = raw.direction / 16
  end
  local sprite = "entity/" .. raw.name
  if not helpers.is_valid_sprite_path(sprite) then
    log(string.format("Blueprint Editor: no sprite for entity '%s' (mod not installed?) -- using placeholder icon.", raw.name))
    sprite = "utility/missing_icon"
  end
  session.render_ids.entities[internal_id] = rendering.draw_sprite{
    sprite = sprite,
    target = { offset.x + raw.position.x - center.x, offset.y + raw.position.y - center.y },
    orientation = orientation,
    surface = surface,
    players = { session.player_index },
  }
end

function M.draw_entities(session)
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
  for internal_id in pairs(session.entities) do
    M.draw_entity(session, internal_id)
  end
end
```

- [ ] Добавить рядом с `M.clear_session_renders`:

```lua
function M.clear_entity_render(session, internal_id)
  local render_object = session.render_ids.entities[internal_id]
  if render_object and render_object.valid then
    render_object:destroy()
  end
  session.render_ids.entities[internal_id] = nil
end
```

- [ ] `draw_tiles`/`clear_session_renders`/`draw_grid` — без изменений.
- [ ] Не покрыто `busted` (зависит от `LuaRendering`) — верификация Задача 9 (визуально: размещение/удаление/поворот отражаются на канвасе без полной перерисовки).
- [ ] Commit: `git add scripts/rendering.lua && git commit -m "feat: extract draw_entity/clear_entity_render for single-entity render updates"`.

### Задача 5 — `scripts/surface.lua`: `eb-cursor-tool` экипируется и в edit-режиме

**Файлы:** изменить `scripts/surface.lua`.

После Phase 1 patch `0.2.1` (см. текущий файл) курсор игрока освобождается (`swap_stack`/`clear_cursor`) в обоих режимах при входе, но инструмент `eb-cursor-tool` экипируется **только** в «new»-режиме:

```lua
  if not import_data then
    if player.clear_cursor() then
      player.cursor_stack.set_stack({ name = "eb-cursor-tool" })
    else
      player.print({"", "Blueprint Editor: could not equip the cursor tool (cursor full) -- entered editor without it."})
    end
  end
```

Это была осознанная граница Phase 1 (read-only, мутировать было нечем). Phase 2 нужен инструмент в обеих ветках — это и есть пункт роадмапа «cursor-tool equip».

- [ ] Заменить этот блок на безусловный (курсор к этому моменту уже гарантированно свободен — pinning/clear_cursor для `import_data` произошли раньше в этой же функции):

```lua
  if player.clear_cursor() then
    player.cursor_stack.set_stack({ name = "eb-cursor-tool" })
  else
    player.print({"", "Blueprint Editor: could not equip the cursor tool (cursor full) -- entered editor without it."})
  end
```

- [ ] Остальной `surface.lua` (пиннинг, god-режим, `teleport_out`) — без изменений, не трогать.
- [ ] Commit: `git add scripts/surface.lua && git commit -m "fix: equip eb-cursor-tool in edit mode too, not just new-session mode"`.

### Задача 6 — `data/custom-input.lua` + `locale/en/controls.cfg`: новые хоткеи

**Файлы:** изменить `data/custom-input.lua`, `locale/en/controls.cfg`.

- [ ] Заменить `data:extend({...})` в `data/custom-input.lua` (текущее содержимое — только `eb-toggle-editor`) на:

```lua
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
    key_sequence = "bracketright",
    consuming = "none",
  },
  {
    type = "custom-input",
    name = "eb-cycle-palette-prev",
    key_sequence = "bracketleft",
    consuming = "none",
  },
})
```

  `consuming = "none"` на всех — тот же выбор, что и для `eb-toggle-editor` в Phase 0 (ADR-0001 §5, «input-conflict avoidance» — не заявлять эксклюзивный захват клавиши поверх базовой игры/других модов).

- [ ] Дописать в `locale/en/controls.cfg` (после существующей строки `eb-toggle-editor=...`):

```
eb-rotate=Rotate entity under cursor
eb-delete=Delete entity under cursor
eb-pick-entity=Pick entity under cursor as current palette selection
eb-cycle-palette-next=Cycle palette selection (next)
eb-cycle-palette-prev=Cycle palette selection (previous)
```

- [ ] Commit: `git add data/custom-input.lua locale/en/controls.cfg && git commit -m "feat: add rotate/delete/pick/cycle custom-inputs"`.

### Задача 7 — `scripts/input.lua`: обработчики ввода → `canvas.lua`

**Файлы:** создать `scripts/input.lua`.

```lua
local state = require("scripts.state")
local canvas = require("scripts.canvas")
local render = require("scripts.rendering")

-- Ad-hoc минимальный список размещаемых сущностей (roadmap Phase 2: "A
-- minimal ad-hoc entity picker is fine here; the full palette UI is Phase
-- 5"). Без catalog.lua -- жёстко зашитый небольшой набор, покрывающий
-- typичные playtest-сценарии (пояс, инсертер, два вида сундуков, столб для
-- проверки wire bookkeeping, труба, сборочная машина). Полностью заменяется
-- catalog.lua в Phase 5 -- не переживает эту фазу как архитектура.
local PALETTE_ITEMS = {
  "transport-belt",
  "inserter",
  "iron-chest",
  "wooden-chest",
  "small-electric-pole",
  "pipe",
  "assembling-machine-1",
}

local function area_center(area)
  return {
    x = (area.left_top.x + area.right_bottom.x) / 2,
    y = (area.left_top.y + area.right_bottom.y) / 2,
  }
end

local function palette_index(name)
  for i, item_name in ipairs(PALETTE_ITEMS) do
    if item_name == name then
      return i
    end
  end
  return nil
end

local M = {}

-- Primary select (клик/драг с eb-cursor-tool) -- размещение. event.entities
-- на eb-canvas всегда пуст (см. phase-2-plan.md "Найденные API-факты" --
-- канвас никогда не содержит реальных сущностей), поэтому вся логика
-- опирается только на event.area.
function M.on_player_selected_area(event)
  if event.item ~= "eb-cursor-tool" then
    return
  end
  local session = state.get_session(event.player_index)
  if not session then
    return
  end
  if not session.selected_palette_item then
    game.get_player(event.player_index).print(
      {"", "Blueprint Editor: no entity selected -- press Q on an existing entity, or [ / ] to cycle the palette."})
    return
  end
  local internal_id = canvas.place_entity(session, session.selected_palette_item, area_center(event.area), 0)
  render.draw_entity(session, internal_id)
end

-- Alt-select -- удаление.
function M.on_player_alt_selected_area(event)
  if event.item ~= "eb-cursor-tool" then
    return
  end
  local session = state.get_session(event.player_index)
  if not session then
    return
  end
  local internal_id = canvas.find_entity_at(session, area_center(event.area))
  if not internal_id then
    return
  end
  render.clear_entity_render(session, internal_id)
  canvas.remove_entity(session, internal_id)
end

function M.on_rotate(event)
  local session = state.get_session(event.player_index)
  if not session then
    return
  end
  local internal_id = canvas.find_entity_at(session, event.cursor_position)
  if not internal_id then
    return
  end
  if canvas.rotate_entity(session, internal_id, 1) then
    render.clear_entity_render(session, internal_id)
    render.draw_entity(session, internal_id)
  end
end

function M.on_delete(event)
  local session = state.get_session(event.player_index)
  if not session then
    return
  end
  local internal_id = canvas.find_entity_at(session, event.cursor_position)
  if not internal_id then
    return
  end
  render.clear_entity_render(session, internal_id)
  canvas.remove_entity(session, internal_id)
end

function M.on_pick_entity(event)
  local session = state.get_session(event.player_index)
  if not session then
    return
  end
  local internal_id = canvas.find_entity_at(session, event.cursor_position)
  if not internal_id then
    return
  end
  session.selected_palette_item = session.entities[internal_id].raw.name
  game.get_player(event.player_index).print({"", "Blueprint Editor: selected " .. session.selected_palette_item})
end

local function cycle_palette(event, delta)
  local session = state.get_session(event.player_index)
  if not session then
    return
  end
  local current_index = palette_index(session.selected_palette_item) or 0
  local next_index = ((current_index - 1 + delta) % #PALETTE_ITEMS) + 1
  session.selected_palette_item = PALETTE_ITEMS[next_index]
  game.get_player(event.player_index).print({"", "Blueprint Editor: selected " .. session.selected_palette_item})
end

function M.on_cycle_palette_next(event)
  cycle_palette(event, 1)
end

function M.on_cycle_palette_prev(event)
  cycle_palette(event, -1)
end

-- ADR-0001 §5: "re-enforce it staying equipped via
-- on_player_cursor_stack_changed while a session is active" -- защита от
-- случайной потери инструмента (Q/скролл/дроп). Проверка ТЕКУЩЕГО стека
-- перед записью обязательна: on_player_cursor_stack_changed фирится и на
-- собственную script-запись (тот же тик, см. phase-2-plan.md "Найденные
-- API-факты"), без этой проверки -- бесконечный цикл событий.
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
  end
end

return M
```

- [ ] Не покрыто `busted` целиком (зависит от `game`/`LuaPlayer`/событий) — верификация Задача 9.
- [ ] Commit: `git add scripts/input.lua && git commit -m "feat: add input.lua wiring selection-tool and custom-inputs to canvas mutations"`.

### Задача 8 — `scripts/debug.lua` + `control.lua`: команда дампа сессии, регистрация событий

**Файлы:** создать `scripts/debug.lua`, изменить `control.lua`.

**`scripts/debug.lua`:**

```lua
local state = require("scripts.state")

local M = {}

-- Dev-only команда (ADR-0001 §10): serpent.block()-дамп текущей сессии
-- игрока в лог -- основной способ проверить entity_number/wire bookkeeping
-- (DoD-тест Phase 2), раз automated-тестов для API-зависимого кода нет
-- (docs/sdlc.md, "Тестирование"). CustomCommandData.player_index -- nil при
-- вызове из серверной консоли (подтверждённый API-факт) -- обрабатывается
-- явно, не молча падает на game.get_player(nil).
function M.dump_session(command)
  if not command.player_index then
    log("Blueprint Editor: eb-dump-session must be run by a player, not the server console.")
    return
  end
  local session = state.get_session(command.player_index)
  local player = game.get_player(command.player_index)
  if not session then
    player.print({"", "Blueprint Editor: no active editor session."})
    return
  end
  log(serpent.block(session, { name = "session" }))
  player.print({"", "Blueprint Editor: session dumped to the log."})
end

return M
```

- [ ] В `control.lua` добавить require-строки (после существующего `local render = require("scripts.rendering")`):

```lua
local input = require("scripts.input")
local debug_commands = require("scripts.debug")
```

  (`debug_commands`, не `debug` — `debug` уже занят стандартной Lua-библиотекой, тень на неё нежелательна даже в рамках одного файла.)

- [ ] Удалить весь спайковый блок (функция `on_selected_area` целиком и её `TODO(Phase 2)`-комментарий, и строку `script.on_event(defines.events.on_player_selected_area, on_selected_area)`) — заменяется полноценной обработкой ниже.

- [ ] Заменить блок регистрации событий в конце файла на:

```lua
script.on_init(on_init)
script.on_configuration_changed(on_configuration_changed)
script.on_load(on_load)
script.on_event(defines.events.on_player_joined_game, on_player_joined_game)
script.on_event("eb-toggle-editor", on_toggle_editor)
script.on_event(defines.events.on_player_selected_area, input.on_player_selected_area)
script.on_event(defines.events.on_player_alt_selected_area, input.on_player_alt_selected_area)
script.on_event(defines.events.on_player_cursor_stack_changed, input.on_cursor_stack_changed)
script.on_event("eb-rotate", input.on_rotate)
script.on_event("eb-delete", input.on_delete)
script.on_event("eb-pick-entity", input.on_pick_entity)
script.on_event("eb-cycle-palette-next", input.on_cycle_palette_next)
script.on_event("eb-cycle-palette-prev", input.on_cycle_palette_prev)

commands.add_command("eb-dump-session", {"", "Blueprint Editor: dump the current editor session to the log."}, debug_commands.dump_session)
```

- [ ] `on_init`/`on_configuration_changed`/`on_load`/`on_player_joined_game`/`on_toggle_editor` — без изменений, не трогать.
- [ ] Commit: `git add scripts/debug.lua control.lua && git commit -m "feat: wire input.lua handlers and eb-dump-session debug command into control.lua"`.

### Задача 9 — Dev-деплой и ручной playtest

Нет автотестов для API-зависимого кода этой фазы — верификация только через dev-loop + ручной прогон (`docs/sdlc.md`). Symlink мода уже существует. `data/custom-input.lua` меняется (новые прототипы) — **обязателен полный рестарт Factorio** (не только save-reload), в отличие от Phase 1.

- [ ] `busted spec/` зелёный целиком (`blueprint_io_spec.lua` + `canvas_spec.lua`) перед стартом playtest.
- [ ] Полный рестарт Factorio (не reload) — забирает новые `custom-input` прототипы.
- [ ] Playtest-чеклист «new»-режим (add/remove/rotate с нуля):
  - [ ] `Ctrl+Shift+K` с пустым курсором — вход, `eb-cursor-tool` в руке (регрессия Phase 0/1, теперь ещё и первый шаг Задачи 5 — до фикса тут ничего не менялось).
  - [ ] `]` несколько раз — сообщение в чате циклирует по всем 7 типам `PALETTE_ITEMS` и оборачивается на первый после последнего. `[` — цикл в обратную сторону.
  - [ ] Клик (primary select) на канвасе — размещается спрайт выбранного типа на позиции клика, привязанной к сетке (odd/even-центрирование заметно на глаз для 1×1 против многоклеточных сущностей типа `assembling-machine-1`).
  - [ ] `Q`, наведясь на уже размещённую сущность — палитра переключается на её тип (сообщение в чате подтверждает), следующий клик размещает такую же.
  - [ ] `R`, наведясь на размещённую сущность — спрайт визуально поворачивается на 90°; повторные `R` — ещё на 90° каждый раз, после 4 нажатий — назад к исходной ориентации.
  - [ ] `R` на сущности без вращения (если такая попадётся среди `PALETTE_ITEMS` — например, `iron-chest`) — не падает, просто ничего не меняет.
  - [ ] Alt-клик (alt-select) на размещённой сущности — исчезает с канваса.
  - [ ] `Delete`, наведясь на сущность — то же самое (альтернативный путь).
  - [ ] Alt-клик/`Delete` на пустом месте — ничего не происходит, ошибок в логе нет.
  - [ ] Уронить `eb-cursor-tool` из курсора вручную (например, кликнуть по другому предмету в панели быстрого доступа, если доступно, или `Q` в пустоту — если это в принципе достижимо в god-режиме без инвентаря) — инструмент должен вернуться в руку автоматически (`on_player_cursor_stack_changed`, Задача 7); если в god-режиме нет доступного способа вытолкнуть предмет из курсора вручную — зафиксировать как found fact в `phase-2-implementation.md`, не блокирует DoD (защитный код остаётся на будущее, где смена контроллера уже не god).
- [ ] Playtest-чеклист «edit»-режим + wire bookkeeping (основной DoD-тест фазы):
  - [ ] В обычном мире построить 3 малых силовых столба (`small-electric-pole`) в ряд на расстоянии, обеспечивающем авто-соединение проводом (стандартный radius). Подтвердить визуально в игре, что провода между всеми тремя реально протянуты.
  - [ ] Захватить область как blueprint (обычным способом, не через Blueprint Library — по итогу Phase 1 это read-only-безопасно, но лишний риск не нужен).
  - [ ] Взять blueprint в курсор, `Ctrl+Shift+K` — вход в edit-режим. Подтвердить, что `eb-cursor-tool` в руке (не пустой курсор, как было в Phase 1 — это и есть фикс Задачи 5).
  - [ ] `/eb-dump-session` в консоли — в логе (`factorio-current.log`) найти 3 `EntityRecord` для столбов, у каждого непустой `wires`, у крайних — по одной ссылке (на среднего), у среднего — на оба крайних. **Зафиксировать как found fact**, дублирует ли реальный blueprint провод в `wires` обеих сторон или только одной (см. "Найденные API-факты" выше) — по итоговому виду `session.entities[id].wires` до дедупликации в теории не отличить (дедуп уже применён), но само значение (по 1 связи с каждой стороны, не по 2) подтверждает, что сборка Задачи 2 сработала корректно независимо от того, как это было в сырых данных.
  - [ ] Alt-клик (или `Delete`) на среднем столбе — исчезает с канваса.
  - [ ] `/eb-dump-session` повторно — средний id **отсутствует** в `session.entities` целиком, и **отсутствует в `wires` обоих оставшихся столбов** (это и есть буквальный DoD-тест роадмапа).
  - [ ] Повторный `Ctrl+Shift+K` — выход, никаких ошибок в логе, blueprint (из пиннинга Phase 1) вернулся в руку как был (регрессия Phase 1 patch `0.2.1`).
- [ ] Спайк: подтвердить логом (временный `log(serpent.line(event))` внутри `input.on_player_selected_area`/`alt`, убрать после подтверждения — по образцу временного логирования Phase 0/1), что `event.entities`/`event.tiles` на `eb-canvas` действительно всегда `{}` — как и предсказано архитектурой (см. "Найденные API-факты"). Зафиксировать итог в `phase-2-implementation.md` независимо от результата.
- [ ] Зафиксировать все результаты (включая расхождения с ожиданиями) как черновик для `phase-2-implementation.md` (Задача 10).

### Задача 10 — Закрытие фазы: документация, версия, DoD

**Definition of Done фазы** (`docs/sdlc.md`) — выполнить по порядку:

- [ ] Прогнать `/code-review` на диффе ветки `phase-2-mutate`, закрыть найденные замечания.
- [ ] Создать `docs/phases/phase-2-implementation.md` по шаблону `docs/phases/TEMPLATE-implementation.md`: что сделано, решения по ходу (found facts из раздела «Найденные API-факты» выше — подтверждённые/опровергнутые playtest'ом; итог спайка `event.entities` на eb-canvas; итог спайка «дублирует ли raw-blueprint провод в wires обеих сторон»), результат playtest-чеклиста (Задача 9), известные ограничения (нет move, нет collision-детекции, ad-hoc палитра из 7 типов вместо каталога, фиксированный шаг вращения в четверть оборота).
- [ ] Обновить `docs/roadmap.md`: отметить Phase 2 завершённой (дата, версия `0.3.0`).
- [ ] Обновить `info.json.version` → `0.3.0`.
- [ ] Обновить `CHANGELOG.md` (новая секция `0.3.0`).
- [ ] Миграция в `scripts/migrations.lua` — уже добавлена в Задаче 1 (шаг `0.3.0`), доп. действий не требуется.
- [ ] `busted spec/` зелёный (Задачи 2, 3) — приложить итог прогона в implementation-doc.
- [ ] Commit: `git add docs/roadmap.md docs/phases/phase-2-implementation.md CHANGELOG.md info.json && git commit -m "docs: close out phase 2"`.
- [ ] Смержить `phase-2-mutate` в `main` (после ручного подтверждения пользователем — мерж не выполняется автоматически).

## Спайки

- [ ] **`event.entities`/`event.tiles` пусты на `eb-canvas`** (ADR-0001 §1 архитектурное следствие, не буквально проверенный факт до этой фазы) — подтвердить логом в Задаче 9. Если ложно (что-то там всё-таки появляется) — это ломает всю модель Задачи 7 (которая опирается только на `event.area`) и требует пересмотра, зафиксировать как блокер, не как found fact, если обнаружится обратное.
- [ ] **Дублирование `BlueprintWire` на обеих сторонах связи в реальных данных игры** — не задокументировано, сборка Задачи 2 устойчива к обоим исходам, но сам исход стоит зафиксировать (любопытный факт для Phase 4/6, где вновь придётся иметь дело с сырым форматом на экспорте/создании).
- [ ] **`on_player_cursor_stack_changed` re-equip без event storm** — теоретически обосновано (see «Найденные API-факты»), подтвердить playtest'ом, что нет видимого мерцания/лишних сообщений в логе при обычном использовании инструмента (клики самим `eb-cursor-tool` тоже могут менять cursor_stack? — на практике selection-tool клик не меняет содержимое курсора, только производит событие area-select, так что вряд ли пересекается, но стоит понаблюдать).

## Открытые вопросы

- **Почему move не входит в Phase 2, хотя ADR-0001 §6 упоминает его в общей архитектуре мутаций.** Роадмап Phase 2 называет буквально три глагола («Add/remove/rotate»), четвёртый (move) не упомянут вовсе ни в этой фазе, ни явно в последующих. Trade-off: без move relocate-редактирование требует remove+place (теряет `wires` перемещаемой сущности, если она была подключена — ещё один аргумент за то, что move в UI без специального сохранения `wires` через операцию был бы footgun; полноценная реализация move обязана переносить `wires` без потерь, что requires отдельного проектирования, не тривиальное дополнение этой фазы). Если понадобится раньше Phase 5, потребует явного решения (возможно, отдельного ADR-дополнения, раз меняет модель мутаций, а не только добавляет функцию).
- **Почему `wires` дедуплицируются на импорте вместо доверия сырым данным.** Раз API не документирует, дублирует ли Factorio провод на обеих сторонах, сборка обязана быть идемпотентной относительно обоих вариантов — иначе результат Phase 2 зависел бы от недокументированного поведения движка, что нарушило бы воспроизводимость (тот же blueprint должен давать тот же `session.entities` независимо от версии игры/формата, в разумных пределах).
- **Почему `find_entity_at` не detected для тайлов, только для сущностей.** Роадмап Phase 2 — только сущности (тайлы: Phase 3). Alt-select/`Delete`/`R`/`Q` целятся исключительно в `session.entities`; удаление/вращение тайлов вне скоупа этой фазы намеренно.
