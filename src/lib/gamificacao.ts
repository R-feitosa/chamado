/**
 * Gamificação: tipos e regras puras de apresentação (testadas em gamificacao.test.ts).
 * As regras de negócio (XP, conquistas, missões, score) vivem no banco (supabase/migrations/2026100515-17*);
 * aqui só se formata o que o banco devolve. `nivelDe` espelha chamados.gam_nivel para o feedback imediato.
 */

export type Raridade = 'comum' | 'incomum' | 'rara' | 'epica' | 'lendaria';
export type XpStatus = 'pendente' | 'retido' | 'confirmado' | 'estornado';
export type Periodo = 'dia' | 'semana' | 'mes' | 'trimestre' | 'ano' | 'geral' | 'temporada';
export type Criterio = 'score' | 'xp' | 'resolvidos' | 'satisfacao' | 'sla' | 'qualidade' | 'eficiencia';

export interface Nivel { nivel: number; nome: string; xp: number; xp_nivel: number; xp_proximo: number; faltam: number; progresso: number }
export interface NivelCadastro { nivel: number; nome: string; xp_minimo: number }

export interface Tier { tier: number; nome: string | null; limite: number; xp: number; raridade: Raridade; desbloqueada_em: string | null }
export interface Conquista { codigo: string; nome: string; descricao: string; icone: string; raridade: Raridade; metrica: string | null; valor: number; tiers: Tier[] }
export interface Missao {
  codigo: string; nome: string; descricao: string; periodo: 'dia' | 'semana' | 'mes'; alvo: 'individual' | 'equipe'; especial: boolean;
  meta: number; xp: number; metrica: string; termina_em: string; valor: number; concluidas: number;
  ultima: { periodo: string; valor: number; concluida: boolean } | null;
}
export interface Notificacao { id: number; tipo: string; titulo: string; detalhe: string | null; xp: number | null; dados: Record<string, unknown>; criada_em: string; lida: boolean }
export interface LinhaXp { id: number; valor: number; motivo: string; status: XpStatus; protocolo: string | null; criado_em: string }
export interface Recompensa { id: number; codigo: string; tipo: 'titulo' | 'moldura' | 'tema' | 'icone' | 'destaque'; nome: string; descricao: string; raridade: Raridade; obtida_em: string }
export interface Sequencia { tipo: 'sem_reabertura' | 'sla' | 'cinco_estrelas' | 'semanas_sla'; atual: number; recorde: number }

export interface Jornada {
  ativo: boolean; participa?: boolean; gestor?: boolean; privado?: boolean;
  pessoa?: { id: string; nome: string; cargo: string };
  /** xp = confirmado + em validação (conta na hora); xp_pendente = parte ainda em validação (pode ser estornada). */
  perfil?: { xp: number; xp_pendente: number; xp_confirmado?: number; nivel: Nivel; titulo: { id: number; nome: string; raridade: Raridade } | null;
             moldura: { id: number; codigo: string; nome: string; raridade: Raridade } | null };
  temporada?: { id: number; nome: string; inicio: string; fim: string } | null;
  ranking?: { posicao: number | null; classificado: boolean | null; total: number; score: number | null; minimo: number };
  estatisticas?: { resolvidos: number; sla: number | null; satisfacao: number | null; reabertura: number | null; ajudas: number; xp: number;
                   score: number; tempo_medio_h: number | null;
                   componentes: { qualidade: number; sla: number; satisfacao: number; produtividade: number; colaboracao: number } } | null;
  sequencias?: Sequencia[]; conquistas?: Conquista[]; missoes?: Missao[]; recompensas?: Recompensa[];
  temporadas?: { nome: string; posicao: number; score: number | null }[];
  feed?: Notificacao[] | null; historico?: LinhaXp[] | null; nao_lidas?: number | null;
}

export interface LinhaRanking {
  posicao: number; pessoa_id: string; nome: string; eu: boolean; nivel?: number; titulo?: string | null; moldura?: string | null;
  valor?: number | null; classificado: boolean; score: number | null; xp: number; resolvidos: number; sla: number | null;
  satisfacao: number | null; reabertura?: number | null; eficiencia?: number | null; ajudas?: number;
}
export interface Ranking { congelado: boolean; temporada?: string; periodo?: Periodo; criterio: Criterio; minimo?: number; linhas: LinhaRanking[] }

export const RARIDADES: Record<Raridade, string> = { comum: 'Comum', incomum: 'Incomum', rara: 'Rara', epica: 'Épica', lendaria: 'Lendária' };
export const PERIODOS: { chave: Periodo; nome: string }[] = [
  { chave: 'dia', nome: 'Hoje' }, { chave: 'semana', nome: 'Semana' }, { chave: 'mes', nome: 'Mês' },
  { chave: 'trimestre', nome: 'Trimestre' }, { chave: 'ano', nome: 'Ano' }, { chave: 'temporada', nome: 'Temporada' }, { chave: 'geral', nome: 'Geral' },
];
export const CRITERIOS: { chave: Criterio; nome: string; ajuda: string }[] = [
  { chave: 'score', nome: 'Performance', ajuda: 'Score composto: qualidade, SLA, satisfação, produtividade e colaboração.' },
  { chave: 'xp', nome: 'XP', ajuda: 'XP ganho no período (inclui o que está em validação).' },
  { chave: 'resolvidos', nome: 'Resolvidos', ajuda: 'Chamados resolvidos no período.' },
  { chave: 'satisfacao', nome: 'Satisfação', ajuda: 'Avaliações de quem abriu (suavizadas pela média do time).' },
  { chave: 'sla', nome: 'SLA', ajuda: 'Assumidos e resolvidos no prazo (suavizado).' },
  { chave: 'qualidade', nome: 'Qualidade', ajuda: 'Chamados sem reabertura (suavizado).' },
  { chave: 'eficiencia', nome: 'Eficiência', ajuda: 'Quanto do prazo sobrou na resolução, em média.' },
];
export const SEQUENCIAS: Record<Sequencia['tipo'], { nome: string; unidade: string }> = {
  sla: { nome: 'Dentro do SLA', unidade: 'chamados seguidos' },
  sem_reabertura: { nome: 'Sem reabertura', unidade: 'chamados seguidos' },
  cinco_estrelas: { nome: '5 estrelas', unidade: 'avaliações seguidas' },
  semanas_sla: { nome: 'Semanas ≥ 95% SLA', unidade: 'semanas seguidas' },
};
export const STATUS_XP: Record<XpStatus, string> = { pendente: 'Em validação', retido: 'Em revisão', confirmado: 'Confirmado', estornado: 'Estornado' };
export const PERIODO_MISSAO: Record<Missao['periodo'], string> = { dia: 'Diária', semana: 'Semanal', mes: 'Mensal' };

/** Nível e progresso a partir do XP (mesma regra de chamados.gam_nivel). */
export function nivelDe(xp: number, niveis: NivelCadastro[], fatorExtra = 1.25): Nivel {
  const v = Math.max(0, Math.floor(xp || 0));
  const lista = [...niveis].sort((a, b) => a.xp_minimo - b.xp_minimo);
  if (!lista.length) return { nivel: 1, nome: '', xp: v, xp_nivel: 0, xp_proximo: 0, faltam: 0, progresso: 1 };
  let i = 0;
  while (i + 1 < lista.length && lista[i + 1].xp_minimo <= v) i++;
  const atual = lista[i];
  let nivel = atual.nivel, min = atual.xp_minimo, nome = atual.nome, prox: number;
  if (i + 1 < lista.length) {
    prox = lista[i + 1].xp_minimo;
  } else {
    let gap = Math.max(atual.xp_minimo - (lista[i - 1]?.xp_minimo ?? 0), 1000);
    for (;;) {
      gap = Math.round(gap * fatorExtra);
      prox = min + gap;
      if (v < prox) break;
      nivel++; min = prox;
    }
    if (nivel > atual.nivel) nome = `${atual.nome} ${nivel - atual.nivel + 1}`;
  }
  return { nivel, nome, xp: v, xp_nivel: min, xp_proximo: prox, faltam: prox - v, progresso: Math.round(((v - min) / Math.max(prox - min, 1)) * 10000) / 10000 };
}

export function fmtXp(n: number): string {
  return Math.round(n).toLocaleString('pt-BR');
}

export function sinalXp(n: number): string {
  return `${n > 0 ? '+' : n < 0 ? '−' : ''}${fmtXp(Math.abs(n))} XP`;
}

export function pct(v: number | null | undefined, casas = 0): string {
  if (v === null || v === undefined || Number.isNaN(v)) return '—';
  return `${(v * 100).toLocaleString('pt-BR', { maximumFractionDigits: casas, minimumFractionDigits: casas })}%`;
}

/** Próximo tier ainda bloqueado e o progresso até ele (null = tudo desbloqueado). */
export function proximoTier(c: Conquista): { tier: Tier; faltam: number; progresso: number } | null {
  const t = c.tiers.find((x) => !x.desbloqueada_em);
  if (!t) return null;
  return { tier: t, faltam: Math.max(0, t.limite - c.valor), progresso: Math.min(1, c.valor / t.limite) };
}

/** Raridade exibida: a do maior tier desbloqueado (ou do próximo, se nenhum). */
export function raridadeAtual(c: Conquista): Raridade {
  const feitos = c.tiers.filter((t) => t.desbloqueada_em);
  return (feitos[feitos.length - 1] ?? c.tiers[0])?.raridade ?? c.raridade;
}

/** Conquistas mais perto de desbloquear (com algum progresso), para "Conquistas próximas". */
export function conquistasProximas(lista: Conquista[], n = 3): { conquista: Conquista; tier: Tier; faltam: number; progresso: number }[] {
  return lista
    .filter((c) => c.metrica)
    .map((c) => ({ conquista: c, p: proximoTier(c) }))
    .filter((x): x is { conquista: Conquista; p: NonNullable<ReturnType<typeof proximoTier>> } => !!x.p)
    .sort((a, b) => b.p.progresso - a.p.progresso || a.p.faltam - b.p.faltam)
    .slice(0, n)
    .map((x) => ({ conquista: x.conquista, ...x.p }));
}

export function desbloqueadas(lista: Conquista[]): { conquista: Conquista; tier: Tier }[] {
  return lista
    .flatMap((c) => c.tiers.filter((t) => t.desbloqueada_em).map((t) => ({ conquista: c, tier: t })))
    .sort((a, b) => (b.tier.desbloqueada_em ?? '').localeCompare(a.tier.desbloqueada_em ?? ''));
}

/** Quanto falta (texto) para o período da missão terminar. */
export function terminaEm(iso: string, agora = Date.now()): string {
  const m = Math.max(0, Math.round((new Date(iso).getTime() - agora) / 60000));
  if (m < 60) return `${m} min`;
  const h = Math.round(m / 60);
  if (h < 48) return `${h} h`;
  return `${Math.round(h / 24)} dias`;
}

/** Valor da missão formatado (porcentagem para métricas de equipe em %). */
export function valorMissao(m: Pick<Missao, 'metrica' | 'valor' | 'meta'>): string {
  const emPct = m.metrica.endsWith('_pct');
  const f = (v: number) => (emPct ? `${v.toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%` : v.toLocaleString('pt-BR'));
  return `${f(m.valor)} / ${f(m.meta)}`;
}

/** Notificações novas desde a última vista (para toasts), na ordem em que aconteceram. */
export function novasDesde(feed: Notificacao[], ultimaVista: number): Notificacao[] {
  return feed.filter((n) => n.id > ultimaVista && !n.lida).sort((a, b) => a.id - b.id);
}
