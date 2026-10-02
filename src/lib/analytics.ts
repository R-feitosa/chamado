/** Cálculos de tempo e produtividade (funções puras, testadas em analytics.test.ts). */
import type { Chamado } from './tipos';

const MIN = 60_000, HORA = 60 * MIN, DIA = 24 * HORA;
const ms = (iso: string) => new Date(iso).getTime();

/** "agora", "12 min", "3 h 20 min", "2 d 4 h". */
export function duracao(t: number | null): string {
  if (t === null || !Number.isFinite(t)) return '—';
  if (t < MIN) return 'agora';
  // Arredonda uma vez na unidade exibida, para nunca mostrar "60 min" ou "2 h 60 min".
  const min = Math.round(t / MIN);
  if (min < 60) return `${min} min`;
  if (t < DIA) {
    const h = Math.floor(min / 60), m = min % 60;
    if (h >= 10 || !m) return `${Math.round(t / HORA)} h`;
    return `${h} h ${m} min`;
  }
  const horas = Math.round(t / HORA), d = Math.floor(horas / 24), h = horas % 24;
  return h ? `${d} d ${h} h` : `${d} d`;
}

function media(v: number[]): number | null {
  return v.length ? v.reduce((a, b) => a + b, 0) / v.length : null;
}

export const PERIODOS = [
  { chave: '7', nome: '7 dias', dias: 7 },
  { chave: '30', nome: '30 dias', dias: 30 },
  { chave: '90', nome: '90 dias', dias: 90 },
  { chave: 'tudo', nome: 'Tudo', dias: null },
] as const;
export type ChavePeriodo = (typeof PERIODOS)[number]['chave'];

export function inicioDoPeriodo(chave: ChavePeriodo, agora: number): number {
  const d = PERIODOS.find((p) => p.chave === chave)?.dias;
  return d == null ? -Infinity : agora - d * DIA;
}

/** Tempo até assumir: chamados assumidos no período. Tempo de resolução: abertura → resolução, resolvidos no período. */
export function temposMedios(chamados: Chamado[], desde: number) {
  const assumir = chamados
    .filter((c) => c.assumido_em && ms(c.assumido_em) >= desde)
    .map((c) => ms(c.assumido_em!) - ms(c.criado_em));
  const resolver = chamados
    .filter((c) => c.status === 'resolvido' && c.resolvido_em && ms(c.resolvido_em) >= desde)
    .map((c) => ms(c.resolvido_em!) - ms(c.criado_em));
  return { mediaAssumir: media(assumir), mediaResolver: media(resolver) };
}

/** Indicadores de tempo da fila atual. */
export function tempoDaFila(chamados: Chamado[], agora: number) {
  const abertos = chamados.filter((c) => c.status !== 'resolvido');
  const idades = abertos.map((c) => agora - ms(c.criado_em));
  const semResp = abertos.filter((c) => !c.responsavel_id).map((c) => agora - ms(c.criado_em));
  return { esperaMediaSemResponsavel: media(semResp), maisAntigo: idades.length ? Math.max(...idades) : null };
}

export function resolvidosNoPeriodo(chamados: Chamado[], desde: number): Chamado[] {
  return chamados.filter((c) => c.status === 'resolvido' && c.resolvido_em && ms(c.resolvido_em) >= desde && c.responsavel_id);
}

export interface LinhaTecnico { id: string; resolvidos: number; emAndamento: number; mediaResolver: number | null }

/** Uma linha por técnico (inclusive quem não resolveu nada), ordenada por resolvidos. */
export function porTecnico(chamados: Chamado[], tecnicos: string[], desde: number): LinhaTecnico[] {
  const res = resolvidosNoPeriodo(chamados, desde);
  return tecnicos
    .map((id) => {
      const meus = res.filter((c) => c.responsavel_id === id);
      return {
        id,
        resolvidos: meus.length,
        emAndamento: chamados.filter((c) => c.status === 'andamento' && c.responsavel_id === id).length,
        mediaResolver: media(meus.map((c) => ms(c.resolvido_em!) - ms(c.criado_em))),
      };
    })
    .sort((a, b) => b.resolvidos - a.resolvidos || b.emAndamento - a.emAndamento);
}

/** Contagem técnico × área (sistema ou setor), só com resolvidos no período. */
export function matriz(resolvidos: Chamado[], area: (c: Chamado) => string | number | null) {
  const m = new Map<string, Map<string, number>>();
  for (const c of resolvidos) {
    const a = String(area(c) ?? '—');
    const linha = m.get(c.responsavel_id!) ?? new Map<string, number>();
    linha.set(a, (linha.get(a) ?? 0) + 1);
    m.set(c.responsavel_id!, linha);
  }
  return m;
}
