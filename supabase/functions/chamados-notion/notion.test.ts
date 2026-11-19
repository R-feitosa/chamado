import { describe, expect, it } from 'vitest'
import { blocos, pedacos, propriedades, type Item } from './notion'

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
  it('corpo com resumo, título e um parágrafo por bloco de texto', () => {
    const b = blocos(base) as any[]
    expect(b[0].type).toBe('callout')
    expect(b[1].heading_3.rich_text[0].text.content).toBe('Descrição do chamado')
    expect(b.slice(2).map((x) => x.paragraph.rich_text[0].text.content)).toEqual(['Tela não abre', 'Desde hoje cedo.'])
  })
  it('texto longo é dividido sem passar de 2000 caracteres', () => {
    const p = pedacos('palavra '.repeat(1000))
    expect(p.length).toBeGreaterThan(3)
    expect(Math.max(...p.map((x) => x.length))).toBeLessThanOrEqual(1900)
  })
})
