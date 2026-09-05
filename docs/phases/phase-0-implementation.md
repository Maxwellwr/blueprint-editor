# Phase 0 — Scaffold + empty canvas surface — реализация

- Ветка: `phase-0-scaffold` → `main`
- Версия после мержа: `info.json` `0.1.0`
- Дата завершения: 2026-09-05

## Что сделано

- `info.json` — метаданные мода, `factorio_version = "2.0"`, зависимости `base >= 2.0` и опционально `space-age`.
- Data-стадия: `data.lua`, `data/custom-input.lua` (custom-input `eb-toggle-editor`), `data/selection-tool.lua` (selection-tool `eb-cursor-tool`).
- `scripts/state.lua` — единственный модуль, трогающий `storage` напрямую; схема `storage` (`mod_version`, `canvas_surface_name`, `sessions`) и session-accessors (`init`, `canvas_surface_name`, `get_mod_version`, `set_mod_version`, `get_session`, `start_session`, `clear_session`, `each_session`).
- `scripts/migrations.lua` — аддитивный механизм миграций (пустой список шагов), корректное упорядоченное сравнение semver-версий.
- `scripts/surface.lua` — `ensure_canvas_surface` (lab-tile поверхность `eb-canvas`, идемпотентна), `teleport_in`/`teleport_out` с проверкой машины/remote-view, региональным офсетом по `player_index`.
- `control.lua` — bootstrap: регистрация `on_init`, `on_configuration_changed`, `on_load` (no-op), `on_player_joined_game` (очистка осиротевших сессий), custom-input `eb-toggle-editor`, спайковый хендлер `on_player_selected_area`.
- `locale/en/controls.cfg` — имя control'а `eb-toggle-editor` для Settings → Controls.
- `.luarc.json` — объявление Factorio-глобалов (`data`, `game`, `script`, `storage`, `defines` и т.д.) для Lua-language-server, чтобы редактор не подсвечивал их как undefined-global.

Оба обязательных спайка (ADR-0001 §2) подтверждены вживую:

- **`generate_with_lab_tiles`** — read-write свойство `LuaSurface`, выставляется после `game.create_surface(...)` (не поле `MapGenSettings`, как формулировка ADR-0001 §5 предполагала вскользь). Подтверждено и документацией lua-api.factorio.com, и playtest: клики/drag в `factorio-current.log` покрывают координаты x≈1005–1031, y≈-10–7 на поверхности `eb-canvas`, созданной с `width=2, height=2` — то есть чанки далеко за пределами исходных 2×2 тайлов сгенерированы и кликабельны, подтверждая, что `generate_with_lab_tiles` полностью подменяет генератор для каждого посещённого чанка, а не только для стартовой области.
- **Plain click + `eb-cursor-tool` → `on_player_selected_area`** — подтверждено. `factorio-current.log`: `eb spike: on_player_selected_area fired, area={left_top = {x = 1021.664, y = -7.211}, right_bottom = {x = 1021.664, y = -7.211}}, entities=0` — `left_top == right_bottom` доказывает точечную (не требующую протяжки) область от одиночного клика. Отдельно подтверждён и полноценный drag-select (`entities=1` в одной из записей). Fallback на raw `custom-input` + `cursor_position` (ADR-0001 §5) не понадобился — основной дизайн ввода для Phase 2 подтверждён рабочим.

## Решения, принятые по ходу (отклонения от phase-0-plan.md / ADR-0001)

Все найдены через ручной playtest (Task 7), не через ревью кода до запуска игры:

1. **`data/selection-tool.lua` использовал схему Factorio 1.1.** Мод не грузился (`Key "select" not found...`). Factorio 2.0 требует вложенные `select`/`alt_select` (`SelectionModeData`: `border_color`, `cursor_box_type`, `mode`) вместо плоских `selection_mode`/`selection_color`/`selection_cursor_box_type`. Подтверждено документацией lua-api.factorio.com, исправлено без нового ADR (уточнение факта API, не архитектурное решение).
2. **`key_sequence` для `eb-toggle-editor` менялся дважды.** Изначальный `CONTROL + SHIFT + B` совпадал с шорткатом стороннего мода `blueprint-align`. Замена на `CONTROL + SHIFT + E` совпала с захардкоженным, непереназначаемым debug-хоткеем движка Factorio («Prototype Explorer» — подтверждено wiki.factorio.com/Tutorial:Keyboard_shortcuts; такие хоткеи не видны ни в Settings → Controls, ни в файлах модов). Финальное значение — `CONTROL + SHIFT + K`, проверено сканированием всех установленных модов и списком захардкоженных хоткеев движка.
3. **Отсутствовал locale-файл для `eb-toggle-editor`** — Settings → Controls показывал `Unknown key: "controls.eb-toggle-editor"`. Не упомянуто ни в ADR-0001, ни в плане, но необходимо для базовой гигиены мода. Добавлен `locale/en/controls.cfg` (английский — по прецеденту `info.json.description`, тоже английского, несмотря на то что документация проекта — на русском).
4. **Критичный краш при save-reload.** `game` недоступен внутри `on_load` в принципе (подтверждено lua-api.factorio.com/latest/auxiliary/data-lifecycle.html — запись в `storage` там тоже запрещена), а исходный `on_load` вызывал `game.get_player(...)`. Логика очистки осиротевших сессий перенесена в `on_player_joined_game`, `on_load` остался зарегистрированным как no-op.
5. **`teleport_out` не очищал курсор** — `eb-cursor-tool` оставался в руках игрока после выхода из редактора. Добавлен `player.clear_cursor()`, симметрично `teleport_in`.
6. **Финальный whole-branch review (см. ledger) нашёл и потребовал исправить до мержа:** нарушение инкапсуляции `storage` в `migrations.lua` (добавлены accessors `get_mod_version`/`set_mod_version` в `state.lua`), неверное сравнение версий (`~=` вместо упорядоченного semver `<`), захардкоженный `mod_version = "0.0.1"` в `default_storage()` (заменён на `script.active_mods["blueprint-editor"]`, чтобы не расходиться с `info.json`), и неучтённый результат `player.clear_cursor()` в `teleport_in` (при полном инвентаре игрока `set_stack` мог уничтожить предмет в курсоре — теперь `set_stack` вызывается только при успешной очистке курсора).

## Definition of Done

- [x] Ручной playtest-чеклист фазы пройден (пункты ниже)
- [x] `/code-review` пройден (финальный whole-branch review, most capable model), замечания закрыты (4 Important) или адъюдицированы (6 остаточных minor, ни один не блокирующий — см. ledger `.superpowers/sdd/phase-0-plan/progress.md`)
- [x] Документация обновлена (`docs/roadmap.md`; ADR не менялся — все находки этой фазы являются уточнениями API-фактов или исправлениями кода, а не архитектурными отклонениями)
- [x] Миграция — не требуется (схема `storage` не менялась после первой версии в рамках самой фазы; `mod_version` теперь читается динамически из `script.active_mods`, а не хранится как отдельная захардкоженная константа, поэтому миграция версии не нужна)
- [x] `CHANGELOG.md` обновлён

### Playtest-чеклист

Полный прогон после всех фиксов, подтверждено человеком-партнёром: «всё работает как задумано».

- [x] Мод грузится без ошибок в логе/консоли.
- [x] `Ctrl+Shift+K` телепортирует игрока на поверхность `eb-canvas`.
- [x] Поверхность `eb-canvas` — лабораторные тайлы, плоская, без ресурсов и врагов (спайк 1).
- [x] После входа в редактор у игрока в курсоре — `eb-cursor-tool`.
- [x] Одиночный клик вызывает лог `eb spike: on_player_selected_area fired...` с точечной area (спайк 2, подтверждено через `factorio-current.log` — сам игровой чат/консоль `log()`-вывод не показывает).
- [x] Повторный `Ctrl+Shift+K` возвращает игрока на исходную позицию/поверхность; курсор очищается.
- [x] Вход в редактор в машине/remote view отклоняется с сообщением, телепорта не происходит.
- [x] Save-reload внутри редактора — не крашит (после фикса `on_load`/`on_player_joined_game`).
- [x] Разные `player_index` получают непересекающиеся регионы на `eb-canvas` (офсет кратен `REGION_SPACING = 1024`).

## Известные ограничения / перенесено в следующую фазу

- Курсор-инструмент не «залипает» принудительно — полноценный lock через `on_player_cursor_stack_changed` появится только в Phase 2.
- `teleport_in` молча возвращает `false` без сообщения игроку, если сессия уже есть (путь недостижим в Phase 0 — единственный вызывающий, `control.lua`, сам проверяет сессию заранее; актуально станет при появлении дополнительных точек входа в Phase 2).
- `pre_edit.controller_type` записывается в сессию, но не применяется при выходе — сегодня не является дефектом, поскольку `player.teleport` не меняет тип контроллера сам по себе; станет обязательным в фазе, где вход в редактор начнёт форсировать god/spectator-контроллер (вероятно, при работе над рендером/камерой).
- Два новых комментария в `scripts/surface.lua` (про `width/height` и `REGION_SPACING`) написаны на английском — расходится с остальными комментариями проекта (русский) и с правилом CLAUDE.md про язык артефактов. Дешёвая правка, отложена до первого прохода по этим файлам в Phase 1.
- `scripts/migrations.lua`'s `parse_version` вернёт `nil` на некорректной строке версии, что уронит `version_less_than` вместо мягкого отказа. Недостижимо, пока `M.steps` пуст; учесть при добавлении первого реального шага миграции в Phase 2.
- `teleport_out` молча оставляет игрока на канвасе (без сообщения), если `pre_edit.surface_name` был удалён за время сессии — редкий краевой случай, лучше, чем прежний хардкраш, но не сообщает игроку о причине.
- Компаратор версий в `migrations.lua` (`parse_version`/`version_less_than`) — единственный кусок чистой логики без Factorio API во всей фазе; по `docs/sdlc.md` (DoD, TDD) должен покрываться `busted`. Решение: сама логика исправлена и вручную проверена (`0.1.0 < 0.2.0` → true, `0.9.0 < 0.10.0` → true как числа, а не строки, `1.0.0 < 1.0.0` → false), но заведение `busted`-раннера как инфраструктуры отложено до Phase 2, где появится первая реальная pure-logic-задача (`internal_id`-remap), и обе будут покрыты вместе.
- `locale/en/controls.cfg` — файл не упомянут в раскладке ADR-0001 §3 (ADR неизменяем); необходимое, безвредное дополнение, зафиксировано здесь, а не отдельным ADR.
- Локали `locale/ru/` нет — не критично для Phase 0 (нет игрового текста, требующего локализации, кроме имени одного control'а), но должна появиться не позже фазы, где будет GUI.
