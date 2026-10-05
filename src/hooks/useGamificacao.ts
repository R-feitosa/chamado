import { useCallback, useEffect, useRef, useState } from 'react';
import { jornada as lerJornada, marcarLidas, processarAgora } from '../lib/apiGam';
import { novasDesde, type Jornada, type Notificacao } from '../lib/gamificacao';

const CHAVE = 'rfg-gam-ultima-notificacao';
const lerUltima = () => { try { return Number(localStorage.getItem(CHAVE) ?? '-1'); } catch { return -1; } };
const gravarUltima = (n: number) => { try { localStorage.setItem(CHAVE, String(n)); } catch { /* sem armazenamento: avisos podem repetir */ } };

/**
 * Estado da gamificação do técnico logado. Relê a jornada a cada 30 s e logo depois das ações do próprio
 * técnico (processando a fila antes, para o feedback não esperar o agendador). Avisos novos viram toasts;
 * variação de XP vira o "+N XP" do selo.
 */
export function useGamificacao(habilitado: boolean) {
  const [jornada, setJornada] = useState<Jornada | null>(null);
  const [toasts, setToasts] = useState<Notificacao[]>([]);
  const [ganho, setGanho] = useState<{ id: number; valor: number } | null>(null);
  const xpAnterior = useRef<number | null>(null);
  const ultima = useRef(lerUltima());

  const carregar = useCallback(async (processar = false) => {
    if (!habilitado) return;
    try {
      if (processar) await processarAgora().catch(() => undefined);
      const j = await lerJornada();
      setJornada(j);
      if (!j.perfil) return;
      const total = j.perfil.xp + j.perfil.xp_pendente;
      if (xpAnterior.current !== null && total !== xpAnterior.current) setGanho({ id: Date.now(), valor: total - xpAnterior.current });
      xpAnterior.current = total;
      const feed = j.feed ?? [];
      const maior = feed.reduce((m, n) => Math.max(m, n.id), -1);
      if (ultima.current < 0) { ultima.current = maior; gravarUltima(maior); return; } // primeiro acesso: sem avalanche de avisos antigos
      const novas = novasDesde(feed, ultima.current);
      if (novas.length) {
        setToasts((t) => [...t, ...novas.filter((n) => !t.some((x) => x.id === n.id))]);
        ultima.current = Math.max(ultima.current, maior);
        gravarUltima(ultima.current);
      }
    } catch { /* sem conexão: tenta de novo no próximo ciclo */ }
  }, [habilitado]);

  useEffect(() => {
    if (!habilitado) return;
    void carregar(true);
    const t = window.setInterval(() => void carregar(), 30_000);
    return () => window.clearInterval(t);
  }, [habilitado, carregar]);

  useEffect(() => { if (ganho) { const t = window.setTimeout(() => setGanho(null), 1600); return () => window.clearTimeout(t); } }, [ganho]);

  const fecharToast = useCallback((id: number) => setToasts((t) => t.filter((n) => n.id !== id)), []);
  const lerTudo = useCallback(async () => {
    try { await marcarLidas(); setJornada((j) => (j ? { ...j, nao_lidas: 0, feed: j.feed?.map((n) => ({ ...n, lida: true })) ?? j.feed } : j)); } catch { /* tenta depois */ }
  }, []);

  return { jornada, toasts, ganho, fecharToast, atualizar: carregar, lerTudo };
}
