import { MUITO_URGENTE, type Chamado } from './tipos';
import { atrasado } from './sla';

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

/** Sem responsável primeiro (pelo prazo de assumir); depois pelo prazo de resolver. Resolvidos: mais recentes. */
export function ordenar(lista: Chamado[]): Chamado[] {
  return [...lista].sort((a, b) => {
    const ra = a.status === 'resolvido', rb = b.status === 'resolvido';
    if (ra !== rb) return ra ? 1 : -1;
    if (ra) return (b.resolvido_em ?? '').localeCompare(a.resolvido_em ?? '');
    if (!a.responsavel_id !== !b.responsavel_id) return a.responsavel_id ? 1 : -1;
    const p = (c: Chamado) => (c.responsavel_id ? c.prazo_em : c.prazo_assumir_em);
    return p(a).localeCompare(p(b));
  });
}

export function indicadores(chamados: Chamado[], eu: string, agora = Date.now()) {
  const abertos = chamados.filter((c) => c.status !== 'resolvido');
  return {
    emAberto: abertos.length,
    semResponsavel: abertos.filter((c) => !c.responsavel_id).length,
    muitoUrgente: abertos.filter((c) => c.urgencia === MUITO_URGENTE).length,
    meus: abertos.filter((c) => c.responsavel_id === eu).length,
    atrasados: abertos.filter((c) => atrasado(c, agora)).length,
  };
}
