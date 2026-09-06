# Changelog

Формат по мотивам [Keep a Changelog](https://keepachangelog.com/), версии по [SemVer](https://semver.org/) (0.x до готовности MVP — см. `docs/sdlc.md`).

## [Unreleased]

## [0.4.0] — 2026-09-07

Phase 3 — Tiles.

### Добавлено

- `scripts/canvas.lua` — мутационное API тайлов (`place_tile`/`remove_tile`/`find_tile_at`), чистая логика с TDD (`tile_coordinates`, `tile_key`).
- `scripts/rendering.lua` — `draw_tile`/`clear_tile_render` (поштучный рендер тайла, без утечки render-объекта при перезаписи клетки), `TILE_RENDER_WARN_THRESHOLD`.
- `scripts/input.lua` — единая палитра сущностей и тайлов (`[`/`]` листают оба типа), приоритет «сущность, потом тайл» для удаления (alt-select/`eb-delete`) и подбора (`eb-pick-entity`).
- `scripts/migrations.lua` — миграция `0.4.0` (нормализация формы `Session.selected_palette_item`).
- `busted`: +1 тест сверх плана (31/31 всего) — контрактный тест, сверяющий ключи `canvas.tile_key` и `blueprint_io.build_import_data`.

### Исправлено

- Тайлы визуально перекрывали сущность на той же клетке после импорта (общий дефолтный `render_layer = "arrow"` у сущностей и тайлов, тайлы рисовались вторыми) — данные не терялись, баг был чисто рендер-слоя; тайлам явно задан более низкий `render_layer`.
- `cycle_palette` больше не сохраняет в сессию прямую ссылку на элемент модульной константы палитры (копирует значение, как и подбор через `Q`).
- `remove_at` в `input.lua` явно падает на нераспознанном типе цели вместо тихого предположения «раз не сущность — значит тайл» (fail-fast).

См. [`docs/phases/phase-3-implementation.md`](docs/phases/phase-3-implementation.md) для полного списка решений, найденных фактов и известных ограничений.

## [0.3.0] — 2026-09-06

Phase 2 — Add/remove/rotate entities + entity_number/wire bookkeeping.

### Добавлено

- `scripts/canvas.lua` — мутационное API (`place_entity`/`remove_entity`/`rotate_entity`/`find_entity_at`), чистая логика с TDD (`snap_position`, `next_direction`, `remove_wire_references`, `to_local_position`).
- `scripts/blueprint_io.lua` — `build_import_data` строит `EntityRecord.wires` из `BlueprintEntity.wires` при импорте (двунаправленно, с дедупликацией).
- `scripts/input.lua` — обработчики размещения/удаления/поворота/подбора/цикла ad-hoc палитры (7 жёстко зашитых типов), переэкипировка `eb-cursor-tool`.
- `scripts/rendering.lua` — `draw_entity`/`clear_entity_render` (поштучный рендер без полной перерисовки сессии).
- `scripts/debug.lua` — команда `eb-dump-session`.
- 5 новых custom-input (`eb-rotate`/`eb-delete`/`eb-pick-entity`/`eb-cycle-palette-next`/`eb-cycle-palette-prev`) + `reverse_select` на `eb-cursor-tool` (удаление правым кликом).
- `scripts/state.lua` — `Session.selected_palette_item`, миграция `0.3.0` (backfill `EntityRecord.wires`).
- `busted`: +14 тестов (25/25 всего) — `spec/canvas_spec.lua` (новый), `spec/blueprint_io_spec.lua` (расширен).

### Исправлено

- `eb-cursor-tool` экипируется и в edit-режиме, не только в "new" (Phase 1 экипировала только для пустого канваса).
- Иконка `eb-cursor-tool` заменена с `blueprint.png` на `copy-paste-tool.png` — игрок не мог отличить инструмент редактора от настоящего чертежа в руке.
- Округление `blueprint_center` до целого — импортированные сущности выравнены по видимой сетке (была систематическая ошибка на дробную величину).
- Точечная защита от размещения нескольких сущностей в одной уже занятой клетке (не полноценная collision-детекция, см. известные ограничения в `phase-2-implementation.md`).
- `teleport_out` больше не пытается «уронить» `eb-cursor-tool` при выходе из edit-режима (курсор явно чистится перед восстановлением запиненного чертежа).

См. [`docs/phases/phase-2-implementation.md`](docs/phases/phase-2-implementation.md) для полного списка решений, найденных фактов и известных ограничений.

## [0.2.1] — 2026-09-06

Патч к Phase 1: снятие ограничения Blueprint Library, освобождение курсора в редакторе.

### Исправлено

- Blueprint из Blueprint Library теперь читается и рендерится (`player.cursor_record`, отдельно от `player.cursor_stack`) — снимает ограничение, задокументированное в `0.2.0`.
- Курсор освобождается при входе в редактор (обычный blueprint прячется в скрытый инвентарь и возвращается при выходе; библиотечный — очищается, с сообщением, что запись осталась в библиотеке).
- Blueprint-книги разворачиваются до текущей выбранной страницы; превью-записи библиотеки (`is_preview`) пропускаются.
- Устранён риск потери данных: временный инвентарь для «спрятанного» blueprint'а больше не уничтожается, пока не подтверждено, что он пуст (обнаружено по факту — один раз реально пропала blueprint-книга игрока из-за неверного порядка операций вокруг переключения на god-контроллер).

См. [`docs/phases/phase-1-implementation.md`](docs/phases/phase-1-implementation.md#патч-021--blueprint-library-освобождение-курсора-книги) для деталей.

## [0.2.0] — 2026-09-06

Phase 1 — Read-only render of an existing blueprint.

### Добавлено

- `scripts/blueprint_io.lua` — `import_from_stack` (read-only импорт blueprint'а из курсора игрока), `build_import_data`/`compute_bounding_box_center` (чистая логика, покрыта TDD).
- `scripts/rendering.lua` — `draw_grid`/`draw_entities`/`draw_tiles`/`clear_session_renders` (иконки-спрайты с фолбэком для неустановленных модов).
- `scripts/state.lua` — расширенная схема `Session` (`entities`, `tiles`, `blueprint_center`, `render_ids`, ...), миграция `0.2.0`.
- Свободный облёт (`defines.controllers.god`) внутри редактора вместо коллизий обычного персонажа.
- Первая тестовая инфраструктура репозитория: `busted`, `.busted`, `spec/blueprint_io_spec.lua` (8/8 тестов).

### Подтверждено (спайк)

- Перенос blueprint'а из игровой Blueprint Library через `cursor_stack` **не работает** (`valid_for_read = false`) — подтверждённый ADR-0001 риск, задокументирован как известное ограничение MVP (воркэраунд: сначала перетащить в инвентарь/книгу).

См. [`docs/phases/phase-1-implementation.md`](docs/phases/phase-1-implementation.md) для полного списка решений, найденных фактов и известных ограничений.

## [0.1.0] — 2026-09-05

Phase 0 — Scaffold + empty canvas surface.

### Добавлено

- `info.json` — метаданные мода, `factorio_version = "2.0"`.
- Custom-input `eb-toggle-editor` (`Ctrl+Shift+K`) и selection-tool `eb-cursor-tool`.
- `scripts/state.lua` — схема `storage` и session-accessors.
- `scripts/migrations.lua` — аддитивный механизм миграций (пока без шагов).
- `scripts/surface.lua` — canvas-поверхность `eb-canvas` (lab tiles), телепорт туда/обратно с региональным офсетом на игрока.
- `control.lua` — bootstrap и event wiring.
- `locale/en/controls.cfg`.

### Подтверждено (спайки)

- `LuaSurface.generate_with_lab_tiles` заменяет генерацию карты для каждого посещённого чанка.
- Одиночный клик с экипированным `selection-tool` вызывает `on_player_selected_area` с точечной area — основной дизайн ввода для Phase 2 подтверждён.

См. [`docs/phases/phase-0-implementation.md`](docs/phases/phase-0-implementation.md) для полного списка решений, найденных фактов и известных ограничений.
