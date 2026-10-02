/** Token do botão "Abrir chamado" dos sistemas do hub (funções puras, testadas em convite.test.ts). */

/** Lê o token (?t=…, 64 caracteres hex) da query string; qualquer outra coisa é ignorada. */
export function tokenDaUrl(search: string): string | null {
  const t = new URLSearchParams(search).get('t')?.trim().toLowerCase() ?? '';
  return /^[0-9a-f]{64}$/.test(t) ? t : null;
}

/** Mesma URL sem o parâmetro t (o token não fica no histórico nem é compartilhado ao copiar o link). */
export function urlSemToken(href: string): string {
  const u = new URL(href);
  u.searchParams.delete('t');
  return u.pathname + (u.searchParams.toString() ? `?${u.searchParams}` : '') + u.hash;
}
