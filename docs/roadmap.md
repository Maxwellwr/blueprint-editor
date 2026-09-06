# Роадмап

Живой документ статуса разработки по фазам. Архитектура и обоснование дизайна зафиксированы неизменяемо в [ADR-0001](adr/0001-baseline-architecture.md) — этот файл обновляется по мере прохождения каждой фазы (в отличие от ADR).

Каждая фаза независимо тестируема в игре; последующие фазы строго опираются на предыдущие.

**Текущий статус: Phase 2 завершена (2026-09-06, версия `0.3.0`).**

Процесс работы над фазой (git-ветки, code review, Definition of Done, TDD) описан в [`docs/sdlc.md`](sdlc.md). Детальная декомпозиция задач и итоговая запись решений по каждой фазе живут в `docs/phases/phase-N-plan.md` / `docs/phases/phase-N-implementation.md` (создаются по ходу работы над фазой, см. `docs/phases/README.md`).

## Фазы

- **Phase 0 — Scaffold + empty canvas surface. ЗАВЕРШЕНА (2026-09-05, `0.1.0`).** `info.json`, `state.lua` init, `surface.lua` (lab-tile surface + teleport in/out), single `eb-toggle-editor` input. *Spikes: `generate_with_lab_tiles` behavior; plain-click selection-tool area-event behavior.* Оба спайка подтверждены playtest'ом — см. [`docs/phases/phase-0-implementation.md`](phases/phase-0-implementation.md).
- **Phase 1 — Read-only render of an existing blueprint. ЗАВЕРШЕНА (2026-09-06, `0.2.1`).** `blueprint_io.import_from_stack` (read-only), `rendering.lua` grid/entity/tile draw. *Spike: Blueprint Library transfer risk.* Изначально подтверждён провальным для `cursor_stack`; патчем `0.2.1` решён через `cursor_record` — перенос из Blueprint Library работает. См. [`docs/phases/phase-1-implementation.md`](phases/phase-1-implementation.md).
- **Phase 2 — Add/remove/rotate entities + entity_number/wire bookkeeping. ЗАВЕРШЕНА (2026-09-06, `0.3.0`).** `canvas.lua` mutation API, `input.lua`, cursor-tool equip, ad-hoc 7-item palette. DoD-тест (delete a wired pole, confirm the deleted id is gone from every other entity's wires list) подтверждён напрямую по `factorio-current.log`. См. [`docs/phases/phase-2-implementation.md`](phases/phase-2-implementation.md).
- **Phase 3 — Tiles.** `place_tile`/`remove_tile`, tile catalog basics, tile rendering.
- **Phase 4 — Save back to same blueprint / new blueprint.** `export_to_entities_array`, `save_new_blueprint`, `save_back_to_stack`. Test: new blueprint round-trip, no-op re-export regression check, wired-delete real-paste verification.
- **Phase 5 — Палитра, поиск, группы, качество, инспектор сущности.** Full `catalog.lua` + `palette_gui.lua`, translation-cache-backed search, click-to-inspect entity panel (ADR-0001, раздел 7).
- **Phase 6 — Wires.** Player-driven wire creation/removal UI built on the bookkeeping already in place since Phase 2.
- **Phase 7 — Polish / mod-compat edge cases.** Rails/rolling-stock basic placement, entity render fidelity pass, snap-metadata round-trip, render-object perf budget for large blueprints, multiplayer concurrent-session stress test, camera-GUI spike (stretch). *(Blueprint Library resolution решена раньше срока — патч `0.2.1`, Phase 1.)*

## Обновление статуса

При завершении фазы (после прохождения Definition of Done — см. `docs/sdlc.md`):
1. Отметить фазу как завершённую в списке выше (дата, номер версии `info.json` после мержа).
2. Убедиться, что `docs/phases/phase-N-implementation.md` создан и закоммичен вместе с мержем.
3. Обновить `CHANGELOG.md`.
