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
  envio_ids: number[]
}

const texto = (t: string | null | undefined) => (t ? [{ type: 'text', text: { content: t.slice(0, 2000) } }] : [])
const data = (iso: string | null | undefined) => (iso ? { start: iso } : null)

/** Propriedades da base "Acompanhamento de Tarefas · P&D". Na criação também vão Tipo e Abertura. */
export function propriedades(i: Item, criar: boolean): Record<string, unknown> {
  const p: Record<string, unknown> = {
    Tarefa: { title: texto(i.titulo) },
    Responsável: { select: i.responsavel ? { name: i.responsavel } : null },
    Contribuintes: { multi_select: (i.contribuintes ?? []).map((name) => ({ name })) },
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

/** Corpo da página na criação: resumo do chamado e a descrição escrita por quem abriu (prints ficam só na Central). */
export function blocos(i: Item): unknown[] {
  const b: unknown[] = [
    {
      object: 'block', type: 'callout',
      callout: {
        icon: { type: 'emoji', emoji: '🎫' },
        rich_text: texto(`${i.protocolo} · ${i.sistema ?? 'Sistema'} · ${i.urgencia}. Criado pela Central de Chamados: o status, o responsável e a conclusão são atualizados automaticamente.`),
      },
    },
    { object: 'block', type: 'heading_3', heading_3: { rich_text: texto('Descrição do chamado') } },
  ]
  for (const linha of (i.descricao ?? '').split(/\n{2,}/)) for (const p of pedacos(linha)) b.push(paragrafo(p))
  if (b.length === 2) b.push(paragrafo('(sem descrição)'))
  return b.slice(0, 95) // limite da API: 100 blocos por chamada
}
