# Phase 4 — Сохранение blueprint — план

- Ветка фазы: `phase/4-save`
- Milestone: `v0.5` (зонтичный issue — #2)
- Базовая версия перед стартом: `info.json` `0.4.0`; по завершении фазы — `0.5.0` (`docs/sdlc.md`, «Версионирование»)
- Спека: [`docs/adr/0001-baseline-architecture.md`](../adr/0001-baseline-architecture.md) (разделы 6 — экспорт и регрессия no-op, 8 — Blueprint I/O, 10 — real-paste validation), [`docs/roadmap.md`](../roadmap.md) (Phase 4)

## Область фазы

Из `docs/roadmap.md`: «`export_to_entities_array`, `save_new_blueprint`, `save_back_to_stack`. Test: new blueprint round-trip, no-op re-export regression check, wired-delete real-paste verification.»

До этой фазы редактор был «односторонним»: сессия импортирует blueprint (Phase 1), игрок правит его на канвасе (Phase 2–3), а при выходе всё редактирование пропадает — исходный blueprint возвращается в руку нетронутым (`surface.teleport_out`). Новизна фазы — **обратный путь данных**: `Session.entities`/`Session.tiles` → массивы `BlueprintEntity`/`Tile` → реальный предмет-blueprint или запись Blueprint Library.

Сценарий фазы (детали взаимодействия — развилки, см. «Вопросы владельцу»):

1. **Edit-режим, исходник — blueprint из инвентаря** (`origin.kind == "pinned_stack"`). Игрок правит и сохраняет: отредактированные данные записываются в тот же самый pinned-стек, затем он, как и раньше, возвращается в курсор. Снаружи это выглядит как «blueprint в руке изменился».
2. **Edit-режим, исходник — запись Blueprint Library** (`origin.kind == "cursor_record"`). В `2.0.77` у `LuaRecord` есть `set_blueprint_entities`/`set_blueprint_tiles` (см. «Найденные API-факты») — запись можно обновить на месте, если она `valid_for_write`. Если нет (запись из «My blueprints» или превью) — сохраняем как **новый** blueprint в руку и говорим об этом игроку.
3. **New-режим** (вход с пустым курсором). При сохранении создаётся новый предмет `blueprint`: в курсор, если он пуст; иначе в основной инвентарь; иначе `spill_item_stack` под ноги (ADR-0001 §8(a).2) — тот же каскад возврата, что уже реализован для pinned-стека в `teleport_out`.
4. **Выход без сохранения** — всегда доступен; исходник остаётся как был (сегодняшнее поведение).

Три сценария объединяет единый экспорт: `blueprint_io.export_to_entities_array(session)` (чистая логика, TDD) строит массив `BlueprintEntity` по ADR-0001 §6 — ремап `internal_id → entity_number`, сборка `wires` в позиционные кортежи `BlueprintWire`, `raw` сущностей передаётся нетронутым (preserve-unknown-fields); `export_to_tiles_array(session)` — то же для тайлов.

**Явно вне области Phase 4:**

- **GUI сохранения** (форма с именем и 4 пикерами иконок из ADR-0001 §8(a).3) — Phase 5 вместе с `palette_gui.lua`. В этой фазе `label`/`preview_icons`/snap-метаданные только **переносятся** с исходника, не редактируются (см. вопрос 4).
- **Браузер библиотеки/инвентаря** для выбора blueprint'а — не MVP (ADR-0001 §8(b).1), вход по-прежнему через курсор.
- **Редактирование проводов** — Phase 6; эта фаза лишь корректно экспортирует уже существующую бухгалтерию `EntityRecord.wires`.
- **Snap-to-grid round-trip с проверкой в игре под нагрузкой** — Phase 7 (roadmap); здесь — только перенос трёх полей как есть.
- **Отмена/история** (undo внутри сессии) — нет в roadmap, не делаем.
- **Книги**: исходником остаётся текущая страница книги (как в Phase 1, `unwrap_actual_blueprint`); перезапись страницы книги в руке через pinned-стек невозможна без отдельной работы — см. вопрос 3.

## Global Constraints

- `factorio_version = "2.0"`; API-факты — только `lua-api.factorio.com/2.0.77/` (`docs/sdlc.md`, «Версия Factorio и проверка API-фактов»).
- `storage` — только через `scripts/state.lua`; поля уже полученного `Session` читаются/пишутся напрямую (граница из `phase-1-plan.md`/`phase-2-plan.md`).
- **Все новые поля аддитивны и nil-safe** (`Session.origin.record`, `Session.origin.writable`) — шаг миграции с преобразованием не требуется (ADR-0001 §4). Активных сессий с `cursor_record`-origin в сохранениях от `0.4.0` быть не может на практике (сессия живёт только пока игрок на канвасе), но код обязан переносить `origin.record == nil` как «не писать в запись, сохранить как новый».
- **Preserve-unknown-fields** (ADR-0001 §6): экспорт делает **shallow copy** `raw` и перекладывает только `entity_number` и `wires`; остальные поля (`recipe`, `control_behavior`, `items`, `tags`, `mirror`, `quality`…) уходят в blueprint нетронутыми. `raw` в `Session` при экспорте **не мутируется** (сессия должна остаться валидной, если сохранение провалилось).
- **Pure-logic TDD обязателен** (`docs/sdlc.md`, DoD п.6) для `export_to_entities_array`, `export_to_tiles_array`, и вспомогательной `build_export_wires`.
- **Fail-fast**: `wires` со ссылкой на `target_internal_id`, которого нет в `session.entities`, — `error()` (нарушение инварианта `canvas.remove_wire_references`, ADR-0001 §6), а не молчаливый пропуск провода.
- **Не терять данные игрока**: любая запись в предмет/запись выполняется **до** возврата pinned-стека в курсор и **после** успешного экспорта; при ошибке записи сессия не закрывается, игроку печатается сообщение, исходник остаётся как был. Ошибки API (`set_blueprint_entities` упал на невалидных данных) ловятся `pcall` только в этой одной точке — чтобы не потерять pinned-стек; текст ошибки — в лог и игроку.
- **God-контроллер имеет собственный курсор** (`phase-1-implementation.md`, «Известные ограничения»): любая операция с `player.cursor_stack` для нового blueprint'а — только **после** `teleport_out` восстановил character-контроллер. Поэтому new-режим не трогает курсор напрямую, а кладёт готовый blueprint во временный `game.create_inventory(1)` и отдаёт его тем же путём, что pinned-стек (см. Задачу 3).
- **Явный бюджет производительности**: экспорт — O(N + W) по сущностям и проводам, без render-объектов; константа не нужна, но `export_to_entities_array` логирует `log()` одну строку с размерами (N сущностей, W проводов, T тайлов) при `N > ENTITY_RENDER_WARN_THRESHOLD` — тем же порогом, что рендер.
- Для API-зависимого кода (`save_*`, `write_blueprint_data`, обработчики в `control.lua`) автотестов нет — верификация через dev-loop и playtest-чеклист (Задача 5).

## Найденные API-факты (проверены на `https://lua-api.factorio.com/2.0.77/`)

1. **`LuaRecord` в `2.0.77` умеет писать blueprint-данные**: `set_blueprint_entities(entities)`, `set_blueprint_tiles(tiles)`, `clear_blueprint()`, `is_blueprint_setup()`, RW-атрибуты `preview_icons`, `blueprint_snap_to_grid`, `blueprint_absolute_snapping`, `blueprint_position_relative_to_grid`, `blueprint_description`. Это снимает оговорку ADR-0001 §8(b).7 («Blueprint Library — задокументировать как ограничение»): сохранение обратно в запись библиотеки **возможно**, roadmap Phase 7 (`Blueprint Library resolution`) закрыт полностью, а не только для чтения.
2. **`LuaRecord.valid_for_write`** (R, boolean): «A record is invalid for write if it is a BlueprintRecord preview or if it is in the "My blueprints" shelf». Описание класса: записи в «My blueprints» — read-only, в «Game blueprints» — read/write. Следствие: для записи из личной полки игрока обновление на месте невозможно даже технически — только «сохранить как новый».
3. **У `LuaRecord` нет `label`** (подтверждено повторно — тот самый факт, что крашил Phase 1 при чтении по `/latest/`). Есть `blueprint_description` (RW string). Имя записи библиотеки через API `2.0.77` не читается и не пишется.
4. **`LuaItemStack` (через `LuaItemCommon`)**: `set_blueprint_entities(entities: array[BlueprintEntity])` — «Set new entities to be a part of this blueprint»; `set_blueprint_tiles(tiles: array[Tile])`; `label` (RW `string?`, «Only valid on an ItemWithLabel»), `label_color`, `preview_icons` (RW `array[BlueprintSignalIcon]?`; «An item that doesn't have icons returns nil on read and throws error on write»), `default_icons` (R), `blueprint_snap_to_grid`/`blueprint_position_relative_to_grid` (RW `TilePosition?`, `nil` = выключено), `blueprint_absolute_snapping` (RW boolean), `blueprint_description`, `clear_blueprint()`, `is_blueprint_setup()`, `export_stack() → string`. Свойства `blueprint_icons` **нет** (как и зафиксировано в Phase 1). Документация **не описывает** требований к `entity_number` (плотность, порядок) и к дублированию проводов — см. «Спайки».
5. **`BlueprintEntity`**: обязательны `entity_number`, `name`, `position`; `direction` — «only present for entities that can face in different directions and when the entity is not facing north»; `wires :: array[BlueprintWire]?`; плюс `mirror`, `quality`, `items`, `tags`, `burner_fuel_inventory` и прототип-специфичные поля. Для no-op регрессии это значит: сущности, размещённые палитрой с `direction = 0`, после записи и повторного чтения могут вернуться **без** поля `direction` — сравнение в playtest ведётся по `export_stack()`, а в busted-тесте — по нормализованным таблицам (`direction == 0` ≡ отсутствию).
6. **`BlueprintWire :: {uint32, defines.wire_connector_id, uint32, defines.wire_connector_id}`** — позиционный кортеж `{source_entity_number, source_wire_connector_id, target_entity_number, target_wire_connector_id}` (подтверждает факт Phase 2 и форму, с которой работает `build_import_data`).
7. **`Tile :: {name: string, position: TilePosition}`** — ровно то, что лежит в `TileRecord.raw`; экспорт тайлов — передача `raw` как есть.
8. **`BlueprintSignalIcon :: {signal: SignalID, index: uint32 [1..4]}`** — форма `preview_icons`; переносится как есть, без разбора.
9. **`storage` допускает «References to Factorio's LuaObjects»** (auxiliary/storage): хранить `LuaRecord` в `Session.origin.record` формально разрешено, как уже хранится `LuaInventory` в `origin.inventory`. Что `LuaRecord` останется `valid` после `clear_cursor()` и после save/load — документацией **не покрыто**, проверяется спайком S1.
10. **`LuaPlayer.cursor_record`** — R-only; `LuaPlayer.insert(items) → uint32`; `LuaInventory.find_empty_stack(item?) → LuaItemStack?, uint32?`; `LuaSurface.spill_item_stack{position, stack, enable_looted?, ...} → array[LuaEntity]` — всё, что нужно каскаду «курсор → инвентарь → земля», в `2.0.77` есть; `spill_item_stack` уже используется в `teleport_out`.

## Файлы

| Файл | Назначение |
|---|---|
| `scripts/blueprint_io.lua` | Изменить: `export_to_entities_array`, `export_to_tiles_array`, `build_export_wires`, `stable_entity_order` (чистая логика, TDD); `write_blueprint_data`, `save_back_to_stack`, `save_new_blueprint`, `save_session` (API-зависимые); `import_from_stack` — запоминать `LuaRecord` и `valid_for_write` в `origin` |
| `spec/blueprint_io_spec.lua` | Изменить: тесты экспорта, round-trip `build_import_data ∘ export`, no-op регрессия |
| `scripts/surface.lua` | Изменить: `teleport_in` — не терять `origin.record`; `teleport_out` — принять `origin.kind == "pinned_stack"` для new-режима (уже работает, проверить комментарии/сообщения) |
| `scripts/state.lua` | Изменить: комментарий к форме `Session.origin` (новые поля `record`, `writable`), без новых accessor'ов |
| `control.lua` | Изменить: обработчики `eb-save-and-exit` / `eb-discard` (по решению вопроса 1), вызов `blueprint_io.save_session` перед `surface.teleport_out` |
| `data/custom-input.lua` | Изменить: новый custom-input (по решению вопроса 1) |
| `locale/en/controls.cfg` | Изменить: подписи новых/изменённых клавиш |
| `scripts/debug.lua` | Изменить (опционально): `/eb-dump-export` — дамп результата экспорта без записи, для разбора по логу |
| `docs/phases/phase-4-implementation.md`, `docs/roadmap.md`, `CHANGELOG.md`, `info.json` | Закрытие фазы |

## Задачи

Каждая задача — отдельный issue (milestone `v0.5`, метка `группа/Импорт и экспорт`), ветка и PR в `phase/4-save`. Граф зависимостей и общие файлы:

```
Задача 1 (blueprint_io.lua, spec)  ──┐
                                      ├─▶ Задача 3 (blueprint_io.lua, surface.lua, state.lua) ─▶ Задача 4 (control.lua, blueprint_io.lua) ─▶ Задача 5 (playtest) ─▶ Задача 6 (закрытие)
Задача 2 (data/custom-input.lua,     │
          locale, control.lua) ──────┘
```

- **Параллельно**: Задачи 1 и 2 — нет общих файлов (Задача 2 трогает `control.lua` только регистрацией пустых обработчиков-заглушек, Задача 1 — только `blueprint_io.lua`/`spec`).
- **Последовательно**: Задача 3 после 1 (общий `blueprint_io.lua`); Задача 4 после 2 и 3 (общие `control.lua` и `blueprint_io.lua`); 5 и 6 — строго в конце.
- Задача 2 блокируется решением владельца по вопросу 1 — до ответа её не запускать; Задача 1 от ответов не зависит и запускается сразу после принятия плана.

### Задача 1 — `scripts/blueprint_io.lua`: чистый экспорт сессии в массивы (TDD)

- Файлы: `scripts/blueprint_io.lua`, `spec/blueprint_io_spec.lua`
- Блокируется: —
- Метки: `группа/Импорт и экспорт`, `Fable 5.1` (провода и `entity_number` — ADR-0001 §6, «сложная» зона по `agent-orchestration.md`)
- Что сделать:
  - `M.stable_entity_order(entities)` → массив `internal_id` по возрастанию (детерминированный порядок; `pairs` не гарантирует).
  - `M.build_export_wires(entities, export_map)` → для каждой сущности массив `BlueprintWire` `{own_number, this_connector_id, target_number, target_connector_id}`. **Каждый уникальный провод эмитится ровно один раз** — на той стороне, чей `entity_number` меньше (при равенстве — по `connector_id`); так экспорт не зависит от того, лежит ли провод в `wires` обеих сторон (import кладёт в обе) и воспроизводит один-кортеж-на-провод. Решение подлежит проверке спайком S2; если игра на вставке ожидает провод с обеих сторон, переключение — одна константа/ветка в этой функции. `target_internal_id` вне `entities` — `error()` с обоими id в тексте.
  - `M.export_to_entities_array(session_entities)` → `array[BlueprintEntity]`: shallow copy `raw`, `entity_number = export_map[id]`, `wires` = результат выше или `nil`, если проводов нет (не пустая таблица — чтобы не раздувать blueprint и совпадать с формой импорта). Позиции **не трогаются**: `raw.position` уже в blueprint-пространстве (`canvas.place_entity` переводит клик через `to_local_position` при размещении), `canvas_offset`/`blueprint_center` в экспорте не участвуют — тест фиксирует это явно.
  - `M.export_to_tiles_array(session_tiles)` → `array[Tile]` в детерминированном порядке (сортировка по `position.y`, затем `position.x`); `raw` как есть.
  - Функции принимают голые таблицы (`session.entities`, `session.tiles`), не `Session` — чтобы тесты не собирали сессию целиком.
- Тесты (красные → зелёные, по образцу `describe("blueprint_io.build_import_data")`):
  - плотная нумерация `1..N` в порядке `internal_id` при «дырявых» id (после удалений);
  - `raw` не мутируется и все неизвестные поля (`recipe`, `control_behavior`, `tags`, вложенные таблицы) доходят до результата той же ссылкой/значением;
  - провод между двумя сущностями эмитится один раз, с правильными `connector_id` на обеих позициях кортежа, и `wires == nil` у сущности без проводов;
  - провод, лежащий в `wires` только одной стороны (наследие/ручная сборка), экспортируется так же, как двусторонний;
  - `error()` на висячей ссылке;
  - **round-trip**: `build_import_data(export(build_import_data(X)))` даёт ту же структуру сущностей и проводов (с точностью до `internal_id`);
  - **no-op регрессия** (ADR-0001 §6): для `X` с плотной нумерацией и уникальными проводами `export(build_import_data(X))` **равен** `X` поэлементно (`assert.are.same`), включая порядок; для `X`, где игра продублировала провод на обеих сторонах, — равен после нормализации проводов в множество симметричных ключей;
  - тайлы: порядок детерминирован, `position`/`name` не меняются, пустая сессия → `{}`.
- Критерии приёмки: `busted` зелёный целиком (существующие 31 + новые); в `blueprint_io.lua` нет обращений к `game`/`prototypes`/`storage` в новых чистых функциях; комментарий у `build_export_wires` ссылается на S2.

### Задача 2 — Клавиши сохранения/выхода: `data/custom-input.lua`, `locale`, заглушки в `control.lua`

- Файлы: `data/custom-input.lua`, `locale/en/controls.cfg`, `control.lua` (только регистрация обработчиков-заглушек, печатающих сообщение)
- Блокируется: ответ владельца на вопрос 1 (какая клавиша что делает)
- Метки: `группа/Холст и ввод`, `Sonnet 5.5`, `playtest`
- Что сделать (при рекомендованном варианте вопроса 1): новый custom-input `eb-discard` (`CONTROL + SHIFT + Q`, `consuming = "none"`) — «выйти без сохранения»; `eb-toggle-editor` получает подпись «Toggle Blueprint Editor (save on exit)». Имя клавиши проверять по `doc-html/prototype-api.json` установленной игры (урок Phase 2: `bracketright` не существует, нужен `RIGHTBRACKET`). В `control.lua` — обработчик `eb-discard`, который делает то, что сейчас делает выход по `eb-toggle-editor` (без сохранения); `on_toggle_editor` в ветке выхода пока без изменений (сохранение подключает Задача 4).
- Критерии приёмки: после полного рестарта игры (`data.lua` изменён) обе клавиши видны в настройках управления с правильными подписями; `eb-discard` выводит из редактора без сохранения; никаких ошибок в логе. Пункт playtest-чеклиста: «клавиши видны и назначены».

### Задача 3 — Запоминание исходника: `origin.record` / `origin.writable` и временный инвентарь для new-режима

- Файлы: `scripts/blueprint_io.lua` (`import_from_stack`), `scripts/surface.lua` (`teleport_in`, `teleport_out`), `scripts/state.lua` (комментарий к `Session.origin`)
- Блокируется: Задача 1 (общий файл `blueprint_io.lua`)
- Метки: `группа/Импорт и экспорт`, `Sonnet 5.5`, `playtest`
- Что сделать:
  - `import_from_stack` для `source_kind == "cursor_record"` возвращает `origin = { kind = "cursor_record", record = source, writable = source.valid_for_write }`; для записи из библиотеки читать `preview_icons` и три snap-поля (они у `LuaRecord` есть — факт 1), `label` — **не читать** (факт 3).
  - `teleport_in` при `cursor_record` — `player.clear_cursor()` как сейчас, `origin.record` сохраняется в сессии (спайк S1: после `clear_cursor()` ссылка остаётся `valid`?). Если на следующем шаге `record.valid == false` — лог `eb playtest:` и `origin.writable = false`.
  - `teleport_out` уже умеет вернуть `origin.kind == "pinned_stack"` в курсор/инвентарь/на землю — проверить, что ветка не завязана на `mode == "edit"` и годится для new-режима, когда Задача 4 подложит в `origin` временный инвентарь с новым blueprint'ом; сообщение для `cursor_record` расширить вариантом «запись в библиотеке обновлена» / «запись read-only, blueprint сохранён в руку» (текст — после Задачи 4, здесь заготовка).
- Критерии приёмки: `/eb-dump-session` после входа из библиотеки показывает `origin.kind = "cursor_record"`, `writable` true/false соответственно для «Game blueprints»/«My blueprints»; `busted` зелёный (чистые функции не менялись); вход/выход без сохранения не регрессировал для всех трёх источников. Пункты playtest-чеклиста — S1.

### Задача 4 — `blueprint_io.save_*` и подключение к выходу в `control.lua`

- Файлы: `scripts/blueprint_io.lua`, `control.lua`, `scripts/surface.lua` (сообщения при выходе), `scripts/debug.lua` (опционально `/eb-dump-export`)
- Блокируется: Задачи 2 и 3
- Метки: `группа/Импорт и экспорт`, `Fable 5.1`, `playtest`
- Что сделать:
  - `M.write_blueprint_data(target, export, metadata)` — единая запись в `LuaItemStack` **или** `LuaRecord` (у обоих одинаковые `set_blueprint_entities`/`set_blueprint_tiles`/`preview_icons`/snap-поля): `set_blueprint_entities(entities)`, `set_blueprint_tiles(tiles)`; затем `preview_icons`, `blueprint_snap_to_grid`, `blueprint_absolute_snapping`, `blueprint_position_relative_to_grid` — **только если** в `metadata` они не `nil` (не затирать значения исходника отсутствием данных); `label` — только для `LuaItemStack` (`metadata.label ~= nil`). Пустой экспорт (нет ни сущностей, ни тайлов) — см. вопрос 5. Вызов обёрнут `pcall`; ошибка → `false, message`.
  - `M.save_back_to_stack(session)` — `origin.kind == "pinned_stack"`: цель `origin.inventory[1]`; проверка `valid_for_read and is_blueprint`; запись **до** возврата стека в курсор (стек в mod-owned инвентаре, контроллер не важен).
  - `M.save_back_to_record(session)` — `origin.kind == "cursor_record"` и `origin.writable` и `origin.record.valid`: запись в `origin.record`. Иначе — `save_new_blueprint` с сообщением игроку (вопрос 2).
  - `M.save_new_blueprint(session, player)` — new-режим (и фолбэк выше): `local inv = game.create_inventory(1); inv[1].set_stack{name="blueprint"}`; `write_blueprint_data(inv[1], …)`; `session.origin = { kind = "pinned_stack", inventory = inv }` — дальше готовый blueprint доставляет существующий каскад `teleport_out` (курсор → `spill`), который работает уже после восстановления character-контроллера (ограничение god-курсора). Если желателен каскад «курсор → инвентарь → земля» в точности по ADR §8(a).2 — добавить `player.insert`-шаг между swap и spill в `teleport_out` (одно место, общее для всех источников).
  - `M.save_session(player, session)` — диспетчер по `origin.kind`/`mode`; возвращает `ok, message`; на `false` сессия **не закрывается**, игрок получает сообщение, может исправить или выйти через `eb-discard`.
  - `control.lua`: ветка выхода `on_toggle_editor` → `save_session`, при `ok` — `clear_session_renders` + `teleport_out`; `eb-discard` — выход без сохранения (из Задачи 2).
  - Временное логирование `eb playtest:` (`docs/sdlc.md`): размеры экспорта, цель записи (`stack`/`record`/`new`), `export_stack()` до и после записи для pinned-стека, результат `pcall`.
- Критерии приёмки (всё — в игре, Задача 5): сохранение в pinned-стек, в запись «Game blueprints», фолбэк для «My blueprints», новый blueprint из new-режима; ошибка записи не теряет исходник; `busted` зелёный.

### Задача 5 — Dev-деплой и ручной playtest

- Файлы: — (лог `factorio-current.log`; временное логирование добавлено Задачей 4)
- Блокируется: Задача 4
- Метки: `группа/Процесс`, `Sonnet 5.5`, `playtest`
- **Полный рестарт Factorio обязателен** — Задача 2 меняет `data/custom-input.lua`.
- Playtest-чеклист (владелец прогоняет один раз, отдаёт лог):
  - [ ] Клавиши: в настройках управления видны `eb-toggle-editor` (с новой подписью) и `eb-discard`.
  - [ ] **Round-trip нового blueprint** (roadmap): пустой курсор → `Ctrl+Shift+K` → поставить 3–4 сущности (в т. ч. две с направлением ≠ north) и 2 тайла → сохранить. В руке новый blueprint; его превью совпадает с канвасом. Войти в редактор с ним снова — всё на месте, позиции и направления те же (`/eb-dump-session` до и после — одинаковые `raw`, кроме `entity_number`/`direction=0`).
  - [ ] **No-op регрессия** (ADR-0001 §6): взять реальный сложный blueprint (сборочные с рецептами, инсертеры с фильтрами, комбинаторы с проводами, модули) → войти → ничего не менять → сохранить. В логе `eb playtest:` строки `export_stack` до/после **идентичны**. Отличие — не обязательно баг (например, игра дедуплицировала провод), но каждое разобрать и зафиксировать в implementation.md.
  - [ ] **Реальная вставка с удалённым проводным столбом** (roadmap, DoD Phase 2): blueprint с ≥3 столбами в цепочке и красным проводом к комбинатору → удалить средний столб → сохранить → вставить в мир: ghost-превью без ошибок, оставшиеся столбы не ссылаются на удалённый, провода между выжившими сущностями на месте. Для контроля — `/eb-dump-session` перед сохранением.
  - [ ] **Изменённый blueprint в руке**: добавить сущность и тайл, повернуть одну сущность → сохранить → в руке тот же предмет с изменениями; `label`, иконки и snap-to-grid (взять исходник со включённым snap) не потерялись.
  - [ ] **Blueprint Library, «Game blueprints»**: перетащить запись → войти → изменить → сохранить. Запись в библиотеке обновлена; сообщение при выходе говорит об этом. (S1, S3)
  - [ ] **Blueprint Library, «My blueprints»**: то же; сообщение «запись read-only, сохранено как новый blueprint», новый предмет в руке, запись не тронута. (S3)
  - [ ] **Книга в руке**: текущая страница редактируется; сохранение — по решению вопроса 3; в любом случае книга не пропала и не повреждена.
  - [ ] **Выход без сохранения** (`eb-discard`) для всех трёх источников — исходник как был, курсор/библиотека не тронуты.
  - [ ] **Пустой холст**: new-режим, ничего не поставлено → сохранить — поведение по вопросу 5, без ошибок в логе.
  - [ ] **Полный курсор и полный инвентарь** в new-режиме: blueprint падает на землю (`spill`), не теряется.
  - [ ] **Save/load во время сессии** (S1): войти из библиотеки, сохранить игру, загрузить, сохранить blueprint — запись обновилась, либо (если `record.valid == false`) сработал фолбэк в новый blueprint с сообщением.
  - [ ] Входы/выходы Phase 1–3 не регрессировали (рендер, палитра, удаление).
- Критерии приёмки: все пункты подтверждены по логу; расхождения занесены в черновик implementation.md; временное логирование убрано отдельным PR (`chore: remove temporary playtest diagnostic logging`).

### Задача 6 — Закрытие фазы: Definition of Done

- Файлы: `docs/phases/phase-4-implementation.md` (новый), `docs/roadmap.md`, `CHANGELOG.md`, `info.json`
- Блокируется: Задача 5
- Метки: `группа/Релиз`, `документация`, `Sonnet 5.5`
- По `docs/sdlc.md`, «Definition of Done фазы»:
  - [ ] `/code-review` на диффе `phase/4-save` относительно `main`, замечания закрыты.
  - [ ] `docs/phases/phase-4-implementation.md` по `TEMPLATE-implementation.md`: что сделано, API-факты (включая результаты спайков S1–S3 и трудности из комментариев к issue фазы), решения по ходу, итог playtest-чеклиста, известные ограничения (нет GUI метаданных, `label` у записей библиотеки, книги).
  - [ ] `docs/roadmap.md`: Phase 4 завершена (дата, `0.5.0`); у Phase 7 убрать/уточнить «Blueprint Library resolution», если S1/S3 подтвердили запись в библиотеку.
  - [ ] `info.json.version` → `0.5.0`; шаг миграции не нужен (поля аддитивны), что зафиксировать в implementation.md; при желании — пустой шаг `0.5.0` **не добавлять** (`migrations.run` и так переставит `mod_version`).
  - [ ] `CHANGELOG.md`: секция `0.5.0`.
  - [ ] Подтвердить, что PR с удалением playtest-логирования смёржен и в ветке фазы не осталось `eb playtest:`.
  - [ ] `busted` и CI `test` зелёные на `phase/4-save`; все issue milestone `v0.5` закрыты, кроме #2.
  - [ ] Финальный PR `phase/4-save` → `main` с `Closes #2` — merge делает владелец.

## Спайки

Непроверяемое по документации `2.0.77` — проверяется в игре внутри задач 3–5, результат фиксируется в implementation.md.

- [ ] **S1 — `LuaRecord` как ссылка в `storage`** (Задача 3; ADR-0001 §4, §8(b).3). Остаётся ли `origin.record.valid == true` после `player.clear_cursor()`, после save/load и после того, как игрок открыл библиотеку и переключил полку. Документация разрешает хранить LuaObjects, но не описывает жизненный цикл `LuaRecord`. Если ссылка умирает — фолбэк «сохранить как новый» с сообщением, ограничение в implementation.md.
- [ ] **S2 — один или два кортежа на провод** (Задачи 1 и 5; ADR-0001 §6). `get_blueprint_entities()` у реального blueprint'а: лежит ли провод в `wires` обеих сущностей или одной? Принимает ли `set_blueprint_entities` провод, перечисленный дважды, и даёт ли один кортеж полный провод на вставке? Проверка — пункты no-op регрессии и real-paste в Задаче 5; по итогу `build_export_wires` остаётся «один раз» или переключается на «обе стороны» (одна ветка кода, тесты правятся вместе).
- [ ] **S3 — `valid_for_write` на практике** (Задачи 3–5). Что реально возвращает `valid_for_write` для записи, перетащенной из «Game blueprints» и из «My blueprints» в мультиплеере/одиночке; падает ли `set_blueprint_entities` на записи с `valid_for_write == false` ошибкой (ловится `pcall`) или молча ничего не делает.
- [ ] **S4 — требования `set_blueprint_entities` к `entity_number`** (Задача 5). Документация молчит; экспорт даёт плотную нумерацию `1..N` в порядке `internal_id` — самый консервативный вариант, поэтому отдельного эксперимента не нужно, но если round-trip покажет перенумерацию/перестановку игрой — зафиксировать.

## Вопросы владельцу

Нумерованным списком, у каждого — рекомендация. Владелец отвечает в ревью PR плана.

1. **Как игрок запускает сохранение?** Варианты: (а) `eb-toggle-editor` при выходе **сохраняет**, новая клавиша `eb-discard` (`Ctrl+Shift+Q`) — выход без сохранения; (б) наоборот — выход как сейчас (без сохранения), новая клавиша `eb-save` сохраняет и выходит; (в) GUI с кнопками «Сохранить / Сохранить как новый / Отмена» при выходе. **Рекомендация — (а).** Игрок вошёл в редактор ради правок — потеря правок по привычному `Ctrl+Shift+K` хуже, чем лишнее сохранение (которое для неизменённой сессии даёт идентичный blueprint — это и проверяет no-op регрессия). (в) — это уже Phase 5 (`palette_gui.lua`), не тащить GUI раньше срока; (б) оставляет «тихую потерю» дефолтом.
2. **Исходник — запись Blueprint Library.** Варианты: (а) писать в запись на месте, если `valid_for_write`, иначе — новый blueprint в руку с сообщением; (б) всегда новый blueprint в руку, библиотеку не трогать; (в) всегда писать в запись, при `valid_for_write == false` — ошибка. **Рекомендация — (а):** API `2.0.77` это позволяет (факт 1–2), игрок получает то, что ожидает («изменил запись»), а read-only полка «My blueprints» всё равно требует фолбэка. Цена — спайки S1/S3; при их провале (а) деградирует в (б) без изменения плана.
3. **Исходник — страница книги.** Сейчас импорт разворачивает книгу до текущей страницы; pinned-стек — это **вся книга**. Варианты: (а) писать в активную страницу книги внутри pinned-стека (`get_inventory(defines.inventory.item_main)[active_index]`, тот же путь, что при импорте) и для книги-записи — в `get_selected_record(player)`; (б) книги в этой фазе не сохранять: предупреждение при входе и всегда «новый blueprint в руку». **Рекомендация — (а) для книги-предмета, (а) для книги-записи при `valid_for_write`**: разворачивание уже написано (`unwrap_actual_blueprint`), это та же ссылка на страницу, что при импорте — дёшево; пока книга-предмет лежит в скрытом инвентаре, игрок её не видит и `active_index` сменить не может, а для книги-записи активную страницу надо перечитать через `get_selected_record(player)` в момент сохранения (игрок мог листать книгу в библиотеке во время сессии) и сравнить с запомненной — при расхождении писать в запомненную. Пункт «книга» в чеклисте обязателен.
4. **`label` и иконки.** Варианты: (а) переносить с исходника как есть; для нового blueprint'а не задавать (игра покажет `default_icons`); (б) для нового blueprint'а ставить `label` вида «Blueprint Editor <дата/тик>»; (в) минимальный GUI «имя + 4 иконки» уже сейчас. **Рекомендация — (а):** редактирование метаданных — задача GUI Phase 5 (ADR-0001 §8(a).3); автогенерированный `label` потом придётся вычищать руками. Иконки нового blueprint'а игра выбирает сама по содержимому — это и есть ванильное поведение.
5. **Пустой результат** (все сущности и тайлы удалены, или new-режим без размещений). Варианты: (а) не сохранять: сообщение «нечего сохранять», сессия остаётся открытой (выход — `eb-discard`); (б) для edit-режима — `clear_blueprint()` исходника (blueprint становится пустым), для new — ничего не создавать; (в) записать пустые массивы. **Рекомендация — (а):** единственный сценарий, где сохранение может **уничтожить** содержимое исходника одним нажатием; явный отказ безопаснее. Если игрок действительно хочет пустой blueprint — у игры для этого есть своя кнопка очистки.
6. **Каскад размещения нового blueprint'а.** ADR §8(a).2: курсор → инвентарь → земля. Сейчас `teleport_out` для pinned-стека делает курсор → земля (без шага «инвентарь»). Варианты: (а) добавить шаг `player.insert` в общий каскад `teleport_out` (меняет и поведение возврата отредактированного blueprint'а при занятом курсоре: вместо земли — инвентарь); (б) оставить курсор → земля. **Рекомендация — (а):** на выходе из редактора курсор почти всегда пуст (мы сами его чистим), шаг редко срабатывает, но «в инвентарь» заметно дружелюбнее «под ноги», и это одна ветка кода, общая для всех источников.
7. **Экспорт проводов — один кортеж на провод** (Задача 1, S2). Это техническое решение, но оно влияет на форму busted-теста no-op регрессии. Варианты: (а) один кортеж на стороне с меньшим `entity_number` (рекомендация, см. Задачу 1); (б) кортеж на обеих сторонах, как хранит `EntityRecord.wires`. **Рекомендация — (а)** с переключением на (б), если S2 покажет, что игра на вставке требует обе стороны; план и тесты при этом меняются механически, решение владельца повторно не требуется.
