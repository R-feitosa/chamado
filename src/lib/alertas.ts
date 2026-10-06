import type { Chamado, Urgencia } from './tipos';

/** Espelho de chamados.push_regras (frequência dos avisos enquanto o chamado está sem responsável). */
export interface RegraAviso { nivel: Urgencia; repetir_min: number | null; so_expediente: boolean; vibrar: number[]; exigir_interacao: boolean }
export interface Expediente { dias: number[]; inicio: string; fim: string }

/** Mesmo seed da migration 20261006120000 (usado enquanto push_config não chega). */
export const REGRAS_PADRAO: RegraAviso[] = [
  { nivel: 3, repetir_min: 5, so_expediente: false, vibrar: [400, 150, 400, 150, 400, 150, 400], exigir_interacao: true },
  { nivel: 2, repetir_min: 15, so_expediente: false, vibrar: [250, 100, 250, 100, 250], exigir_interacao: true },
  { nivel: 1, repetir_min: 60, so_expediente: true, vibrar: [150, 80, 150], exigir_interacao: false },
  { nivel: 0, repetir_min: 240, so_expediente: true, vibrar: [120], exigir_interacao: false },
];
export const EXPEDIENTE_PADRAO: Expediente = { dias: [1, 2, 3, 4, 5], inicio: '08:00', fim: '18:00' };

const MIN = 60_000;

/** Hora de Fortaleza (mesmo fuso do banco) como dia ISO (1 = segunda … 7 = domingo) e minutos do dia. */
function horaLocal(agora: number): { dia: number; min: number } {
  const p = new Intl.DateTimeFormat('en-GB', { timeZone: 'America/Fortaleza', weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
    .formatToParts(new Date(agora));
  const v = (t: string) => p.find((x) => x.type === t)?.value ?? '';
  const dia = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].indexOf(v('weekday')) + 1;
  return { dia, min: Number(v('hour')) * 60 + Number(v('minute')) };
}
const minutos = (hhmm: string) => { const [h, m] = hhmm.split(':').map(Number); return h * 60 + (m || 0); };

/** Espelho de chamados.push_no_expediente. */
export function noExpediente(agora: number, e: Expediente = EXPEDIENTE_PADRAO): boolean {
  const { dia, min } = horaLocal(agora);
  return e.dias.includes(dia) && min >= minutos(e.inicio) && min < minutos(e.fim);
}

/** Quantos intervalos de lembrete já passaram desde a abertura (0 = só o aviso de "novo"). */
export function seqLembrete(c: Pick<Chamado, 'criado_em'>, regra: RegraAviso | undefined, agora: number): number {
  if (!regra?.repetir_min) return 0;
  return Math.max(0, Math.floor((agora - new Date(c.criado_em).getTime()) / MIN / regra.repetir_min));
}

export interface Aviso { chamado: Chamado; tipo: 'novo' | 'lembrete'; seq: number }

/**
 * Avisos devidos agora para a aba aberta (mesma regra do agendador do banco):
 * chamado novo (ainda não visto) sem responsável → "novo"; sem responsável e com um intervalo a mais
 * desde o último aviso → "lembrete" (fora do expediente, só as urgências 24 h).
 * `vistos` guarda o último seq avisado por chamado e é atualizado aqui.
 */
export function avisosDevidos(
  chamados: Chamado[], regras: RegraAviso[], exp: Expediente, agora: number, vistos: Map<string, number>, euId?: string,
): Aviso[] {
  const out: Aviso[] = [];
  const dentro = noExpediente(agora, exp);
  for (const c of chamados) {
    if (c.status === 'resolvido' || c.responsavel_id || c.solicitante_id === euId) { vistos.delete(c.id); continue; }
    const regra = regras.find((r) => r.nivel === c.urgencia);
    const seq = seqLembrete(c, regra, agora);
    const anterior = vistos.get(c.id);
    if (anterior === undefined) {
      vistos.set(c.id, seq);
      out.push({ chamado: c, tipo: 'novo', seq });
    } else if (seq > anterior && (dentro || !regra?.so_expediente)) {
      vistos.set(c.id, seq);
      out.push({ chamado: c, tipo: 'lembrete', seq });
    }
  }
  return out;
}

/** Marca como já vistos (sem avisar) os chamados que existiam quando a tela abriu. */
export function marcarVistos(chamados: Chamado[], regras: RegraAviso[], agora: number, vistos: Map<string, number>) {
  for (const c of chamados) {
    if (c.status === 'resolvido' || c.responsavel_id) continue;
    vistos.set(c.id, seqLembrete(c, regras.find((r) => r.nivel === c.urgencia), agora));
  }
}

export function frequenciaPorExtenso(r: RegraAviso): string {
  if (!r.repetir_min) return 'só o primeiro aviso';
  const t = r.repetir_min < 60 ? `${r.repetir_min} min` : `${r.repetir_min / 60} h`;
  return `a cada ${t}${r.so_expediente ? ', no expediente' : ', 24 h'}`;
}
