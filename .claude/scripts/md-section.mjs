// Оглавление и разделы большого markdown-файла — чтобы читать план, спеку или архитектуру по разделу,
// а не целиком и не кусками вслепую. Только чтение.
//
//   node .claude/scripts/md-section.mjs <файл> --outline [--depth N]
//       заголовки с номерами строк и размером раздела (~токенов); --depth — до какого уровня (по умолчанию 3)
//   node .claude/scripts/md-section.mjs <файл> "<часть заголовка>" ["<ещё>" ...] [--no-sub]
//       печатает каждый найденный раздел: от заголовка до следующего заголовка того же или старшего уровня
//       (с подразделами; --no-sub — без них). Поиск — подстрока без учёта регистра; первое совпадение.
//       Номера строк в выводе — как в файле, их можно передать Read (offset/limit) для правки.
//
// Примеры:
//   node .claude/scripts/md-section.mjs docs/adr/0001-baseline-architecture.md --outline --depth 2
//   node .claude/scripts/md-section.mjs docs/phases/phase-3-plan.md "Задача 1" "Закрытие фазы"
//   node .claude/scripts/md-section.mjs CLAUDE.md "Договорённости" "Где что лежит"
//
// Токены — оценка: русский markdown ~0,45 токена на символ (замер по транскриптам подагентов, 2026-10-18).
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const TOKENS_PER_CHAR = 0.45

export function headings(lines) {
  const out = []
  let fence = false
  lines.forEach((line, i) => {
    if (/^\s*(```|~~~)/.test(line)) fence = !fence
    if (fence) return
    const m = /^(#{1,6})\s+(.*)$/.exec(line)
    if (m) out.push({ line: i, level: m[1].length, title: m[2].trim() })
  })
  return out
}

// Конец раздела: следующий заголовок того же или старшего уровня (или любого — при noSub).
export function sectionEnd(hs, idx, total, noSub = false) {
  const h = hs[idx]
  for (let j = idx + 1; j < hs.length; j++) {
    if (noSub || hs[j].level <= h.level) return hs[j].line
  }
  return total
}

function main() {
  const argv = process.argv.slice(2)
  if (!argv.length || argv.includes('--help') || argv.includes('-h')) {
    const src = readFileSync(fileURLToPath(import.meta.url), 'utf8')
    console.log(src.split('\nimport ')[0].replace(/^\/\/ ?/gm, ''))
    return
  }
  const file = argv[0]
  const lines = readFileSync(file, 'utf8').split(/\r?\n/)
  const hs = headings(lines)
  const flagVal = (name, def) => {
    const i = argv.indexOf(name)
    return i >= 0 ? argv[i + 1] : def
  }

  if (argv.includes('--outline')) {
    const depth = Number(flagVal('--depth', 3))
    const total = lines.join('\n').length
    console.log(
      `${file}: ${lines.length} строк, ~${Math.round((total * TOKENS_PER_CHAR) / 1000)} тыс. токенов`,
    )
    hs.forEach((h, i) => {
      if (h.level > depth) return
      const end = sectionEnd(hs, i, lines.length)
      const chars = lines.slice(h.line, end).join('\n').length
      const tok = Math.round(chars * TOKENS_PER_CHAR)
      console.log(
        `${String(h.line + 1).padStart(5)}-${String(end).padEnd(5)} ${'  '.repeat(h.level - 1)}${'#'.repeat(h.level)} ${h.title}  (~${tok >= 1000 ? Math.round(tok / 1000) + ' тыс.' : tok} ток.)`,
      )
    })
    return
  }

  const noSub = argv.includes('--no-sub')
  const queries = argv
    .slice(1)
    .filter((a, i, all) => !a.startsWith('--') && all[i - 1] !== '--depth')
  let missing = 0
  for (const q of queries) {
    const idx = hs.findIndex((h) =>
      h.title.toLowerCase().includes(q.toLowerCase()),
    )
    if (idx < 0) {
      console.error(`Раздел не найден: «${q}». Оглавление: --outline`)
      missing++
      continue
    }
    const start = hs[idx].line
    const end = sectionEnd(hs, idx, lines.length, noSub)
    console.log(`--- ${file}:${start + 1}-${end} ---`)
    console.log(lines.slice(start, end).join('\n').trimEnd())
  }
  if (missing) process.exitCode = 1
}

// Запуск только как скрипт: импорт ничего не выполняет.
if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
)
  main()
