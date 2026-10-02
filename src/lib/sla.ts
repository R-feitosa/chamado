/**
 * Prazos (SLA) de assumir e de resolver. O banco grava prazo_assumir_em e prazo_em na
 * abertura, conforme o tipo de demanda (desenvolvimento/suporte) e a urgência; aqui só se lê.
 */
import type { Chamado } from './tipos';
import { duracao } from './analytics';

export type Situacao = 'no_prazo' | 'perto' | 'atrasado' | 'cumprido' | 'estourado';
export type Etapa = 'assumir' | 'resolver';
const ms = (iso: string) => new Date(iso).getTime();

/** Pendente: no prazo, perto (últimos 25%) ou atrasado. Concluída: cumprido ou estourado. */
function avaliar(inicio: string, prazo: string, concluidoEm: string | null, agora: number) {
  const p = ms(prazo);
  if (concluidoEm) {
    const d = p - ms(concluidoEm);
    return { situacao: (d >= 0 ? 'cumprido' : 'estourado') as Situacao, diferenca: Math.abs(d) };
  }
  const restante = p - agora;
  if (restante < 0) return { situacao: 'atrasado' as Situacao, diferenca: -restante };
  return { situacao: (restante <= (p - ms(inicio)) * 0.25 ? 'perto' : 'no_prazo') as Situacao, diferenca: restante };
}

export const situacaoAssumir = (c: Chamado, agora: number) => avaliar(c.criado_em, c.prazo_assumir_em, c.assumido_em, agora);
export const situacaoResolver = (c: Chamado, agora: number) =>
  avaliar(c.criado_em, c.prazo_em, c.status === 'resolvido' ? c.resolvido_em : null, agora);

/** Etapa que está correndo agora: sem responsável = assumir; senão = resolver. */
export const etapaAtual = (c: Chamado): Etapa => (c.status !== 'resolvido' && !c.responsavel_id ? 'assumir' : 'resolver');

export function situacaoPrazo(c: Chamado, agora: number) {
  return etapaAtual(c) === 'assumir' ? situacaoAssumir(c, agora) : situacaoResolver(c, agora);
}

export function textoPrazo(c: Chamado, agora: number): string {
  const etapa = etapaAtual(c);
  const { situacao, diferenca } = situacaoPrazo(c, agora);
  if (etapa === 'assumir') return situacao === 'atrasado' ? `assumir atrasado ${duracao(diferenca)}` : `assumir em ${duracao(diferenca)}`;
  switch (situacao) {
    case 'no_prazo': case 'perto': return `resolver em ${duracao(diferenca)}`;
    case 'atrasado': return `atrasado ${duracao(diferenca)}`;
    case 'cumprido': return 'resolvido no prazo';
    case 'estourado': return `${duracao(diferenca)} além do prazo`;
  }
}

/** Aberto e com a etapa atual (assumir ou resolver) vencida. */
export const atrasado = (c: Chamado, agora: number) => c.status !== 'resolvido' && situacaoPrazo(c, agora).situacao === 'atrasado';

const pct = (total: number, ok: number) => (total ? Math.round((ok / total) * 100) : null);

/** % de resolvidos dentro do prazo de resolução. */
export function taxaNoPrazo(resolvidos: Chamado[]): number | null {
  const r = resolvidos.filter((c) => c.resolvido_em);
  return pct(r.length, r.filter((c) => ms(c.resolvido_em!) <= ms(c.prazo_em)).length);
}

/** % de assumidos dentro do prazo de assumir. */
export function taxaAssumidoNoPrazo(chamados: Chamado[]): number | null {
  const a = chamados.filter((c) => c.assumido_em);
  return pct(a.length, a.filter((c) => ms(c.assumido_em!) <= ms(c.prazo_assumir_em)).length);
}

export function minutosPorExtenso(min: number): string {
  if (min < 60) return `${min} min`;
  if (min % 1440 === 0) return `${min / 1440} ${min === 1440 ? 'dia' : 'dias'}`;
  return min % 60 ? `${Math.floor(min / 60)} h ${min % 60} min` : `${min / 60} h`;
}

export const formatoPct = (v: number | null) => (v === null ? '—' : `${v}%`);
