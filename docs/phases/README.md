# Документы фаз

Для каждой фазы из [`docs/roadmap.md`](../roadmap.md) заводится пара файлов:

- **`phase-N-plan.md`** — создаётся в начале работы над фазой. Декомпозиция задач фазы на конкретные шаги, ссылки на спайки, упомянутые в [ADR-0001](../adr/0001-baseline-architecture.md) для этой фазы.
- **`phase-N-implementation.md`** — создаётся по завершении фазы, перед мержем ветки `phase-N-*` в `main`. Что реально сделано, какие решения приняты по ходу (включая отклонения от `phase-N-plan.md`), результат ручного playtest-чеклиста. Это основной артефакт Definition of Done фазы (см. `docs/sdlc.md`) — отдельного файла под чеклист не заводим.

Шаблоны: [`TEMPLATE-plan.md`](TEMPLATE-plan.md), [`TEMPLATE-implementation.md`](TEMPLATE-implementation.md).

Если по ходу фазы принимается решение, отклоняющееся от [ADR-0001](../adr/0001-baseline-architecture.md), — оно попадает в `phase-N-implementation.md`, а если существенно меняет архитектуру — дополнительно оформляется отдельным ADR (см. `docs/adr/README.md`).
