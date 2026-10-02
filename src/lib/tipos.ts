export type Papel = 'solicitante' | 'dev';
export type Status = 'aberto' | 'andamento' | 'resolvido';
export type Urgencia = 0 | 1 | 2;

export interface Setor { id: number; nome: string; ordem: number }
export interface Pessoa { id: string; nome: string; setor_id: number | null; papel: Papel; ativo: boolean }
export interface Sistema { id: number; nome: string; ordem: number; ativo: boolean }

export interface Chamado {
  id: string;
  protocolo: string;
  descricao: string;
  solicitante_id: string;
  sistema_id: number;
  urgencia: Urgencia;
  status: Status;
  responsavel_id: string | null;
  prints: string[];
  criado_em: string;
  atualizado_em: string;
  resolvido_em: string | null;
}

export interface Catalogo {
  setores: Setor[];
  pessoas: Pessoa[];
  sistemas: Sistema[];
}

export const URGENCIAS = ['Pode esperar', 'Atrapalha', 'Estou parado'] as const;
export const COR_URGENCIA = ['ok', 'warn', 'bad'] as const;
