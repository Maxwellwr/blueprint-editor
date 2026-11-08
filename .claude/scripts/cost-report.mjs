// Учёт затрат подагентов по транскриптам: точные суммы `usage` всех вызовов, а не размер контекста
// последнего вызова (`subagent_tokens` в отчёте Agent недооценивает расход в десятки раз).
// Пишет в issue GitHub комментарий учёта с блоком `cost-report:v2` (PATCH существующего комментария
// с этим блоком, иначе новый). Записи — через `gh api` от аккаунта, под которым залогинен `gh`
// (репозиторий — из git remote текущего каталога или GH_REPO); --dry-run печатает их без выполнения.
// Учёта времени, как в Gitea, у GitHub нет: минуты живут в таблице комментария и в поле проекта «Минуты».
//
//   measure <agentId|путь.jsonl ...> [--since ISO] [--until ISO] [--json]
//       посчитать подагентов: ходы, вызовы инструментов, input/output/cache write/cache read, взвешенные токены
//   add <issue> --stage <код> --agents <id,id...> [--pr N] [--label "<строка таблицы>"]
//       [--since ISO] [--until ISO] [--minutes N] [--dry-run]
//       дописать этап (сумма по подагентам) в комментарий учёта
//       (--minutes — вместо длительности по транскрипту)
//   rewrite <issue> --stages-file <файл.json> [--dry-run]
//       заменить список этапов v2 целиком (пересчёт прошлого)
//   show <issue>
//       этапы и итоги из комментария
//   sync <issue> [--project N] [--dry-run]
//       пересинхронизировать числовые поля карточки issue в проекте из существующего комментария
//
// Итоги (`totals`) после `add`, `rewrite` и в `sync` пишутся в числовые поля карточки issue в проекте GitHub:
// Минуты, Ходы, Вызовы инстр., Input, Output, Cache write, Cache read, Взвеш. токены. Проект — `--project N`
// или env COST_PROJECT, по умолчанию 2; поля ищутся по имени (id не хардкодятся). Нет карточки или поля —
// предупреждение в stderr, не падение. Поле «Модель» скрипт не трогает. --dry-run печатает и эти записи.
// Нужен scope `project` у gh (`gh auth refresh -s project`).
//
// Транскрипт подагента: <проекты>/<сессия>/subagents/agent-<id>.jsonl, где <проекты> — CLAUDE_PROJECTS_DIR
// или ~/.claude/projects/<путь корня репозитория, не-буквы → «-»>* (вместе с каталогами worktree).
// Вызов модели — уникальный message.id (строки одного сообщения не суммируются дважды); ход = вызов.
//
// Взвешенные токены — ОЦЕНКА расхода в эквиваленте входных токенов по соотношению цен API:
//   weighted = input + 1,25 × cache write + 0,1 × cache read + 5 × output.
// Как тариф считает недельные окна, не публикуется: это ориентир для сравнения этапов, а не процент окна.
// Формат блока и правила — .claude/rules/github-workflow.md, «Учёт затрат в задаче».
// Скрипт перенесён из barista-free (там Gitea); блока v1 в этом репозитории не было, его чтение убрано.
import { execFileSync } from 'node:child_process'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

// {owner}/{repo} gh подставляет сам — из GH_REPO или git remote текущего каталога.
const R = 'repos/{owner}/{repo}'
export const V2 = /<!-- cost-report:v2\r?\n([\s\S]*?)\r?\n-->/
export const WEIGHTS = {
  input: 1,
  cacheWrite: 1.25,
  cacheRead: 0.1,
  output: 5,
}
let DRY = false

const fail = (m) => {
  console.error(m)
  process.exit(1)
}

// ---------- транскрипты ----------
export function modelName(id) {
  const m = /claude-(\w+)-(\d+)-(\d+)/.exec(id ?? '')
  if (!m) return id ?? '?'
  return `${m[1][0].toUpperCase()}${m[1].slice(1)} ${m[2]}.${m[3]}`
}

function projectDirs() {
  if (process.env.CLAUDE_PROJECTS_DIR) return [process.env.CLAUDE_PROJECTS_DIR]
  let root
  try {
    const common = execFileSync(
      'git',
      ['rev-parse', '--path-format=absolute', '--git-common-dir'],
      {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore'],
      },
    ).trim()
    root = dirname(common)
  } catch {
    root = process.cwd()
  }
  const slug = resolve(root).replace(/[^A-Za-z0-9]/g, '-')
  const base = join(homedir(), '.claude', 'projects')
  if (!existsSync(base)) return []
  return readdirSync(base)
    .filter((d) => d.toLowerCase().startsWith(slug.toLowerCase()))
    .map((d) => join(base, d))
}

export function findTranscript(idOrPath) {
  if (idOrPath.endsWith('.jsonl') && existsSync(idOrPath)) return idOrPath
  const id = idOrPath.replace(/^agent-/, '')
  for (const dir of projectDirs())
    for (const s of readdirSync(dir)) {
      const f = join(dir, s, 'subagents', `agent-${id}.jsonl`)
      if (existsSync(f)) return f
    }
  return null
}

// Сумма usage по уникальным вызовам модели в окне [since, until].
export function measureLines(lines, { since, until } = {}) {
  const calls = new Map()
  let model = null
  let first = null
  let last = null
  let toolCalls = 0
  for (const line of lines) {
    if (!line) continue
    let j
    try {
      j = JSON.parse(line)
    } catch {
      continue
    }
    if (j.type !== 'assistant' || !j.message?.id) continue
    const t = j.timestamp ?? null
    if (since && t && t < since) continue
    if (until && t && t > until) continue
    const m = j.message
    if (!calls.has(m.id)) calls.set(m.id, { usage: m.usage, tools: new Set() })
    const c = calls.get(m.id)
    c.usage = m.usage ?? c.usage
    for (const b of m.content ?? [])
      if (b.type === 'tool_use') c.tools.add(b.id)
    model ??= m.model
    if (t) {
      first ??= t
      last = t
    }
  }
  const s = {
    inputTokens: 0,
    outputTokens: 0,
    cacheCreationTokens: 0,
    cacheReadTokens: 0,
  }
  let lastCtx = 0
  for (const c of calls.values()) {
    const u = c.usage ?? {}
    s.inputTokens += u.input_tokens ?? 0
    s.outputTokens += u.output_tokens ?? 0
    s.cacheCreationTokens += u.cache_creation_input_tokens ?? 0
    s.cacheReadTokens += u.cache_read_input_tokens ?? 0
    toolCalls += c.tools.size
    lastCtx =
      (u.input_tokens ?? 0) +
      (u.cache_creation_input_tokens ?? 0) +
      (u.cache_read_input_tokens ?? 0) +
      (u.output_tokens ?? 0)
  }
  return {
    model: modelName(model),
    turns: calls.size,
    toolCalls,
    ...s,
    weightedTokens: weighted(s),
    finalContextTokens: lastCtx,
    minutes: first && last ? (Date.parse(last) - Date.parse(first)) / 60000 : 0,
    start: first,
    end: last,
  }
}

export function weighted(s) {
  return Math.round(
    s.inputTokens * WEIGHTS.input +
      s.cacheCreationTokens * WEIGHTS.cacheWrite +
      s.cacheReadTokens * WEIGHTS.cacheRead +
      s.outputTokens * WEIGHTS.output,
  )
}

export function measureAgent(idOrPath, window) {
  const f = findTranscript(idOrPath)
  if (!f)
    throw new Error(
      `Транскрипт подагента ${idOrPath} не найден (CLAUDE_PROJECTS_DIR?)`,
    )
  const r = measureLines(readFileSync(f, 'utf8').split('\n'), window)
  return { agent: idOrPath.replace(/^.*agent-|\.jsonl$/g, ''), ...r }
}

const SUM_KEYS = [
  'minutes',
  'turns',
  'toolCalls',
  'inputTokens',
  'outputTokens',
  'cacheCreationTokens',
  'cacheReadTokens',
  'weightedTokens',
]
export function sumStats(list) {
  const out = Object.fromEntries(SUM_KEYS.map((k) => [k, 0]))
  for (const x of list) for (const k of SUM_KEYS) out[k] += x[k] ?? 0
  out.minutes = Math.round(out.minutes)
  return out
}

// ---------- комментарий ----------
const n = (v) => {
  if (v === null || v === undefined) return '—'
  if (v >= 1e6) return `${(v / 1e6).toFixed(1).replace('.', ',')} млн`
  if (v >= 1e3) return `${Math.round(v / 1e3)} тыс.`
  return String(v)
}

export function renderV2(data) {
  const rows = data.stages.map((s) => {
    const exact = s.match !== 'unmatched'
    const note =
      s.match === 'exact'
        ? ''
        : s.match === 'approx'
          ? ' (≈)'
          : ' (нет транскрипта)'
    const label = s.label ?? s.stage
    // номер PR дописывается, только если его нет в подписи («План (PR #168)»)
    const pr =
      s.pr && !new RegExp(`PR #?${s.pr}(?!\\d)`).test(label)
        ? ` (PR ${s.pr})`
        : ''
    return `| ${label}${pr}${note} | ${s.model ?? '—'} | ${s.minutes ?? '—'} | ${exact ? s.turns : '—'} | ${exact ? s.toolCalls : '—'} | ${exact ? n(s.inputTokens) : '—'} | ${exact ? n(s.outputTokens) : '—'} | ${exact ? n(s.cacheCreationTokens) : '—'} | ${exact ? n(s.cacheReadTokens) : '—'} | ${exact ? n(s.weightedTokens) : '—'} | ${n(s.finalContextTokens)} |`
  })
  const counted = data.stages.filter((s) => s.match !== 'unmatched')
  data.totals = {
    ...sumStats(counted),
    minutes: data.stages.reduce((a, s) => a + (s.minutes ?? 0), 0),
    stages: data.stages.length,
    unmatched: data.stages.length - counted.length,
  }
  const t = data.totals
  const lines = [
    'Учёт затрат по задаче (v2: точные суммы по транскриптам подагентов).',
    '',
    '| Этап | Модель | Мин | Ходов | Вызовов инстр. | input | output | cache write | cache read | Взвеш. | Финал. контекст |',
    '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |',
    ...rows,
    `| **Итого** | | **${t.minutes}** | **${t.turns}** | **${t.toolCalls}** | **${n(t.inputTokens)}** | **${n(t.outputTokens)}** | **${n(t.cacheCreationTokens)}** | **${n(t.cacheReadTokens)}** | **${n(t.weightedTokens)}** | |`,
    '',
    'Источник: транскрипты подагентов, сумма `usage` всех вызовов модели (`.claude/scripts/cost-report.mjs`). ' +
      '«Взвеш.» — оценка в эквиваленте входных токенов по соотношению цен API: input + 1,25 × cache write + 0,1 × cache read + 5 × output; как тариф считает недельные окна, не публикуется — это ориентир, не процент окна. ' +
      '«Финал. контекст» — прежняя метрика (`subagent_tokens`, контекст последнего вызова). ' +
      '(≈) — транскрипт сопоставлен по датам и модели, а не по номеру задачи; «нет транскрипта» — этап не сопоставлен, в итоги токенов не входит. ' +
      'Время ревью владельца и ожидание оркестратора не входят.',
    '',
    `<!-- cost-report:v2\n${JSON.stringify(data)}\n-->`,
  ]
  return lines.join('\n')
}

// Из существующего тела комментария — данные блока v2.
export function parseComment(body) {
  const v2 = body?.match(V2)
  return v2 ? JSON.parse(v2[1]) : null
}

// ---------- GitHub ----------
function gh(path, method = 'GET', body) {
  const args = ['api', '-X', method]
  if (body !== undefined) args.push('--input', '-')
  args.push(path)
  const out = execFileSync('gh', args, {
    encoding: 'utf8',
    input: body !== undefined ? JSON.stringify(body) : '',
    stdio: ['pipe', 'pipe', 'pipe'],
    maxBuffer: 64 * 1024 * 1024,
  })
  return out.trim() ? JSON.parse(out) : null
}
function write(method, path, body) {
  if (DRY) {
    const shown = body?.body
      ? { ...body, body: `<${body.body.length} симв.>` }
      : body
    console.log(
      `DRY-RUN ${method} ${path}${shown !== undefined ? ' ' + JSON.stringify(shown) : ''}`,
    )
    return null
  }
  return gh(path, method, body)
}
function comments(issue) {
  const out = []
  for (let page = 1; page < 50; page++) {
    const part =
      gh(`${R}/issues/${issue}/comments?page=${page}&per_page=100`) ?? []
    out.push(...part)
    if (part.length < 100) break
  }
  return out
}
// Бота нет: комментарий учёта узнаётся по блоку, а не по автору.
export function findCostComment(list) {
  return list.find((c) => V2.test(c.body ?? '')) ?? null
}
// ---------- поля проекта ----------
export const FIELD_MAP = {
  minutes: 'Минуты',
  turns: 'Ходы',
  toolCalls: 'Вызовы инстр.',
  inputTokens: 'Input',
  outputTokens: 'Output',
  cacheCreationTokens: 'Cache write',
  cacheReadTokens: 'Cache read',
  weightedTokens: 'Взвеш. токены',
}
function graphql(query, vars = {}, numeric = []) {
  const args = ['api', 'graphql', '-f', `query=${query}`]
  for (const [k, v] of Object.entries(vars))
    args.push(numeric.includes(k) ? '-F' : '-f', `${k}=${v}`)
  const out = execFileSync('gh', args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 64 * 1024 * 1024,
  })
  return JSON.parse(out).data
}
const warn = (m) => console.error(`предупреждение: ${m}`)

// Записать totals в числовые поля карточки issue; любая неудача — предупреждение, не падение.
function syncFields(issue, totals, flags) {
  try {
    const projectNumber = Number(flags.project ?? process.env.COST_PROJECT ?? 2)
    const repo = JSON.parse(
      execFileSync('gh', ['repo', 'view', '--json', 'owner,name'], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
      }),
    )
    const data = graphql(
      'query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){projectItems(first:100){pageInfo{hasNextPage}nodes{id project{id number}}}}}}',
      { o: repo.owner.login, r: repo.name, n: issue },
      ['n'],
    )
    const items = data.repository?.issue?.projectItems
    if (items?.pageInfo?.hasNextPage)
      throw new Error(
        'у issue больше 100 карточек проектов, пагинация не реализована',
      )
    const item = items?.nodes?.find((x) => x.project.number === projectNumber)
    if (!item)
      return warn(
        `#${issue}: карточки в проекте №${projectNumber} нет, поля не обновлены`,
      )
    const fdata = graphql(
      'query($p:ID!){node(id:$p){... on ProjectV2{fields(first:100){pageInfo{hasNextPage}nodes{... on ProjectV2FieldCommon{id name dataType}}}}}}',
      { p: item.project.id },
    )
    if (fdata.node?.fields?.pageInfo?.hasNextPage)
      throw new Error('в проекте больше 100 полей, пагинация не реализована')
    const fields = new Map(
      (fdata.node?.fields?.nodes ?? [])
        .filter((f) => f.name)
        .map((f) => [f.name, f]),
    )
    const mutation =
      'mutation($p:ID!,$i:ID!,$f:ID!,$v:Float!){updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{number:$v}}){projectV2Item{id}}}'
    let failed = 0
    for (const [key, name] of Object.entries(FIELD_MAP)) {
      const field = fields.get(name)
      if (!field) {
        warn(`в проекте №${projectNumber} нет поля «${name}»`)
        failed++
        continue
      }
      if (field.dataType !== 'NUMBER') {
        warn(
          `поле «${name}» имеет тип ${field.dataType}, а не NUMBER — пропущено`,
        )
        failed++
        continue
      }
      const value = Number(totals[key] ?? 0)
      if (!Number.isFinite(value)) {
        warn(`значение для «${name}» нечисловое (${totals[key]}) — пропущено`)
        failed++
        continue
      }
      if (DRY) {
        console.log(
          `DRY-RUN updateProjectV2ItemFieldValue поле «${name}» $v=${value} (проект №${projectNumber}, карточка ${item.id}, поле ${field.id})`,
        )
        continue
      }
      try {
        graphql(
          mutation,
          { p: item.project.id, i: item.id, f: field.id, v: value },
          ['v'],
        )
      } catch (e) {
        warn(`поле «${name}»: ${e.stderr || e.message}`)
        failed++
      }
    }
    if (!DRY && !failed)
      console.log(`#${issue}: поля проекта №${projectNumber} обновлены`)
  } catch (e) {
    warn(
      `#${issue}: не удалось обновить поля проекта: ${e.stderr || e.message}`,
    )
  }
}

function save(issue, existing, body) {
  if (existing) write('PATCH', `${R}/issues/comments/${existing.id}`, { body })
  else write('POST', `${R}/issues/${issue}/comments`, { body })
}

// ---------- команды ----------
function parseArgs(argv) {
  const pos = []
  const flags = {}
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a.startsWith('--')) {
      const k = a.slice(2)
      if (i + 1 < argv.length && !argv[i + 1].startsWith('--'))
        flags[k] = argv[++i]
      else flags[k] = true
    } else pos.push(a)
  }
  return { pos, flags }
}
const windowOf = (f) => ({ since: f.since, until: f.until })

function cmdMeasure(pos, flags) {
  const list = pos
    .flatMap((x) => x.split(','))
    .filter(Boolean)
    .map((a) => measureAgent(a, windowOf(flags)))
  if (flags.json) return console.log(JSON.stringify(list, null, 2))
  for (const s of list)
    console.log(
      `${s.agent} ${s.model}: ${s.turns} ходов, ${s.toolCalls} вызовов инстр., ${Math.round(s.minutes)} мин; input ${n(s.inputTokens)}, output ${n(s.outputTokens)}, cache write ${n(s.cacheCreationTokens)}, cache read ${n(s.cacheReadTokens)}; взвеш. ${n(s.weightedTokens)}; финал. контекст ${n(s.finalContextTokens)}`,
    )
}

function cmdAdd(pos, flags) {
  const issue = Number(pos[0]) || fail('Нужен номер issue')
  const stage = flags.stage ?? fail('Нужен --stage')
  const ids = String(flags.agents ?? fail('Нужен --agents'))
    .split(',')
    .filter(Boolean)
  const per = ids.map((id) => measureAgent(id, windowOf(flags)))
  const sum = sumStats(per)
  if (flags.minutes) sum.minutes = Math.round(Number(flags.minutes))
  sum.minutes = Math.max(1, sum.minutes)
  const models = [...new Set(per.map((p) => p.model))]
  const entry = {
    stage,
    pr: flags.pr ? Number(flags.pr) : null,
    label: flags.label ?? stage,
    model: models.join(' + '),
    agents: per.map((p) => p.agent),
    match: 'exact',
    ...sum,
    finalContextTokens: per.reduce((a, p) => a + p.finalContextTokens, 0),
  }
  const existing = findCostComment(comments(issue))
  const d = parseComment(existing?.body) ?? { issue, stages: [] }
  d.stages.push(entry)
  save(issue, existing, renderV2(d))
  syncFields(issue, d.totals, flags)
  console.log(
    `#${issue}: этап ${stage} — ${entry.model}, ${sum.turns} ходов, взвеш. ${n(sum.weightedTokens)}, cache read ${n(sum.cacheReadTokens)}, ${sum.minutes} мин${existing ? ' (комментарий обновлён)' : ' (новый комментарий)'}${DRY ? ' (dry-run)' : ''}`,
  )
}

function cmdRewrite(pos, flags) {
  const issue = Number(pos[0]) || fail('Нужен номер issue')
  const stages = JSON.parse(
    readFileSync(flags['stages-file'] ?? fail('Нужен --stages-file'), 'utf8'),
  )
  const existing = findCostComment(comments(issue))
  const data = { issue, stages }
  save(issue, existing, renderV2(data))
  syncFields(issue, data.totals, flags)
  console.log(
    `#${issue}: этапов v2 — ${stages.length}${DRY ? ' (dry-run)' : ''}`,
  )
}

function cmdShow(pos) {
  const issue = Number(pos[0]) || fail('Нужен номер issue')
  const existing = findCostComment(comments(issue))
  if (!existing) return console.log(`#${issue}: комментария учёта нет`)
  const data = parseComment(existing.body)
  for (const s of data.stages)
    console.log(
      `${s.stage} PR ${s.pr ?? '—'} ${s.model} ${s.match}: ${s.minutes} мин, взвеш. ${n(s.weightedTokens)}, финал. ${n(s.finalContextTokens)}`,
    )
}

function cmdSync(pos, flags) {
  const issue = Number(pos[0]) || fail('Нужен номер issue')
  const existing = findCostComment(comments(issue))
  if (!existing) return console.log(`#${issue}: нет комментария учёта`)
  const data = parseComment(existing.body)
  syncFields(
    issue,
    data.totals ?? sumStats(data.stages.filter((x) => x.match !== 'unmatched')),
    flags,
  )
}

function main() {
  const [cmd, ...rest] = process.argv.slice(2)
  if (!cmd || cmd === '--help' || cmd === '-h') {
    const src = readFileSync(fileURLToPath(import.meta.url), 'utf8')
    return console.log(src.split('\nimport ')[0].replace(/^\/\/ ?/gm, ''))
  }
  const { pos, flags } = parseArgs(rest)
  DRY = Boolean(flags['dry-run'])
  const cmds = {
    measure: cmdMeasure,
    add: cmdAdd,
    rewrite: cmdRewrite,
    show: cmdShow,
    sync: cmdSync,
  }
  if (!cmds[cmd]) fail(`Неизвестная команда «${cmd}». Справка: --help`)
  try {
    cmds[cmd](pos, flags)
  } catch (e) {
    fail(e.message)
  }
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
)
  main()
