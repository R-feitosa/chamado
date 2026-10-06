import { describe, expect, it } from 'vitest';
import { avisosDevidos, frequenciaPorExtenso, marcarVistos, noExpediente, REGRAS_PADRAO, seqLembrete } from './alertas';
import { padraoSom } from './som';
import type { Chamado, Urgencia } from './tipos';

const MIN = 60_000;
// Segunda-feira, 6/10/2026, 10:00 em Fortaleza (UTC−3).
const SEG_10H = Date.parse('2026-10-06T13:00:00Z') - 24 * 60 * MIN; // 05/10 (segunda) 10:00 local
const SEG_20H = SEG_10H + 10 * 60 * MIN;
const SAB_10H = SEG_10H + 5 * 24 * 60 * MIN;

function ch(id: string, urgencia: Urgencia, minutosAtras: number, agora: number, extra: Partial<Chamado> = {}): Chamado {
  return { id, protocolo: `TI-${id}`, descricao: 'x', solicitante_id: null, sistema_id: 1, urgencia, status: 'aberto', responsavel_id: null,
    assumido_em: null, prazo_assumir_em: '', prazo_em: '', prints: [], criado_em: new Date(agora - minutosAtras * MIN).toISOString(),
    atualizado_em: '', resolvido_em: null, ...extra };
}

describe('expediente (fuso de Fortaleza)', () => {
  it('segunda 10h dentro, 20h fora, sábado fora', () => {
    expect(noExpediente(SEG_10H)).toBe(true);
    expect(noExpediente(SEG_20H)).toBe(false);
    expect(noExpediente(SAB_10H)).toBe(false);
  });
});

describe('frequência por urgência (espelho de chamados.push_regras)', () => {
  it('seed Balanceado', () => {
    expect(REGRAS_PADRAO.map((r) => [r.nivel, r.repetir_min, r.so_expediente])).toEqual([[3, 5, false], [2, 15, false], [1, 60, true], [0, 240, true]]);
    expect(frequenciaPorExtenso(REGRAS_PADRAO[0])).toBe('a cada 5 min, 24 h');
    expect(frequenciaPorExtenso(REGRAS_PADRAO[3])).toBe('a cada 4 h, no expediente');
  });
  it('seq conta os intervalos desde a abertura', () => {
    expect(seqLembrete(ch('1', 3, 12, SEG_10H), REGRAS_PADRAO[0], SEG_10H)).toBe(2);
    expect(seqLembrete(ch('1', 1, 59, SEG_10H), REGRAS_PADRAO[2], SEG_10H)).toBe(0);
  });
});

describe('avisos na aba', () => {
  it('novo, lembrete no intervalo seguinte e para ao assumir', () => {
    const vistos = new Map<string, number>();
    const c = ch('9', 3, 1, SEG_10H);
    expect(avisosDevidos([c], REGRAS_PADRAO, { dias: [1, 2, 3, 4, 5], inicio: '08:00', fim: '18:00' }, SEG_10H, vistos).map((a) => a.tipo)).toEqual(['novo']);
    expect(avisosDevidos([c], REGRAS_PADRAO, { dias: [1, 2, 3, 4, 5], inicio: '08:00', fim: '18:00' }, SEG_10H + 2 * MIN, vistos)).toEqual([]);
    expect(avisosDevidos([c], REGRAS_PADRAO, { dias: [1, 2, 3, 4, 5], inicio: '08:00', fim: '18:00' }, SEG_10H + 5 * MIN, vistos).map((a) => [a.tipo, a.seq])).toEqual([['lembrete', 1]]);
    expect(avisosDevidos([{ ...c, responsavel_id: 'k', status: 'andamento' }], REGRAS_PADRAO, { dias: [1, 2, 3, 4, 5], inicio: '08:00', fim: '18:00' }, SEG_10H + 30 * MIN, vistos)).toEqual([]);
  });
  it('fora do expediente: meio urgente não lembra; muito urgente lembra', () => {
    const vistos = new Map<string, number>();
    const meio = ch('a', 1, 70, SEG_20H), muito = ch('b', 3, 70, SEG_20H);
    marcarVistos([meio, muito], REGRAS_PADRAO, SEG_20H - 20 * MIN, vistos);
    expect(avisosDevidos([meio, muito], REGRAS_PADRAO, { dias: [1, 2, 3, 4, 5], inicio: '08:00', fim: '18:00' }, SEG_20H, vistos).map((a) => a.chamado.id)).toEqual(['b']);
  });
  it('não avisa o próprio chamado de quem está logado', () => {
    expect(avisosDevidos([ch('c', 2, 0, SEG_10H, { solicitante_id: 'eu' })], REGRAS_PADRAO, { dias: [1], inicio: '08:00', fim: '18:00' }, SEG_10H, new Map(), 'eu')).toEqual([]);
  });
});

describe('som por urgência', () => {
  it('mais urgente = mais toques', () => {
    expect([0, 1, 2, 3].map((u) => padraoSom(u as Urgencia).length)).toEqual([1, 2, 3, 6]);
    expect(Math.max(...padraoSom(3).map((n) => n.ini + n.dur))).toBeLessThan(1.6);
  });
});
