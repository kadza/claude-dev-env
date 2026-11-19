import type { Register } from 'claude-code'
import type { EngineInterface } from 'claude-code'

const refresh = async ($: EngineInterface) => {
  try {
    const [model, cwd] = await Promise.all([$.session.model(), $.session.cwd()])
    $.ui.status(`${cwd} · ${model}`)
  } catch {}
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    await refresh($)
    return result
  })

  on('prompt.submit', async ($, e, next) => {
    const result = await next(e)
    await refresh($)
    return result
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    await refresh($)
    return result
  })
}
