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

/** Espaços nas pontas e repetidos fora (mesma regra de chamados._limpar no banco). */
export function limparTexto(t: string): string {
  return t.trim().replace(/\s+/g, ' ');
}

/** Valor do select de setor para "Outro" (aí a pessoa digita qual). */
export const SETOR_OUTRO = 'outro';

/** O que falta para identificar quem abre sem login (tamanhos iguais aos do banco). */
export function faltaSolicitante(c: { setor: string; setorOutro: string; nome: string; cargo: string }, pedeSetor = true, pedeNome = true, pedeCargo = true): string[] {
  const f: string[] = [];
  const tam = (t: string, min: number, max: number) => { const n = limparTexto(t).length; return n >= min && n <= max; };
  if (pedeSetor && (!c.setor || (c.setor === SETOR_OUTRO && !tam(c.setorOutro, 2, 60)))) f.push('seu setor');
  if (pedeNome && !tam(c.nome, 3, 80)) f.push('seu nome');
  if (pedeCargo && !tam(c.cargo, 2, 60)) f.push('seu cargo');
  return f;
}

export const MAX_PRINTS = 3;
export const MAX_BYTES = 5 * 1024 * 1024;
const TIPOS = ['image/png', 'image/jpeg', 'image/webp', 'image/gif'];

/** Aplica as regras de anexo e devolve o que entra e a mensagem para o usuário. */
export function filtrarPrints(atuais: number, arquivos: { type: string; size: number }[]) {
  const aceitos: number[] = [];
  let msg = '';
  arquivos.forEach((f, i) => {
    if (!TIPOS.includes(f.type)) { msg = 'Só imagens (PNG, JPG, WEBP ou GIF).'; return; }
    if (f.size > MAX_BYTES) { msg = 'Imagem acima de 5 MB. Recorte o print ou salve em JPG.'; return; }
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
  if (/^(Só |Este chamado|Seu acesso|Print inválido|Escolha seu nome|Muitos chamados|Informe seu setor|O nome escolhido|Link inválido|Ative as notificações|Aguarde um minuto|Notificações são|Permissão de notificações|O servidor de notificações|Link da conversa|A conversa foi|Escreva uma mensagem|Muitas mensagens|Só o responsável e quem ajuda|Chamado resolvido não pode|Chamado não encontrado)/.test(m)) return m;
  if (/exceeded the maximum allowed size|Payload too large/i.test(m)) return 'Um dos prints passa de 5 MB. Recorte a imagem e tente de novo.';
  return padrao;
}
