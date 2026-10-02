import { describe, expect, it } from 'vitest';
import { duracao, inicioDoPeriodo, matriz, porTecnico, resolvidosNoPeriodo, tempoDaFila, temposMedios } from './analytics';
import type { Chamado } from './tipos';

const H = 3_600_000;
const agora = new Date('2026-10-10T12:00:00Z').getTime();
const iso = (horasAtras: number) => new Date(agora - horasAtras * H).toISOString();
const base: Chamado = {
  id: '', protocolo: '', descricao: 'x', solicitante_id: 's', sistema_id: 1, urgencia: 0, status: 'aberto',
  responsavel_id: null, assumido_em: null, prazo_assumir_em: iso(0), prazo_em: iso(0), prints: [], criado_em: iso(1), atualizado_em: '', resolvido_em: null,
};
const c = (p: Partial<Chamado>): Chamado => ({ ...base, ...p });

const lista = [
  c({ id: 'a', criado_em: iso(5) }),                                               // aberto, sem resp, 5 h
  c({ id: 'b', criado_em: iso(30), status: 'andamento', responsavel_id: 'kaio', assumido_em: iso(28) }),
  c({ id: 'c', criado_em: iso(10), status: 'resolvido', responsavel_id: 'kaio', assumido_em: iso(9), resolvido_em: iso(6), sistema_id: 1 }),
  c({ id: 'd', criado_em: iso(20), status: 'resolvido', responsavel_id: 'aldo', assumido_em: iso(18), resolvido_em: iso(12), sistema_id: 2 }),
  c({ id: 'e', criado_em: iso(24 * 60), status: 'resolvido', responsavel_id: 'kaio', assumido_em: iso(24 * 59), resolvido_em: iso(24 * 58), sistema_id: 2 }),
];

describe('duracao', () => {
  it('formata faixas', () => {
    expect(duracao(30_000)).toBe('agora');
    expect(duracao(12 * 60_000)).toBe('12 min');
    expect(duracao(3 * H + 20 * 60_000)).toBe('3 h 20 min');
    expect(duracao(14 * H)).toBe('14 h');
    expect(duracao(52 * H)).toBe('2 d 4 h');
    expect(duracao(null)).toBe('—');
  });
  it('nunca mostra 60 min', () => {
    expect(duracao(59.7 * 60_000)).toBe('1 h');
    expect(duracao(2 * H + 59.7 * 60_000)).toBe('3 h');
    expect(duracao(23.9 * H)).toBe('24 h');
    expect(duracao(47.8 * H)).toBe('2 d');
  });
});

describe('tempoDaFila', () => {
  it('espera média sem responsável e mais antigo em aberto', () =>
    expect(tempoDaFila(lista, agora)).toEqual({ esperaMediaSemResponsavel: 5 * H, maisAntigo: 30 * H }));
  it('fila vazia', () => expect(tempoDaFila([], agora)).toEqual({ esperaMediaSemResponsavel: null, maisAntigo: null }));
});

describe('período de 7 dias', () => {
  const desde = inicioDoPeriodo('7', agora);
  it('ignora o resolvido há 58 dias', () => expect(resolvidosNoPeriodo(lista, desde).map((x) => x.id)).toEqual(['c', 'd']));
  it('tempos médios', () =>
    // assumir: b 2 h, c 1 h, d 2 h → 5/3 h; resolver: c 4 h, d 8 h → 6 h
    expect(temposMedios(lista, desde)).toEqual({ mediaAssumir: (5 / 3) * H, mediaResolver: 6 * H }));
  it('por técnico inclui quem não resolveu', () =>
    expect(porTecnico(lista, ['ruan', 'aldo', 'kaio'], desde)).toEqual([
      { id: 'kaio', resolvidos: 1, emAndamento: 1, mediaResolver: 4 * H },
      { id: 'aldo', resolvidos: 1, emAndamento: 0, mediaResolver: 8 * H },
      { id: 'ruan', resolvidos: 0, emAndamento: 0, mediaResolver: null },
    ]));
});

describe('matriz', () => {
  it('conta técnico × sistema em todo o período', () => {
    const m = matriz(resolvidosNoPeriodo(lista, inicioDoPeriodo('tudo', agora)), (x) => x.sistema_id);
    expect(Object.fromEntries(m.get('kaio')!)).toEqual({ 1: 1, 2: 1 });
    expect(Object.fromEntries(m.get('aldo')!)).toEqual({ 2: 1 });
  });
});
