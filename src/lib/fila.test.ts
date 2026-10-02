import { describe, expect, it } from 'vitest';
import { indicadores, noFiltro, ordenar } from './fila';
import type { Chamado } from './tipos';

const base: Chamado = {
  id: '', protocolo: '', descricao: 'x', solicitante_id: 's', sistema_id: 1, urgencia: 0, status: 'aberto',
  responsavel_id: null, assumido_em: null, prints: [], criado_em: '2026-10-01T10:00:00Z', atualizado_em: '', resolvido_em: null,
};
const c = (p: Partial<Chamado>): Chamado => ({ ...base, ...p });

const lista = [
  c({ id: 'a', urgencia: 0, criado_em: '2026-10-01T09:00:00Z' }),
  c({ id: 'b', urgencia: 3, responsavel_id: 'kaio', status: 'andamento' }),
  c({ id: 'c', urgencia: 3 }),
  c({ id: 'd', urgencia: 0, criado_em: '2026-10-01T11:00:00Z' }),
  c({ id: 'e', urgencia: 1, responsavel_id: 'kaio', status: 'resolvido', resolvido_em: 'x' }),
];

describe('ordenar', () => {
  it('sem responsável → urgência → mais recente', () =>
    expect(ordenar(lista).map((x) => x.id)).toEqual(['c', 'd', 'a', 'b', 'e']));
});

describe('filtros', () => {
  const ids = (f: Parameters<typeof noFiltro>[0]) => lista.filter((x) => noFiltro(f, x, 'kaio')).map((x) => x.id);
  it('em aberto', () => expect(ids('abertos')).toEqual(['a', 'b', 'c', 'd']));
  it('sem responsável', () => expect(ids('livres')).toEqual(['a', 'c', 'd']));
  it('meus', () => expect(ids('meus')).toEqual(['b']));
  it('resolvidos', () => expect(ids('resolvidos')).toEqual(['e']));
});

describe('indicadores', () => {
  it('conta só os abertos', () =>
    expect(indicadores(lista, 'kaio')).toEqual({ emAberto: 4, semResponsavel: 3, muitoUrgente: 2, meus: 1 }));
});
