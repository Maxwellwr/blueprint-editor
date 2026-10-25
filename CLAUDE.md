# CLAUDE.md

Работа с этим репозиторием. Здесь — только то, что нужно каждому агенту и каждой роли; ролевое и привязанное к путям лежит отдельно (раздел «Где что лежит»).

## Проект

`blueprint-editor` — мод Factorio 2.0 (Space Age — опционально): редактирование blueprint как данных. Сущности и тайлы — Lua-таблицы в форме `BlueprintEntity`/`Tile`, рендер — оверлей `LuaRendering` на отдельной поверхности `eb-canvas`; реальные игровые объекты не создаются. Архитектура и обоснование — [ADR-0001](docs/adr/0001-baseline-architecture.md) (неизменяем), статус фаз — [`docs/roadmap.md`](docs/roadmap.md), версии — [`CHANGELOG.md`](CHANGELOG.md).

Код: `control.lua` (bootstrap событий) → `scripts/` (`state` — `storage`, `migrations`, `surface`, `blueprint_io`, `canvas` — мутации, `rendering`, `input`, `debug`); прототипы — `data/`; unit-тесты чистой логики — `spec/` (busted).

## Где что лежит

Правила в `.claude/rules/` без `paths` грузятся всем при старте; с `paths` во frontmatter — только когда агент читает или правит файл по шаблону. Нужное правило без работы с его файлами — прочитать явно: `Read` или `node .claude/scripts/md-section.mjs <файл> "<раздел>"`.

- Процесс разработки для людей и агентов: фазы, Definition of Done, версионирование, тестирование и playtest, архитектурные принципы — [`docs/sdlc.md`](docs/sdlc.md). Прочитать перед началом любой работы над фазой.
- GitHub: PR, ветка фазы, хотфиксы, планы через PR, задачи, метки, доска, учёт затрат, монитор PR, самостоятельный merge, уборка, первичная настройка репозитория — `.claude/rules/github-workflow.md` (всем).
- Оркестрация подагентов, выбор модели, трудности исполнителей, playtest — `.claude/rules/agent-orchestration.md`; остаток лимитов — `.claude/rules/usage-reports.md` (всем; основному агенту).
- Команды тестов и dev-loop в игре — `.claude/rules/commands.md`; выжимка принципов кода мода — `.claude/rules/lua-mod.md` (оба — по путям `scripts/`, `data/`, `spec/`, `*.lua`).
- Документы фаз — [`docs/phases/`](docs/phases/) (`phase-N-plan.md` / `phase-N-implementation.md`, шаблоны там же).
- Типы подагентов — `.claude/agents/` (`code-executor`, `doc-writer`, `reviewer`, `github-ops`, `cleanup`; выбор — `agent-orchestration.md`, «Типы подагентов»); скрипты чтения разделов markdown и учёта затрат — `.claude/scripts/md-section.mjs`, `cost-report.mjs`.

## Договорённости

Договорённость, которая должна действовать на всех машинах и у всех агентов, записывается в `CLAUDE.md` (общая) или в `.claude/rules/` (ролевая или по путям), а не в личную автопамять Claude Code — та остаётся на одной машине.

- **Язык проекта — русский.** Все артефакты (документы, планы, комментарии в коде, тексты PR и issue) — по-русски, и ответы Claude Code владельцу в чате — тоже. Исключение — заголовки коммитов: Conventional Commits на английском (`docs/sdlc.md`, «Коммиты»).
- **Репозиторий — на GitHub** (`github.com/Maxwellwr/blueprint-editor`), CI — GitHub Actions, инструмент — `gh`. В `main` — только через PR; фаза ведётся в ветке `phase/N-<slug>` и сливается в `main` одним PR по окончании. Merge в `main` делает владелец; PR в ветку фазы без решений владельца мёржит основной агент по чек-листу. Бота нет: реплики агентов в GitHub начинаются с «🤖». Подробно — `.claude/rules/github-workflow.md`.
- **Основной агент оркестрирует, подагенты исполняют** — `.claude/rules/agent-orchestration.md`.
- **Factorio API — только по документации установленной версии** (`2.0.77`, `https://lua-api.factorio.com/2.0.77/…`), никогда `/latest/` — `docs/sdlc.md`, «Версия Factorio и проверка API-фактов».
- **Playtest проводит владелец**, агент готовит временное логирование `eb playtest:` и разбирает `factorio-current.log` — `docs/sdlc.md`, «Тестирование».
