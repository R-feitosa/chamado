import { describe, expect, it } from 'vitest';
import { atrasado, etapaAtual, minutosPorExtenso, situacaoAssumir, situacaoResolver, taxaAssumidoNoPrazo, taxaNoPrazo, textoPrazo } from './sla';
import type { Chamado } from './tipos';

const H = 3_600_000;
const agora = new Date('2026-10-10T12:00:00Z').getTime();
const iso = (h: number) => new Date(agora + h * H).toISOString(); // h negativo = passado
const base: Chamado = {
  id: '', protocolo: '', descricao: 'x', solicitante_id: 's', sistema_id: 1, urgencia: 3, status: 'aberto',
  responsavel_id: null, assumido_em: null, prazo_assumir_em: iso(1), prazo_em: iso(5), prints: [], criado_em: iso(-1), atualizado_em: '', resolvido_em: null,
};
const c = (p: Partial<Chamado>): Chamado => ({ ...base, ...p });
const andamento = (p: Partial<Chamado>) => c({ status: 'andamento', responsavel_id: 'kaio', assumido_em: iso(-0.5), ...p });

describe('etapas', () => {
  it('sem responsável corre o prazo de assumir', () => expect(etapaAtual(c({}))).toBe('assumir'));
  it('com responsável corre o prazo de resolver', () => expect(etapaAtual(andamento({}))).toBe('resolver'));
});

describe('situação', () => {
  it('assumir no prazo / perto / atrasado', () => {
    expect(situacaoAssumir(c({ criado_em: iso(-1), prazo_assumir_em: iso(7) }), agora)).toEqual({ situacao: 'no_prazo', diferenca: 7 * H });
    expect(situacaoAssumir(c({ criado_em: iso(-7), prazo_assumir_em: iso(1) }), agora).situacao).toBe('perto');
    expect(situacaoAssumir(c({ criado_em: iso(-5), prazo_assumir_em: iso(-2) }), agora)).toEqual({ situacao: 'atrasado', diferenca: 2 * H });
  });
  it('assumido fora do prazo fica registrado', () =>
    expect(situacaoAssumir(c({ assumido_em: iso(-1), prazo_assumir_em: iso(-3) }), agora)).toEqual({ situacao: 'estourado', diferenca: 2 * H }));
  it('resolvido no prazo e fora', () => {
    expect(situacaoResolver(c({ status: 'resolvido', resolvido_em: iso(-2), prazo_em: iso(-1) }), agora).situacao).toBe('cumprido');
    expect(situacaoResolver(c({ status: 'resolvido', resolvido_em: iso(-1), prazo_em: iso(-4) }), agora)).toEqual({ situacao: 'estourado', diferenca: 3 * H });
  });
});

describe('textoPrazo e atrasado', () => {
  it('textos por etapa', () => {
    expect(textoPrazo(c({ prazo_assumir_em: iso(3) }), agora)).toBe('assumir em 3 h');
    expect(textoPrazo(c({ prazo_assumir_em: iso(-2), criado_em: iso(-3) }), agora)).toBe('assumir atrasado 2 h');
    expect(textoPrazo(andamento({ prazo_em: iso(5) }), agora)).toBe('resolver em 5 h');
    expect(textoPrazo(andamento({ prazo_em: iso(-3), criado_em: iso(-5) }), agora)).toBe('atrasado 3 h');
    expect(textoPrazo(c({ status: 'resolvido', responsavel_id: 'k', resolvido_em: iso(-2), prazo_em: iso(-1) }), agora)).toBe('resolvido no prazo');
  });
  it('atrasado olha a etapa atual', () => {
    expect(atrasado(c({ prazo_assumir_em: iso(-1), criado_em: iso(-2) }), agora)).toBe(true);
    // assumiu atrasado, mas o prazo de resolver ainda não venceu
    expect(atrasado(andamento({ prazo_assumir_em: iso(-1), prazo_em: iso(4) }), agora)).toBe(false);
    expect(atrasado(c({ status: 'resolvido', resolvido_em: iso(-1), prazo_em: iso(-9) }), agora)).toBe(false);
  });
});

describe('taxas', () => {
  it('resolvidos no prazo', () => expect(taxaNoPrazo([
    c({ status: 'resolvido', resolvido_em: iso(-2), prazo_em: iso(-1) }),
    c({ status: 'resolvido', resolvido_em: iso(-1), prazo_em: iso(-4) }),
    c({ status: 'resolvido', resolvido_em: iso(-5), prazo_em: iso(-4) }),
  ])).toBe(67));
  it('assumidos no prazo ignora quem não foi assumido', () => expect(taxaAssumidoNoPrazo([
    c({ assumido_em: iso(-2), prazo_assumir_em: iso(-1) }), c({ assumido_em: iso(-1), prazo_assumir_em: iso(-3) }), c({}),
  ])).toBe(50));
  it('vazio', () => expect(taxaNoPrazo([])).toBeNull());
});

describe('minutosPorExtenso', () => {
  it('formata', () => {
    expect(minutosPorExtenso(15)).toBe('15 min');
    expect(minutosPorExtenso(120)).toBe('2 h');
    expect(minutosPorExtenso(90)).toBe('1 h 30 min');
    expect(minutosPorExtenso(2880)).toBe('2 dias');
    expect(minutosPorExtenso(1440)).toBe('1 dia');
  });
});
