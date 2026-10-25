// Хук PreToolUse (matcher Agent): перед запуском подагента напоминает основному
// агенту про проверку лимитов. Не блокирует вызов: всегда exit 0.
// Чек-лист и его смысл — .claude/rules/usage-reports.md.

const REMINDER =
  'Перед запуском подагента: ' +
  '1) get_usage (mcp__ccd_session_mgmt__get_usage) — окна 5 часов, неделя, Weekly · Fable; ' +
  '2) запущен ли Monitor-напоминание на 15 минут; ' +
  '3) выбор модели по окну Fable (.claude/rules/agent-orchestration.md). ' +
  'Подагентам этот чек-лист не касается.'

let raw = ''
process.stdin.setEncoding('utf8')
process.stdin.on('data', (chunk) => (raw += chunk))
process.stdin.on('end', () => {
  let payload = {}
  try {
    payload = JSON.parse(raw)
  } catch {
    // Пустой или битый stdin — всё равно напомним.
  }

  // Внутри подагента в payload есть agent_id — там чек-лист не нужен.
  if (payload && payload.agent_id) {
    process.exit(0)
  }

  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        additionalContext: REMINDER,
      },
    }) + '\n',
  )
  process.exit(0)
})
