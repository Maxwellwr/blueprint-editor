---
paths:
  - "scripts/**"
  - "spec/**"
  - "data/**"
  - "*.lua"
  - ".busted"
  - "info.json"
  - ".github/workflows/**"
---

# Команды

```bash
busted                     # unit-тесты чистой логики (spec/*_spec.lua), из корня репозитория; конфиг — .busted
busted spec/canvas_spec.lua   # один файл; --filter "<часть имени теста>" — один тест
```

- Локально стоят Lua 5.4 и busted 2.3 (через WinGet). Factorio исполняет модифицированный Lua 5.2, CI гоняет тесты на Lua 5.2 (`.github/workflows/test.yml`). Поэтому в коде мода не использовать то, чего нет в 5.2: целочисленное деление `//`, побитовые операторы `& | ~ << >>`, библиотеку `utf8`, `<const>`/`<close>`. Тест, зелёный локально и красный в CI, чаще всего означает именно это.
- Factorio API в тестах не подменяется моками целиком: busted покрывает только чистые функции (принимают и возвращают обычные Lua-таблицы). Код с `game`, `storage`, `rendering`, `prototypes`, событиями проверяется playtest'ом (`docs/sdlc.md`, «Тестирование»).

## Dev-loop в игре (делает владелец)

- Мод подключён символической ссылкой из `%APPDATA%\Factorio\mods\blueprint-editor` на рабочую копию репозитория. Ссылка указывает на один каталог: чтобы проверить ветку из worktree, владелец переключает ссылку или ветку основной копии — агент об этом напоминает при передаче playtest-чеклиста.
- Правка `control.lua` / `scripts/*` — сохранить и перезагрузить сохранение; правка `data.lua` / `data/*` / `locale/*` / `info.json` — полный перезапуск игры.
- Лог игры — `%APPDATA%\Factorio\factorio-current.log`. Первая строка — точная версия игры (`Factorio 2.0.77 (build …)`), по ней сверяется документация API.
- `/eb-dump-session` — дамп `session.entities` и `session.tiles` текущей сессии в лог (`scripts/debug.lua`).
- Временное playtest-логирование — `log("eb playtest: …")`, grep по префиксу `eb playtest:`.
