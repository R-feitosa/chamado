import { useCallback, useEffect, useRef, useState } from 'react';
import { avisosDevidos, EXPEDIENTE_PADRAO, marcarVistos, REGRAS_PADRAO, type Aviso } from '../lib/alertas';
import { ativarPush, configPush, desativarPush, inscricaoAtual, registrarSW, suportaPush, testarPush, type ConfigPush } from '../lib/push';
import { definirSom, prepararAudio, somLigado, tocarSom } from '../lib/som';
import { mensagemErro } from '../lib/formato';
import { URGENCIAS, type Catalogo, type Chamado } from '../lib/tipos';

export interface AlertaTela { id: number; titulo: string; corpo: string; urgencia: Chamado['urgencia'] }
const ICONE = ['🟢', '🔵', '🟠', '🔴'];

/**
 * Avisos do time na própria aba (som + cartão) e controle do push deste aparelho.
 * Com a aba aberta: avisa chamado novo na hora e repete pela regra da urgência enquanto ninguém assume
 * (mesma regra do agendador do banco). A notificação do sistema vem do push (Edge Function); se o push
 * não estiver ativo mas a permissão estiver dada, a própria aba mostra a notificação quando estiver em segundo plano.
 * `avisar = false` (gestor): só controla o push deste aparelho.
 */
export function useAlertas({ chamados, catalogo, euId, avisar }: { chamados: Chamado[]; catalogo: Catalogo; euId: string; avisar: boolean }) {
  const [config, setConfig] = useState<ConfigPush | null>(null);
  const [pushAtivo, setPushAtivo] = useState(false);
  const [som, setSomEstado] = useState(somLigado);
  const [alertas, setAlertas] = useState<AlertaTela[]>([]);
  const [ocupado, setOcupado] = useState(false);
  const [aviso, setAviso] = useState('');
  const vistos = useRef(new Map<string, number>());
  const iniciou = useRef(false);
  const seq = useRef(0);

  const carregar = useCallback(async () => {
    try { setConfig(await configPush()); } catch { /* sem config: usa o padrão */ }
    if (suportaPush() && Notification.permission === 'granted') setPushAtivo(!!(await inscricaoAtual()));
  }, []);

  useEffect(() => {
    void registrarSW();
    void carregar();
    // Áudio só é liberado depois de um gesto do usuário.
    const liberar = () => prepararAudio();
    window.addEventListener('pointerdown', liberar); window.addEventListener('keydown', liberar);
    return () => { window.removeEventListener('pointerdown', liberar); window.removeEventListener('keydown', liberar); };
  }, [carregar]);

  const nomeSistema = useCallback((id: number) => catalogo.sistemas.find((s) => s.id === id)?.nome ?? 'Sistema', [catalogo]);

  const mostrar = useCallback((a: Aviso) => {
    const c = a.chamado;
    const espera = Math.max(0, Math.round((Date.now() - new Date(c.criado_em).getTime()) / 60_000));
    const titulo = a.tipo === 'novo' ? `${ICONE[c.urgencia]} Novo chamado · ${URGENCIAS[c.urgencia]}`
      : `${ICONE[c.urgencia]} Sem responsável há ${espera < 60 ? `${espera} min` : `${Math.floor(espera / 60)} h`}`;
    const corpo = `${c.protocolo} · ${nomeSistema(c.sistema_id)}${a.tipo === 'lembrete' ? ` · ${URGENCIAS[c.urgencia]}` : ''}`;
    if (somLigado()) tocarSom(c.urgencia);
    const id = ++seq.current;
    setAlertas((l) => [{ id, titulo, corpo, urgencia: c.urgencia }, ...l].slice(0, 4));
    window.setTimeout(() => setAlertas((l) => l.filter((x) => x.id !== id)), c.urgencia >= 2 ? 20_000 : 9_000);
    // Sem push neste aparelho: a própria aba avisa o sistema quando estiver em segundo plano.
    if (!pushAtivo && document.hidden && suportaPush() && Notification.permission === 'granted') {
      void navigator.serviceWorker.getRegistration().then((reg) => reg?.showNotification(titulo, {
        body: corpo, tag: `chamado-${c.protocolo}`, icon: '/icon-192.png', badge: '/badge-72.png',
        requireInteraction: c.urgencia >= 2, data: { url: '/' },
      }));
    }
  }, [nomeSistema, pushAtivo]);

  // Chamados novos (realtime) e lembretes (relógio), só para o time que assume.
  useEffect(() => {
    if (!avisar) return;
    const regras = config?.regras ?? REGRAS_PADRAO;
    if (!iniciou.current) {
      if (!chamados.length) return;
      marcarVistos(chamados, regras, Date.now(), vistos.current);
      iniciou.current = true;
      return;
    }
    avisosDevidos(chamados, regras, config?.expediente ?? EXPEDIENTE_PADRAO, Date.now(), vistos.current, euId).forEach(mostrar);
  }, [avisar, chamados, config, euId, mostrar]);
  useEffect(() => {
    if (!avisar) return;
    const t = window.setInterval(() => {
      if (!iniciou.current) return;
      avisosDevidos(chamados, config?.regras ?? REGRAS_PADRAO, config?.expediente ?? EXPEDIENTE_PADRAO, Date.now(), vistos.current, euId).forEach(mostrar);
    }, 30_000);
    return () => window.clearInterval(t);
  }, [avisar, chamados, config, euId, mostrar]);

  async function executar(f: () => Promise<unknown>, ok: string) {
    setOcupado(true); setAviso('');
    try { await f(); setAviso(ok); } catch (e) { setAviso(mensagemErro(e)); }
    finally { setOcupado(false); await carregar(); }
  }

  return {
    config, pushAtivo, som, alertas, ocupado, aviso, suporta: suportaPush(),
    fechar: (id: number) => setAlertas((l) => l.filter((x) => x.id !== id)),
    setSom: (v: boolean) => { definirSom(v); setSomEstado(v); if (v) { prepararAudio(); tocarSom(1); } },
    ouvir: (u: Chamado['urgencia']) => { prepararAudio(); tocarSom(u); },
    ativar: () => executar(async () => {
      prepararAudio();
      let c = config ?? (await configPush());
      if (!c.vapid_public_key) c = await configPush();
      if (!c.vapid_public_key) throw new Error('O servidor de notificações ainda está sendo preparado. Tente de novo em 1 minuto.');
      await ativarPush(c.vapid_public_key);
    }, 'Notificações ativadas neste aparelho.'),
    desativar: () => executar(desativarPush, 'Notificações desativadas neste aparelho.'),
    testar: () => executar(testarPush, 'Teste enviado. Deve chegar em alguns segundos.'),
  };
}
