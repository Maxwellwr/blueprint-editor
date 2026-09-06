# Changelog

Формат по мотивам [Keep a Changelog](https://keepachangelog.com/), версии по [SemVer](https://semver.org/) (0.x до готовности MVP — см. `docs/sdlc.md`).

## [Unreleased]

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
