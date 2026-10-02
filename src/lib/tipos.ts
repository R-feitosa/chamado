export type Papel = 'solicitante' | 'dev';
export type Status = 'aberto' | 'andamento' | 'resolvido';
export type Urgencia = 0 | 1 | 2 | 3;

export interface Setor { id: number; nome: string; ordem: number }
export interface Pessoa { id: string; nome: string; setor_id: number | null; papel: Papel; ativo: boolean }
export interface Sistema { id: number; nome: string; ordem: number; ativo: boolean; grupo: Grupo; hub_codigo?: string | null }
export type Grupo = 'sistema' | 'suporte';
export interface NivelUrgencia { nivel: Urgencia; nome: string; descricao: string }
/** SLA em minutos corridos desde a abertura, por tipo de demanda e urgência (chamados.prazos). */
export interface Prazo { grupo: Grupo; nivel: Urgencia; assumir_min: number; resolver_min: number }
export const NOME_GRUPO: Record<Grupo, string> = { sistema: 'Desenvolvimento', suporte: 'Suporte técnico' };

export interface Chamado {
  id: string;
  protocolo: string;
  descricao: string;
  solicitante_id: string;
  sistema_id: number;
  urgencia: Urgencia;
  status: Status;
  responsavel_id: string | null;
  assumido_em: string | null;
  prazo_assumir_em: string;
  prazo_em: string;
  prints: string[];
  criado_em: string;
  atualizado_em: string;
  resolvido_em: string | null;
  sistema_origem?: string | null;
  contexto?: Record<string, string> | null;
}

export interface Catalogo {
  setores: Setor[];
  pessoas: Pessoa[];
  sistemas: Sistema[];
  urgencias: NivelUrgencia[];
  prazos: Prazo[];
}

/** Nomes para exibição; explicação vem de chamados.urgencias e prazos de chamados.prazos. */
export const URGENCIAS = ['Não urgente', 'Meio urgente', 'Urgente', 'Muito urgente'] as const;
export const URGENCIA_PADRAO: Urgencia = 1;
export const COR_URGENCIA = ['ok', 'info', 'warn', 'bad'] as const;
export const MUITO_URGENTE: Urgencia = 3;

export const NOME_PAPEL: Record<Papel, string> = { dev: 'Dev/Suporte', solicitante: 'Solicitante' };
