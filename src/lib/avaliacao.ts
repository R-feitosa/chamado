/** Código secreto de avaliação: fica só no navegador de quem abriu (e no link "avaliar depois"). */
const CHAVE = 'rfg-chamados-avaliacao';

function ler(): Record<string, string> {
  try { return JSON.parse(localStorage.getItem(CHAVE) ?? '{}') as Record<string, string>; } catch { return {}; }
}

export function guardarCodigo(protocolo: string, codigo: string) {
  try {
    const atual = ler();
    atual[protocolo.toUpperCase()] = codigo;
    // Guarda só os 30 mais recentes.
    const chaves = Object.keys(atual);
    for (const k of chaves.slice(0, Math.max(0, chaves.length - 30))) delete atual[k];
    localStorage.setItem(CHAVE, JSON.stringify(atual));
  } catch { /* sem armazenamento: ainda dá para usar o link */ }
}

export function codigoDe(protocolo: string): string | null {
  return ler()[protocolo.toUpperCase()] ?? null;
}

/** Link para avaliar depois (outro aparelho ou depois de limpar o navegador). */
export function linkAvaliacao(origem: string, protocolo: string, codigo: string): string {
  return `${origem.replace(/\/$/, '')}/?avaliar=${encodeURIComponent(`${protocolo}.${codigo}`)}`;
}

/** Lê ?avaliar=TI-0425.<código> da URL. */
export function avaliacaoDaUrl(busca: string): { protocolo: string; codigo: string } | null {
  const v = new URLSearchParams(busca).get('avaliar');
  const m = v?.match(/^(TI-\d{4,})\.([0-9a-f]{24})$/i);
  return m ? { protocolo: m[1].toUpperCase(), codigo: m[2].toLowerCase() } : null;
}

export function urlSemAvaliacao(href: string): string {
  const u = new URL(href);
  u.searchParams.delete('avaliar');
  return u.pathname + (u.search === '?' ? '' : u.search) + u.hash;
}
