import { describe, expect, it } from 'vitest';
import { indicadores, noFiltro, ordenar, quemAbriu } from './fila';
import type { Chamado, Pessoa, Setor } from './tipos';

const base: Chamado = {
  id: '', protocolo: '', descricao: 'x', solicitante_id: 's', sistema_id: 1, urgencia: 0, status: 'aberto',
  responsavel_id: null, assumido_em: null, prazo_assumir_em: '2026-10-03T10:00:00Z', prazo_em: '2026-10-03T10:00:00Z', prints: [], criado_em: '2026-10-01T10:00:00Z', atualizado_em: '', resolvido_em: null,
};
const c = (p: Partial<Chamado>): Chamado => ({ ...base, ...p });

const lista = [
  c({ id: 'a', urgencia: 0, prazo_assumir_em: '2026-10-03T09:00:00Z' }),
  c({ id: 'b', urgencia: 3, responsavel_id: 'kaio', status: 'andamento', prazo_em: '2026-10-01T12:00:00Z' }),
  c({ id: 'c', urgencia: 3, prazo_assumir_em: '2026-10-01T12:00:00Z' }),
  c({ id: 'd', urgencia: 0, prazo_assumir_em: '2026-10-03T11:00:00Z' }),
  c({ id: 'e', urgencia: 1, responsavel_id: 'kaio', status: 'resolvido', resolvido_em: 'x' }),
];

describe('ordenar', () => {
  it('sem responsável → prazo mais próximo → resolvidos por último', () =>
    expect(ordenar(lista).map((x) => x.id)).toEqual(['c', 'a', 'd', 'b', 'e']));
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
    expect(indicadores(lista, 'kaio', new Date('2026-10-02T00:00:00Z').getTime())).toEqual({ emAberto: 4, semResponsavel: 3, muitoUrgente: 2, meus: 1, atrasados: 2 }));
});

describe('quemAbriu', () => {
  const setores: Setor[] = [{ id: 4, nome: 'Jurídico', ordem: 4 }];
  const pessoas = new Map<string, Pessoa>([
    ['tam', { id: 'tam', nome: 'Tamira', setor_id: 4, papel: 'solicitante', ativo: true }],
    ['kaio', { id: 'kaio', nome: 'Kaio', setor_id: null, papel: 'dev', ativo: true }],
  ]);
  it('cadastro ligado', () => expect(quemAbriu(c({ solicitante_id: 'tam', solicitante_nome: 'TAMIRA', solicitante_cargo: 'Advogada' }), pessoas, setores))
    .toEqual({ nome: 'Tamira', cargo: 'Advogada', setor: 'Jurídico', setorChave: '4', cadastrado: true }));
  it('sem cadastro, setor da lista', () => expect(quemAbriu(c({ solicitante_id: null, solicitante_nome: 'Maria Silva', solicitante_cargo: 'Estagiária', setor_id: 4 }), pessoas, setores))
    .toEqual({ nome: 'Maria Silva', cargo: 'Estagiária', setor: 'Jurídico', setorChave: '4', cadastrado: false }));
  it('setor "Outro"', () => expect(quemAbriu(c({ solicitante_id: null, solicitante_nome: 'Pedro', solicitante_cargo: 'Vendedor', setor_id: null, setor_outro: 'Comercial' }), pessoas, setores))
    .toMatchObject({ setor: 'Comercial', setorChave: 'outro' }));
  it('dev sem setor; cargo antigo do contexto do hub', () => expect(quemAbriu(c({ solicitante_id: 'kaio', contexto: { cargo: 'Dev' } }), pessoas, setores))
    .toMatchObject({ nome: 'Kaio', cargo: 'Dev', setor: null, setorChave: 'dev' }));
});
