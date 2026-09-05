# Changelog

Формат по мотивам [Keep a Changelog](https://keepachangelog.com/), версии по [SemVer](https://semver.org/) (0.x до готовности MVP — см. `docs/sdlc.md`).

## [Unreleased]

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
