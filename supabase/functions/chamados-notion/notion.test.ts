import { describe, expect, it } from 'vitest'
import { blocos, equipeCorrigida, pedacos, propriedades, textoFicha, textoHistorico, TITULO_FICHA, TITULO_HISTORICO, type Item } from './notion'

const base: Item = {
  chamado_id: 'c1', page_id: null, protocolo: 'TI-0450', titulo: 'TI-0450 · CRM · Tela não abre', status: 'Em andamento',
  responsavel: 'KAIO', prioridade: 'P1 · Alta', sistema_projeto: 'CRM', solicitante: 'Ana · Advogada · Jurídico',
  abertura: '2026-11-19T13:00:00+00:00', prazo: '2026-11-19T21:00:00+00:00', conclusao: null,
  ultimo_andamento: 'Assumido na Central por Kaio', data_andamento: '2026-11-19T13:05:00+00:00',
  link: 'https://chamado-jdc5.vercel.app', descricao: 'Tela não abre\n\nDesde hoje cedo.', sistema: 'CRM', urgencia: 'Urgente', envio_ids: [1],
}

describe('propriedades', () => {
  it('criação leva Tipo Chamado e Abertura', () => {
    const p = propriedades(base, true) as Record<string, any>
    expect(p.Tipo).toEqual({ select: { name: 'Chamado' } })
    expect(p.Abertura).toEqual({ date: { start: base.abertura } })
    expect(p.Responsável).toEqual({ select: { name: 'KAIO' } })
    expect(p.Status).toEqual({ status: { name: 'Em andamento' } })
    expect(p.Tarefa.title[0].text.content).toBe('TI-0450 · CRM · Tela não abre')
  })
  it('leva os contribuintes (vazio quando não há)', () => {
    expect((propriedades({ ...base, contribuintes: ['ALDO', 'RUAN'] }, false) as Record<string, any>).Contribuintes)
      .toEqual({ multi_select: [{ name: 'ALDO' }, { name: 'RUAN' }] })
    expect((propriedades(base, false) as Record<string, any>).Contribuintes).toEqual({ multi_select: [] })
  })
  it('Equipe junta responsável e contribuintes, sem repetir; sem responsável fica só quem contribui', () => {
    expect((propriedades({ ...base, contribuintes: ['ALDO', 'KAIO', 'ÉSAU'] }, false) as Record<string, any>).Equipe)
      .toEqual({ multi_select: [{ name: 'KAIO' }, { name: 'ALDO' }, { name: 'ÉSAU' }] })
    expect((propriedades({ ...base, responsavel: null, contribuintes: ['ALDO'] }, false) as Record<string, any>).Equipe)
      .toEqual({ multi_select: [{ name: 'ALDO' }] })
    expect((propriedades(base, false) as Record<string, any>).Equipe).toEqual({ multi_select: [{ name: 'KAIO' }] })
  })
  it('atualização não mexe em Tipo/Abertura e limpa o responsável ao desassumir', () => {
    const p = propriedades({ ...base, responsavel: null, status: 'A fazer' }, false) as Record<string, any>
    expect(p.Tipo).toBeUndefined()
    expect(p.Abertura).toBeUndefined()
    expect(p.Responsável).toEqual({ select: null })
    expect(p.Conclusão).toEqual({ date: null })
  })
  it('concluída leva a data de conclusão', () => {
    const p = propriedades({ ...base, status: 'Concluída', conclusao: '2026-11-19T15:00:00+00:00' }, false) as Record<string, any>
    expect(p.Conclusão).toEqual({ date: { start: '2026-11-19T15:00:00+00:00' } })
  })
})

describe('blocos e pedaços', () => {
  it('corpo com ficha, histórico, título e um parágrafo por bloco de texto', () => {
    const b = blocos(base) as any[]
    expect(b[0].callout.icon.emoji).toBe('🎫')
    expect(b[1].callout.icon.emoji).toBe('🕘')
    expect(b[2].heading_3.rich_text[0].text.content).toBe('Descrição do chamado')
    expect(b.slice(3).map((x) => x.paragraph.rich_text[0].text.content)).toEqual(['Tela não abre', 'Desde hoje cedo.'])
  })
  it('texto longo é dividido sem passar de 2000 caracteres', () => {
    const p = pedacos('palavra '.repeat(1000))
    expect(p.length).toBeGreaterThan(3)
    expect(Math.max(...p.map((x) => x.length))).toBeLessThanOrEqual(1900)
  })
})

describe('equipeCorrigida (edição feita direto no Notion)', () => {
  const ms = (...n: string[]) => ({ multi_select: n.map((name) => ({ name })) })
  it('responsável + contribuintes escolhidos no Notion entram na Equipe', () => {
    expect(equipeCorrigida({ Responsável: { select: { name: 'ALDO' } }, Contribuintes: ms('RUAN', 'ÉSAU'), Equipe: ms('ALDO') }))
      .toEqual(['ALDO', 'RUAN', 'ÉSAU'])
  })
  it('nada a fazer quando já está certa (em qualquer ordem)', () => {
    expect(equipeCorrigida({ Responsável: { select: { name: 'ALDO' } }, Contribuintes: ms('RUAN'), Equipe: ms('RUAN', 'ALDO') })).toBeNull()
  })
  it('tirar um contribuinte tira da Equipe', () => {
    expect(equipeCorrigida({ Responsável: { select: { name: 'ALDO' } }, Contribuintes: ms(), Equipe: ms('ALDO', 'RUAN') })).toEqual(['ALDO'])
  })
  it('sem responsável nem contribuintes, não mexe', () => {
    expect(equipeCorrigida({ Responsável: { select: null }, Contribuintes: ms(), Equipe: ms('KAIO') })).toBeNull()
  })
})

describe('ficha e histórico da página', () => {
  const comPessoas: Item = {
    ...base, responsavel: 'ALDO', contribuintes: ['RUAN', 'ÉSAU'],
    ficha: [['Responsável', 'Aldo Júnior · assumiu em 23/11/2026 09:00'], ['Contribuintes', 'Ruan (desde 23/11/2026 09:05), Esaú (desde 23/11/2026 09:06)']],
    historico: [['23/11/2026 08:50', 'Chamado aberto'], ['23/11/2026 09:00', 'Assumido por Aldo Júnior'], ['23/11/2026 09:05', 'Ruan entrou como contribuinte']],
  }
  const plano = (t: { text: { content: string } }[]) => t.map((x) => x.text.content).join('')
  it('ficha começa pelo título (é assim que a função acha o bloco) e traz cada informação numa linha', () => {
    const t = plano(textoFicha(comPessoas))
    expect(t.startsWith(`${TITULO_FICHA} · TI-0450`)).toBe(true)
    expect(t).toContain('Responsável: Aldo Júnior · assumiu em 23/11/2026 09:00\n')
    expect(t).toContain('Contribuintes: Ruan (desde 23/11/2026 09:05), Esaú (desde 23/11/2026 09:06)\n')
    expect(t.endsWith('Abrir na Central ↗')).toBe(true)
    expect(textoFicha(comPessoas).at(-1)!.text).toEqual({ content: 'Abrir na Central ↗', link: { url: base.link } })
  })
  it('histórico em ordem, um evento por linha, e mensagem quando vazio', () => {
    const t = plano(textoHistorico(comPessoas))
    expect(t.startsWith(TITULO_HISTORICO)).toBe(true)
    expect(t.split('\n').slice(1)).toEqual(['23/11/2026 08:50  Chamado aberto', '23/11/2026 09:00  Assumido por Aldo Júnior', '23/11/2026 09:05  Ruan entrou como contribuinte'])
    expect(plano(textoHistorico(base))).toBe('Histórico\nSem movimentações ainda.')
  })
  it('histórico longo mostra os últimos 40 e cabe no limite de 100 trechos da API', () => {
    const muitos = { ...base, historico: Array.from({ length: 70 }, (_, k) => [`d${k}`, `e${k}`] as [string, string]) }
    const r = textoHistorico(muitos)
    expect(r.length).toBeLessThanOrEqual(100)
    expect(plano(r)).toContain('(últimos 40 de 70)')
    expect(plano(r).endsWith('d69  e69')).toBe(true)
  })
})
