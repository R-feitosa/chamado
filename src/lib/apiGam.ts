import { supabase } from './supabase';
import type { Criterio, Jornada, Periodo, Ranking } from './gamificacao';

/** Chamadas da gamificação (RPCs chamados.gam_*). Escrita do time: só ler/marcar lidas/escolher visual. */
async function rpc<T>(nome: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(nome, args);
  if (error) throw error;
  return data as T;
}

export const jornada = (pessoa?: string) => rpc<Jornada>('gam_jornada', pessoa ? { p_pessoa: pessoa } : {});
export const ranking = (periodo: Periodo, criterio: Criterio, temporada?: number | null) =>
  rpc<Ranking>('gam_ranking', { p_periodo: periodo, p_criterio: criterio, p_temporada: temporada ?? null });
export const marcarLidas = (ate?: number) => rpc<{ lidas: number }>('gam_marcar_lidas', { p_ate: ate ?? null });
export const escolherVisual = (titulo: number | null, moldura: number | null) => rpc<{ ok: boolean }>('gam_escolher_visual', { p_titulo: titulo, p_moldura: moldura });
export async function listarTemporadas(): Promise<{ id: number; nome: string; inicio: string; fim: string; status: string }[]> {
  const { data, error } = await supabase.from('gam_temporadas').select('id,nome,inicio,fim,status').order('inicio', { ascending: false });
  if (error) throw error;
  return data ?? [];
}
export const processarAgora = () => rpc<{ processados: number; confirmados: number }>('gam_processar_agora');

// Central de Gamificação (só gestor)
export type Painel = Record<string, unknown> & {
  config: Record<string, { valor: unknown; descricao: string; atualizado_em: string }>;
  regras: Regra[]; multiplicadores: { urgencia: number; rotulo: string; fator: number }[];
  niveis: { nivel: number; nome: string; xp_minimo: number }[];
  conquistas: (Record<string, unknown> & { codigo: string; nome: string; descricao: string; icone: string; raridade: string; metrica: string | null; ativo: boolean; ordem: number;
    tiers: { tier: number; nome: string | null; limite: number; xp: number; raridade: string | null; recompensa: string | null; desbloqueios: number }[] })[];
  missoes: (Record<string, unknown> & { codigo: string; nome: string; descricao: string; periodo: string; alvo: string; metrica: string; meta: number; xp: number;
    especial: boolean; inicio: string; fim: string | null; ativo: boolean; recompensa: string | null; conquista: string | null })[];
  recompensas: { id: number; codigo: string; tipo: string; nome: string; descricao: string; raridade: string; ativo: boolean }[];
  temporadas: { id: number; nome: string; inicio: string; fim: string; status: string; encerrada_em: string | null }[];
  suspeitas: { id: number; pessoa: string; protocolo: string | null; regra: string; descricao: string; status: string; criada_em: string; nota: string | null; xp_retido: number }[];
  fila: { pendentes: number; erros: number; processados: number; ignorados: number; ultimo: string | null; ultimos_erros: { id: number; tipo: string; erro: string }[] | null };
  xp_pendente: number;
  auditoria: { acao: string; alvo: string; autor: string | null; antes: unknown; depois: unknown; criado_em: string }[];
};
export interface Regra { codigo: string; nome: string; descricao: string; evento: string; xp: number; ativo: boolean; limite_por_chamado: number; limite_diario: number | null; usa_multiplicador: boolean }

export const adminPainel = () => rpc<Painel>('gam_admin_painel');
export const adminConfig = (chave: string, valor: unknown) => rpc('gam_admin_config', { p_chave: chave, p_valor: valor });
export const adminRegra = (r: Pick<Regra, 'codigo' | 'xp' | 'ativo' | 'limite_por_chamado' | 'limite_diario'>) =>
  rpc('gam_admin_regra', { p_codigo: r.codigo, p_xp: r.xp, p_ativo: r.ativo, p_limite_chamado: r.limite_por_chamado, p_limite_diario: r.limite_diario });
export const adminMultiplicador = (urgencia: number, fator: number) => rpc('gam_admin_multiplicador', { p_urgencia: urgencia, p_fator: fator });
export const adminNiveis = (niveis: { nivel: number; nome: string; xp_minimo: number }[]) => rpc('gam_admin_niveis', { p_niveis: niveis });
export const adminConquista = (c: Record<string, unknown>) => rpc('gam_admin_conquista', { p: c });
export const adminMissao = (m: Record<string, unknown>) => rpc('gam_admin_missao', { p: m });
export const adminRecompensa = (r: Record<string, unknown>) => rpc('gam_admin_recompensa', { p: r });
export const adminTemporada = (t: Record<string, unknown>) => rpc('gam_admin_temporada', { p: t });
export const adminSuspeita = (id: number, aceitar: boolean, nota: string) => rpc('gam_admin_suspeita', { p_id: id, p_aceitar: aceitar, p_nota: nota || null });
export const adminReprocessar = () => rpc<Record<string, number>>('gam_admin_reprocessar');
