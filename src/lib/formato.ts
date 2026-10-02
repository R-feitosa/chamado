/** Funções puras de apresentação (testadas em formato.test.ts). */

export function iniciais(nome: string): string {
  const p = nome.trim().split(/\s+/).filter(Boolean);
  if (!p.length) return '—';
  return (p[0][0] + (p[1] ? p[1][0] : p[0][1] ?? '')).toUpperCase();
}

export function quando(iso: string, agora = Date.now()): string {
  const m = Math.round((agora - new Date(iso).getTime()) / 60000);
  if (m < 1) return 'agora';
  if (m < 60) return `há ${m} min`;
  const h = Math.round(m / 60);
  if (h < 24) return `há ${h} h`;
  return `há ${Math.round(h / 24)} d`;
}

const DIAS = ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'];
const MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

export function hojePorExtenso(d = new Date()): string {
  return `${DIAS[d.getDay()]}, ${d.getDate()} de ${MESES[d.getMonth()]}`;
}

/** Título do chamado na fila: primeiros 90 caracteres da descrição (mesma regra do protótipo). */
export function titulo(descricao: string): string {
  return descricao.trim().slice(0, 90);
}

export function faltando(c: { sistema: number | null; descricao: string; urgencia: number | null }): string[] {
  const f: string[] = [];
  if (c.sistema === null) f.push('o sistema');
  if (!c.descricao.trim()) f.push('a descrição');
  if (c.urgencia === null) f.push('a urgência');
  return f;
}

export const MAX_PRINTS = 3;
export const MAX_BYTES = 20 * 1024 * 1024;
const TIPOS = ['image/png', 'image/jpeg', 'image/webp', 'image/gif'];

/** Aplica as regras de anexo e devolve o que entra e a mensagem para o usuário. */
export function filtrarPrints(atuais: number, arquivos: { type: string; size: number }[]) {
  const aceitos: number[] = [];
  let msg = '';
  arquivos.forEach((f, i) => {
    if (!TIPOS.includes(f.type)) { msg = 'Só imagens (PNG, JPG, WEBP ou GIF).'; return; }
    if (f.size > MAX_BYTES) { msg = 'Imagem acima de 20 MB.'; return; }
    if (atuais + aceitos.length >= MAX_PRINTS) { msg = `Máximo de ${MAX_PRINTS} prints por chamado.`; return; }
    aceitos.push(i);
  });
  return { aceitos, msg };
}

/** Converte erros do Supabase/Postgres em frases para o usuário. */
export function mensagemErro(e: unknown, padrao = 'Não foi possível concluir. Tente de novo.'): string {
  const m = (e as { message?: string } | null)?.message ?? '';
  if (/Invalid login credentials/i.test(m)) return 'E-mail ou senha incorretos.';
  if (/rate limit/i.test(m)) return 'Muitas tentativas. Aguarde alguns minutos.';
  if (/Failed to fetch|NetworkError/i.test(m)) return 'Sem conexão com o servidor. Verifique a internet.';
  // Mensagens das RPCs já estão em português.
  if (/^(Só |Este chamado|Seu acesso|Print inválido)/.test(m)) return m;
  return padrao;
}
