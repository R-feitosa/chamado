import type { Chamado } from './tipos';

export type Filtro = 'abertos' | 'livres' | 'meus' | 'resolvidos';

export const FILTROS: { chave: Filtro; nome: string }[] = [
  { chave: 'abertos', nome: 'Em aberto' },
  { chave: 'livres', nome: 'Sem responsável' },
  { chave: 'meus', nome: 'Meus' },
  { chave: 'resolvidos', nome: 'Resolvidos' },
];

export function noFiltro(f: Filtro, c: Chamado, eu: string): boolean {
  const aberto = c.status !== 'resolvido';
  switch (f) {
    case 'abertos': return aberto;
    case 'livres': return aberto && !c.responsavel_id;
    case 'meus': return aberto && c.responsavel_id === eu;
    case 'resolvidos': return !aberto;
  }
}

/** Sem responsável primeiro; depois mais urgente; depois mais recente (regra do protótipo). */
export function ordenar(lista: Chamado[]): Chamado[] {
  return [...lista].sort((a, b) => {
    if (!a.responsavel_id !== !b.responsavel_id) return a.responsavel_id ? 1 : -1;
    if (b.urgencia !== a.urgencia) return b.urgencia - a.urgencia;
    return b.criado_em.localeCompare(a.criado_em);
  });
}

export function indicadores(chamados: Chamado[], eu: string) {
  const abertos = chamados.filter((c) => c.status !== 'resolvido');
  return {
    emAberto: abertos.length,
    semResponsavel: abertos.filter((c) => !c.responsavel_id).length,
    alguemParado: abertos.filter((c) => c.urgencia === 2).length,
    meus: abertos.filter((c) => c.responsavel_id === eu).length,
  };
}
