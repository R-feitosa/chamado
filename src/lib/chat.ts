import { supabase } from './supabase';

/** Chat descartável do chamado (RPCs chamados.chat_*). Quem abriu entra com protocolo + código secreto. */
export interface MensagemChat { id: number; autor: 'solicitante' | 'time'; texto: string | null; criada_em: string; apagada: boolean; nome: string | null }
export type EstadoChat = 'aberto' | 'fechado' | 'apagado';
export interface ConversaPublica { protocolo: string; estado: EstadoChat; apaga_em: string | null; responsavel: string | null; mensagens: MensagemChat[] }
export interface ResumoChat { total: number; nao_lidas: number; ultima_em: string }

async function rpc<T>(nome: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(nome, args);
  if (error) throw error;
  return data as T;
}

export const lerConversa = (protocolo: string, codigo: string, depois = 0) =>
  rpc<ConversaPublica>('chat_ler', { p_protocolo: protocolo, p_codigo: codigo, p_depois: depois });
export const enviarComoSolicitante = (protocolo: string, codigo: string, texto: string) =>
  rpc<{ id: number }>('chat_enviar', { p_protocolo: protocolo, p_codigo: codigo, p_texto: texto });
export const enviarComoTime = (chamado: string, texto: string) => rpc<{ id: number }>('chat_enviar_time', { p_chamado: chamado, p_texto: texto });
export const marcarConversaLida = (chamado: string) => rpc<void>('chat_marcar_lido', { p_chamado: chamado });
export const resumoConversas = () => rpc<Record<string, ResumoChat>>('chat_resumo');

/** Time: mensagens do chamado (RLS) com o primeiro nome de quem escreveu. */
export async function mensagensDoChamado(chamado: string): Promise<MensagemChat[]> {
  const { data, error } = await supabase.from('chat_mensagens')
    .select('id, autor, texto, criada_em, apagada_em, pessoa:pessoas(nome)').eq('chamado_id', chamado).order('id');
  if (error) throw error;
  return (data ?? []).map((m) => {
    const r = m as unknown as { id: number; autor: MensagemChat['autor']; texto: string | null; criada_em: string; apagada_em: string | null; pessoa: { nome: string } | null };
    return { id: r.id, autor: r.autor, texto: r.texto, criada_em: r.criada_em, apagada: !!r.apagada_em, nome: r.pessoa ? r.pessoa.nome.split(' ')[0] : null };
  });
}

/** Junta mensagens novas às atuais, sem repetir e em ordem. */
export function juntar(atual: MensagemChat[], novas: MensagemChat[]): MensagemChat[] {
  const vistos = new Set(atual.map((m) => m.id));
  return [...atual, ...novas.filter((m) => !vistos.has(m.id))].sort((a, b) => a.id - b.id);
}

/** Separadores por dia ("Hoje", "Ontem", "03/10"). */
export function rotuloDia(iso: string, agora = Date.now()): string {
  const d = new Date(iso), h = new Date(agora);
  const dia = (x: Date) => `${x.getFullYear()}-${x.getMonth()}-${x.getDate()}`;
  if (dia(d) === dia(h)) return 'Hoje';
  const ontem = new Date(agora - 86_400_000);
  if (dia(d) === dia(ontem)) return 'Ontem';
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
}

export function agruparPorDia(ms: MensagemChat[], agora = Date.now()): { dia: string; mensagens: MensagemChat[] }[] {
  const out: { dia: string; mensagens: MensagemChat[] }[] = [];
  for (const m of ms) {
    const dia = rotuloDia(m.criada_em, agora);
    if (out[out.length - 1]?.dia !== dia) out.push({ dia, mensagens: [] });
    out[out.length - 1].mensagens.push(m);
  }
  return out;
}

/** Último id visto pelo solicitante neste navegador (para o aviso de mensagem nova). */
const CHAVE = 'rfg-chamados-chat-visto';
export function ultimoVisto(protocolo: string): number {
  try { return Number((JSON.parse(localStorage.getItem(CHAVE) ?? '{}') as Record<string, number>)[protocolo] ?? 0); } catch { return 0; }
}
export function marcarVisto(protocolo: string, id: number) {
  try {
    const a = JSON.parse(localStorage.getItem(CHAVE) ?? '{}') as Record<string, number>;
    a[protocolo] = Math.max(a[protocolo] ?? 0, id);
    localStorage.setItem(CHAVE, JSON.stringify(a));
  } catch { /* sem armazenamento */ }
}
