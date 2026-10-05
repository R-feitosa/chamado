import { describe, expect, it } from 'vitest';
import { conquistasProximas, nivelDe, novasDesde, pct, proximoTier, raridadeAtual, sinalXp, valorMissao, type Conquista, type Notificacao } from './gamificacao';

const NIVEIS = [
  { nivel: 1, nome: 'Novato', xp_minimo: 0 }, { nivel: 2, nome: 'Aprendiz', xp_minimo: 500 }, { nivel: 3, nome: 'Operador', xp_minimo: 1200 },
  { nivel: 4, nome: 'Especialista', xp_minimo: 2500 }, { nivel: 5, nome: 'Expert', xp_minimo: 5000 }, { nivel: 6, nome: 'Elite', xp_minimo: 10000 },
  { nivel: 7, nome: 'Master', xp_minimo: 20000 },
];

// Mesmos casos do teste do banco (supabase/testes/gamificacao.sql, bloco 13): as duas regras precisam bater.
describe('nivelDe (paridade com chamados.gam_nivel)', () => {
  it('limites', () => {
    expect(nivelDe(0, NIVEIS).nivel).toBe(1);
    expect(nivelDe(499, NIVEIS).nivel).toBe(1);
    expect(nivelDe(500, NIVEIS).nivel).toBe(2);
  });
  it('2.840 XP → nível 4, faltam 2.160', () => {
    const n = nivelDe(2840, NIVEIS);
    expect(n).toMatchObject({ nivel: 4, nome: 'Especialista', xp_nivel: 2500, xp_proximo: 5000, faltam: 2160 });
    expect(n.progresso).toBeCloseTo(340 / 2500, 4);
  });
  it('acima do último nível: intervalo anterior × 1,25', () => {
    expect(nivelDe(20000, NIVEIS)).toMatchObject({ nivel: 7, xp_proximo: 32500 });
    expect(nivelDe(32500, NIVEIS)).toMatchObject({ nivel: 8, nome: 'Master 2' });
  });
  it('XP negativo vira zero', () => expect(nivelDe(-30, NIVEIS).xp).toBe(0));
});

const conquista = (valor: number, desbloq: boolean[]): Conquista => ({
  codigo: 'guardiao_sla', nome: 'Guardião do SLA', descricao: '', icone: 'escudo', raridade: 'rara', metrica: 'resolvidos_sla', valor,
  tiers: [10, 50, 100].map((limite, i) => ({ tier: i + 1, nome: ['Bronze', 'Prata', 'Ouro'][i], limite, xp: 10, raridade: (['comum', 'incomum', 'rara'] as const)[i],
    desbloqueada_em: desbloq[i] ? '2026-10-05T10:00:00Z' : null })),
});

describe('conquistas', () => {
  it('próximo tier e quanto falta', () => {
    expect(proximoTier(conquista(42, [true, false, false]))).toMatchObject({ tier: { nome: 'Prata', limite: 50 }, faltam: 8, progresso: 0.84 });
    expect(proximoTier(conquista(120, [true, true, true]))).toBeNull();
  });
  it('raridade do maior tier obtido', () => {
    expect(raridadeAtual(conquista(42, [true, false, false]))).toBe('comum');
    expect(raridadeAtual(conquista(60, [true, true, false]))).toBe('incomum');
    expect(raridadeAtual(conquista(0, [false, false, false]))).toBe('comum');
  });
  it('próximas: mais adiantadas primeiro', () => {
    const a = { ...conquista(42, [true, false, false]), codigo: 'a' };
    const b = { ...conquista(2, [false, false, false]), codigo: 'b' };
    expect(conquistasProximas([b, a]).map((x) => x.conquista.codigo)).toEqual(['a', 'b']);
  });
});

describe('formatação', () => {
  it('XP com sinal', () => { expect(sinalXp(25)).toBe('+25 XP'); expect(sinalXp(-10)).toBe('−10 XP'); expect(sinalXp(4820)).toBe('+4.820 XP'); });
  it('porcentagem', () => { expect(pct(0.94)).toBe('94%'); expect(pct(null)).toBe('—'); });
  it('missão em % e em contagem', () => {
    expect(valorMissao({ metrica: 'sla_equipe_pct', valor: 92, meta: 95 })).toBe('92% / 95%');
    expect(valorMissao({ metrica: 'resolvidos_sla', valor: 2, meta: 3 })).toBe('2 / 3');
  });
});

describe('novasDesde', () => {
  const n = (id: number, lida = false): Notificacao => ({ id, tipo: 'xp', titulo: '', detalhe: null, xp: 5, dados: {}, criada_em: '', lida });
  it('só não lidas depois da última vista, em ordem', () => expect(novasDesde([n(5), n(3), n(4, true), n(2)], 2).map((x) => x.id)).toEqual([3, 5]));
});
