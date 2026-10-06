import { supabase } from './supabase';
import { EXPEDIENTE_PADRAO, REGRAS_PADRAO, type Expediente, type RegraAviso } from './alertas';

/** Notificações push do time (RPCs chamados.push_*; entrega pela Edge Function chamados-push). */
export interface ConfigPush { vapid_public_key: string | null; expediente: Expediente; regras: RegraAviso[]; aparelhos: number }

async function rpc<T>(nome: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(nome, args);
  if (error) throw error;
  return data as T;
}

export async function configPush(): Promise<ConfigPush> {
  const c = await rpc<Partial<ConfigPush>>('push_config');
  return { vapid_public_key: c.vapid_public_key ?? null, expediente: c.expediente ?? EXPEDIENTE_PADRAO, regras: c.regras ?? REGRAS_PADRAO, aparelhos: c.aparelhos ?? 0 };
}
export const testarPush = () => rpc<{ enfileirado: number }>('push_testar');

export function suportaPush(): boolean {
  return typeof window !== 'undefined' && 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
}

/** iPhone/iPad só recebe push com a Central instalada na tela de início (Safari → Compartilhar → Adicionar à Tela de Início). */
export function precisaInstalarNoIOS(): boolean {
  const ios = /iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const instalado = window.matchMedia?.('(display-mode: standalone)').matches || (navigator as unknown as { standalone?: boolean }).standalone === true;
  return ios && !instalado;
}

export async function registrarSW(): Promise<ServiceWorkerRegistration | null> {
  if (!('serviceWorker' in navigator)) return null;
  try { return await navigator.serviceWorker.register('/sw.js'); } catch { return null; }
}

export async function inscricaoAtual(): Promise<PushSubscription | null> {
  if (!suportaPush()) return null;
  const reg = await navigator.serviceWorker.getRegistration();
  return (await reg?.pushManager.getSubscription()) ?? null;
}

function chaveVapid(b64url: string): Uint8Array {
  const b64 = b64url.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (b64url.length % 4)) % 4);
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

/** Pede permissão, inscreve este navegador e grava a inscrição no banco. */
export async function ativarPush(vapid: string): Promise<void> {
  marcarRecusa(false);
  const perm = await Notification.requestPermission();
  if (perm !== 'granted') throw new Error('Permissão de notificações negada. Libere nas configurações do navegador para este site.');
  const reg = (await registrarSW()) ?? (await navigator.serviceWorker.ready);
  await navigator.serviceWorker.ready;
  let sub = await reg.pushManager.getSubscription();
  sub ??= await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: chaveVapid(vapid) as BufferSource });
  const j = sub.toJSON();
  await rpc('push_inscrever', { p_endpoint: sub.endpoint, p_p256dh: j.keys?.p256dh, p_auth: j.keys?.auth, p_user_agent: navigator.userAgent });
}

/** Quem desativou de propósito neste aparelho não é reinscrito sozinho. */
const RECUSA = 'rfg-push-desativado';
function recusou(): boolean { try { return localStorage.getItem(RECUSA) === '1'; } catch { return false; } }
function marcarRecusa(v: boolean) { try { if (v) localStorage.setItem(RECUSA, '1'); else localStorage.removeItem(RECUSA); } catch { /* sem armazenamento */ } }

/**
 * Sem pedir nada: com a permissão já dada, garante a inscrição deste navegador no banco (reinscreve se sumiu
 * ou foi desativada pelo servidor). Devolve se o push ficou ativo.
 */
export async function garantirPush(vapid: string | null): Promise<boolean> {
  if (!vapid || !suportaPush() || Notification.permission !== 'granted' || recusou()) return false;
  const reg = (await registrarSW()) ?? (await navigator.serviceWorker.ready);
  await navigator.serviceWorker.ready;
  let sub = await reg.pushManager.getSubscription();
  sub ??= await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: chaveVapid(vapid) as BufferSource });
  const j = sub.toJSON();
  await rpc('push_inscrever', { p_endpoint: sub.endpoint, p_p256dh: j.keys?.p256dh, p_auth: j.keys?.auth, p_user_agent: navigator.userAgent });
  return true;
}

export async function desativarPush(): Promise<void> {
  marcarRecusa(true);
  const sub = await inscricaoAtual();
  if (!sub) return;
  await rpc('push_cancelar', { p_endpoint: sub.endpoint }).catch(() => undefined);
  await sub.unsubscribe();
}
