// Monta o corpo das chamadas à API do Notion a partir do item que o banco devolve (chamados.notion_item).
// Sem nenhuma API do Deno: roda igual na Edge Function e nos testes (Vitest).

export interface Item {
  chamado_id: string
  page_id: string | null
  protocolo: string
  titulo: string
  status: 'A fazer' | 'Em andamento' | 'Concluída'
  responsavel: string | null
  prioridade: string
  sistema_projeto: string
  solicitante: string
  abertura: string
  prazo: string | null
  conclusao: string | null
  ultimo_andamento: string | null
  data_andamento: string | null
  link: string | null
  descricao: string | null
  sistema: string | null
  urgencia: string
  /** Opções de "Contribuintes" (quem ajuda, além do responsável). */
  contribuintes?: string[]
  /** Ficha do chamado: pares [rótulo, valor] já formatados pelo banco. */
  ficha?: [string, string][]
  /** Histórico: pares [data, o que aconteceu], do mais antigo ao mais recente. */
  historico?: [string, string][]
  envio_ids: number[]
}

const texto = (t: string | null | undefined) => (t ? [{ type: 'text', text: { content: t.slice(0, 2000) } }] : [])
const data = (iso: string | null | undefined) => (iso ? { start: iso } : null)

/** Todos na tarefa (responsável + contribuintes, sem repetir): o quadro da equipe agrupa por "Equipe". */
export function equipe(i: Item): string[] {
  return [...new Set([i.responsavel, ...(i.contribuintes ?? [])].filter((n): n is string => !!n))]
}

type Props = Record<string, { select?: { name: string } | null; multi_select?: { name: string }[] } | undefined>

/**
 * Página editada à mão no Notion: "Equipe" tem que ser Responsável + Contribuintes (é ela que põe o cartão na
 * coluna de cada pessoa no quadro da equipe). Devolve a Equipe certa, ou null se já está certa (ou não há ninguém).
 */
export function equipeCorrigida(props: Props): string[] | null {
  const nomes = (k: string) => (props[k]?.multi_select ?? []).map((o) => o.name)
  const alvo = [...new Set([props['Responsável']?.select?.name ?? null, ...nomes('Contribuintes')].filter((n): n is string => !!n))]
  if (!alvo.length) return null
  const atual = new Set(nomes('Equipe'))
  return atual.size === alvo.length && alvo.every((n) => atual.has(n)) ? null : alvo
}

/** Propriedades da base "Acompanhamento de Tarefas · P&D". Na criação também vão Tipo e Abertura. */
export function propriedades(i: Item, criar: boolean): Record<string, unknown> {
  const p: Record<string, unknown> = {
    Tarefa: { title: texto(i.titulo) },
    Responsável: { select: i.responsavel ? { name: i.responsavel } : null },
    Contribuintes: { multi_select: (i.contribuintes ?? []).map((name) => ({ name })) },
    Equipe: { multi_select: equipe(i).map((name) => ({ name })) },
    Status: { status: { name: i.status } },
    Prioridade: { select: { name: i.prioridade } },
    'Sistema/Projeto': { multi_select: [{ name: i.sistema_projeto }] },
    Solicitante: { rich_text: texto(i.solicitante) },
    Prazo: { date: data(i.prazo) },
    Conclusão: { date: i.status === 'Concluída' ? data(i.conclusao) : null },
    'Último andamento': { rich_text: texto(i.ultimo_andamento) },
    'Data do andamento': { date: data(i.data_andamento) },
  }
  if (i.link) p['Link (PR/sistema)'] = { url: i.link }
  if (criar) {
    p.Tipo = { select: { name: 'Chamado' } }
    p.Abertura = { date: data(i.abertura) }
  }
  return p
}

/** Divide o texto em pedaços que cabem num bloco do Notion (2000 caracteres), sem cortar palavras quando dá. */
export function pedacos(t: string, max = 1900): string[] {
  const out: string[] = []
  let resto = t.trim()
  while (resto.length > max) {
    let corte = resto.lastIndexOf(' ', max)
    if (corte < max * 0.5) corte = max
    out.push(resto.slice(0, corte).trimEnd())
    resto = resto.slice(corte).trimStart()
  }
  if (resto) out.push(resto)
  return out
}

const paragrafo = (t: string) => ({ object: 'block', type: 'paragraph', paragraph: { rich_text: texto(t) } })

type Trecho = { type: 'text'; text: { content: string; link?: { url: string } | null }; annotations?: Record<string, unknown> }
const trecho = (t: string, a: Record<string, unknown> = {}, link?: string | null): Trecho =>
  ({ type: 'text', text: { content: t.slice(0, 2000), ...(link ? { link: { url: link } } : {}) }, ...(Object.keys(a).length ? { annotations: a } : {}) })

export const TITULO_FICHA = 'Ficha do chamado'
export const TITULO_HISTORICO = 'Histórico'
const MAX_HISTORICO = 40 // cada linha usa 2 trechos; a API aceita até 100 por bloco

/** Texto da ficha (callout 🎫): rótulos em negrito, uma informação por linha. Reescrito a cada mudança. */
export function textoFicha(i: Item): Trecho[] {
  const r: Trecho[] = [trecho(`${TITULO_FICHA} · ${i.protocolo}`, { bold: true }), trecho('  (atualizada pela Central; anote abaixo da descrição)\n', { italic: true, color: 'gray' })]
  for (const [rotulo, valor] of i.ficha ?? []) r.push(trecho(`${rotulo}: `, { bold: true }), trecho(`${valor}\n`))
  if (i.link) r.push(trecho('Abrir na Central ↗', { bold: true }, i.link))
  else if (r.length) r[r.length - 1].text.content = r[r.length - 1].text.content.replace(/\n$/, '')
  return r
}

/** Texto do histórico (callout 🕘): data em negrito e o que aconteceu; mostra os últimos 40. */
export function textoHistorico(i: Item): Trecho[] {
  const h = i.historico ?? []
  const r: Trecho[] = [trecho(TITULO_HISTORICO, { bold: true })]
  if (h.length > MAX_HISTORICO) r.push(trecho(`  (últimos ${MAX_HISTORICO} de ${h.length})`, { italic: true, color: 'gray' }))
  for (const [quando, oque] of h.slice(-MAX_HISTORICO)) r.push(trecho(`\n${quando}  `, { bold: true }), trecho(oque))
  if (!h.length) r.push(trecho('\nSem movimentações ainda.'))
  return r
}

export const calloutFicha = (i: Item) => ({ object: 'block', type: 'callout', callout: { icon: { type: 'emoji', emoji: '🎫' }, color: 'blue_background', rich_text: textoFicha(i) } })
export const calloutHistorico = (i: Item) => ({ object: 'block', type: 'callout', callout: { icon: { type: 'emoji', emoji: '🕘' }, color: 'gray_background', rich_text: textoHistorico(i) } })

/** Corpo da página na criação: ficha, histórico e a descrição escrita por quem abriu (prints ficam só na Central). */
export function blocos(i: Item): unknown[] {
  const b: unknown[] = [
    calloutFicha(i),
    calloutHistorico(i),
    { object: 'block', type: 'heading_3', heading_3: { rich_text: texto('Descrição do chamado') } },
  ]
  for (const linha of (i.descricao ?? '').split(/\n{2,}/)) for (const p of pedacos(linha)) b.push(paragrafo(p))
  if (b.length === 3) b.push(paragrafo('(sem descrição)'))
  return b.slice(0, 95) // limite da API: 100 blocos por chamada
}
