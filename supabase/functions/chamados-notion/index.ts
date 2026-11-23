// Edge Function chamados-notion — leva os chamados assumidos para a base "Acompanhamento de Tarefas · P&D" do Notion.
//
// Quem decide QUANDO sincronizar é o banco (gatilho em chamados.eventos + retentativa no agendador do push);
// esta função lê a fila (notion_lote), cria ou atualiza a página no Notion e confirma (notion_confirmar).
// Chamada pelo pg_net com o segredo de despacho do Vault no cabeçalho `x-chamados-notion-secret` — por isso
// verify_jwt=false: a autenticação é esse segredo, conferido pelos próprios RPCs (que só aceitam service_role).
// O token da integração do Notion fica só no segredo NOTION_TOKEN desta função (painel do Supabase).
import { blocos, calloutFicha, calloutHistorico, equipeCorrigida, propriedades, TITULO_FICHA, TITULO_HISTORICO, type Item } from './notion.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const NOTION = 'https://api.notion.com/v1'
const NOTION_VERSION = '2022-06-28'

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: {
      apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json',
      'Content-Profile': 'chamados', 'Accept-Profile': 'chamados',
    },
    body: JSON.stringify(args),
  })
  const text = await res.text()
  if (!res.ok) throw new Error(`${fn}: ${res.status} ${text.slice(0, 300)}`)
  return (text ? JSON.parse(text) : null) as T
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}

async function notion(token: string, method: string, path: string, body: unknown) {
  const res = await fetch(`${NOTION}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, 'Notion-Version': NOTION_VERSION, 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  const text = await res.text()
  let data: Record<string, unknown> = {}
  try { data = text ? JSON.parse(text) : {} } catch { /* resposta não JSON */ }
  return { status: res.status, data, text }
}

const espera = (ms: number) => new Promise((r) => setTimeout(r, ms))

type Bloco = { id: string; type: string; callout?: { rich_text: { plain_text: string }[] } }
const textoDoBloco = (b: Bloco) => (b.callout?.rich_text ?? []).map((t) => t.plain_text).join('')

/**
 * Reescreve a ficha e o histórico no topo de uma página que já existe. Páginas antigas têm só um callout de resumo:
 * ele vira a ficha e o histórico entra logo abaixo. O resto da página (descrição, anotações do time) não é tocado.
 */
async function atualizarFicha(token: string, pageId: string, i: Item): Promise<void> {
  const r = await notion(token, 'GET', `/blocks/${pageId}/children?page_size=20`, undefined)
  if (r.status !== 200) { console.error(`ficha ${i.protocolo}: ${r.status}: ${r.text.slice(0, 200)}`); return }
  const callouts = ((r.data.results as Bloco[] | undefined) ?? []).filter((b) => b.type === 'callout')
  const ficha = callouts.find((b) => textoDoBloco(b).startsWith(TITULO_FICHA)) ?? callouts.find((b) => !textoDoBloco(b).startsWith(TITULO_HISTORICO))
  const hist = callouts.find((b) => textoDoBloco(b).startsWith(TITULO_HISTORICO))
  const fNovo = calloutFicha(i), hNovo = calloutHistorico(i)
  if (ficha) await notion(token, 'PATCH', `/blocks/${ficha.id}`, { callout: fNovo.callout })
  if (hist) await notion(token, 'PATCH', `/blocks/${hist.id}`, { callout: hNovo.callout })
  const faltam = [...(ficha ? [] : [fNovo]), ...(hist ? [] : [hNovo])]
  if (faltam.length) {
    const a = await notion(token, 'PATCH', `/blocks/${pageId}/children`, { children: faltam, ...(ficha ? { after: ficha.id } : {}) })
    if (a.status !== 200) console.error(`ficha ${i.protocolo}: ${a.status}: ${a.text.slice(0, 200)}`)
  }
}

async function sincronizar(token: string, databaseId: string, i: Item): Promise<{ ok: boolean; page_id?: string; erro?: string }> {
  if (i.page_id) {
    const r = await notion(token, 'PATCH', `/pages/${i.page_id}`, { properties: propriedades(i, false) })
    if (r.status === 200) {
      // A ficha é um extra: se falhar, a tarefa já está certa e o erro só vai para o log.
      try { await atualizarFicha(token, i.page_id, i) } catch (err) { console.error(`ficha ${i.protocolo}: ${String(err).slice(0, 200)}`) }
      return { ok: true, page_id: i.page_id }
    }
    // Página apagada/arquivada no Notion ou sem acesso: cria de novo.
    if (!(r.status === 404 || (r.status === 400 && /archiv/i.test(r.text)))) return { ok: false, erro: `${r.status}: ${r.text.slice(0, 300)}` }
  }
  const r = await notion(token, 'POST', '/pages', {
    parent: { database_id: databaseId },
    icon: { type: 'emoji', emoji: '🎫' },
    properties: propriedades(i, true),
    children: blocos(i),
  })
  if (r.status === 200 && typeof r.data.id === 'string') return { ok: true, page_id: r.data.id as string }
  return { ok: false, erro: `${r.status}: ${r.text.slice(0, 300)}` }
}

/**
 * Quem escolhe Responsável/Contribuintes direto no Notion também precisa aparecer na coluna de cada pessoa:
 * olha as páginas editadas nos últimos minutos e acerta a "Equipe". Roda a cada chamada (o agendador chama a cada 2 min).
 */
async function acertarEquipe(token: string, databaseId: string): Promise<number> {
  const desde = new Date(Date.now() - 6 * 60 * 1000).toISOString()
  const q = await notion(token, 'POST', `/databases/${databaseId}/query`, {
    filter: { timestamp: 'last_edited_time', last_edited_time: { on_or_after: desde } },
    page_size: 50,
  })
  if (q.status !== 200) { console.error(`equipe: consulta ${q.status}: ${q.text.slice(0, 200)}`); return 0 }
  let n = 0
  for (const pg of (q.data.results as { id: string; properties: Record<string, never> }[] | undefined) ?? []) {
    const alvo = equipeCorrigida(pg.properties)
    if (!alvo) continue
    const r = await notion(token, 'PATCH', `/pages/${pg.id}`, { properties: { Equipe: { multi_select: alvo.map((name) => ({ name })) } } })
    if (r.status === 200) n++
    else console.error(`equipe ${pg.id}: ${r.status}: ${r.text.slice(0, 200)}`)
    await espera(350)
  }
  return n
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)
  const segredo = req.headers.get('x-chamados-notion-secret')
  if (!segredo) return json({ error: 'unauthorized' }, 401)
  const token = Deno.env.get('NOTION_TOKEN')
  // Sem token não reserva nada: a fila espera até o segredo ser configurado.
  if (!token) return json({ error: 'NOTION_TOKEN não configurado' }, 503)

  let lote: { database_id: string; itens: Item[] }
  try {
    lote = await rpc('notion_lote', { p_segredo: segredo })
  } catch (err) {
    const msg = String(err)
    if (/42501|Segredo/.test(msg)) return json({ error: 'unauthorized' }, 401)
    console.error(msg)
    return json({ error: 'lote_indisponivel' }, 500)
  }

  const resultados: Record<string, unknown>[] = []
  for (const item of lote.itens) {
    let r: { ok: boolean; page_id?: string; erro?: string }
    try { r = await sincronizar(token, lote.database_id, item) } catch (err) { r = { ok: false, erro: String(err).slice(0, 300) } }
    if (!r.ok) console.error(`notion ${item.protocolo}: ${r.erro}`)
    resultados.push({ chamado_id: item.chamado_id, envio_ids: item.envio_ids, ...r })
    await espera(350) // limite da API do Notion: ~3 chamadas por segundo
  }
  if (resultados.length) await rpc('notion_confirmar', { p_segredo: segredo, p_resultados: resultados })
  let equipe = 0
  try { equipe = await acertarEquipe(token, lote.database_id) } catch (err) { console.error(`equipe: ${String(err).slice(0, 200)}`) }
  return json({ itens: resultados.length, ok: resultados.filter((r) => r.ok).length, equipe })
})
