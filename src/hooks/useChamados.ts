import { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from '../lib/supabase';
import { listarChamados } from '../lib/api';
import type { Chamado } from '../lib/tipos';

/** Lista de chamados visíveis ao usuário, atualizada em tempo real. */
export function useChamados() {
  const [chamados, setChamados] = useState<Chamado[]>([]);
  const [conexao, setConexao] = useState<'conectando' | 'ok' | 'caiu'>('conectando');
  const timer = useRef<number>();

  const recarregar = useCallback(async () => {
    try { setChamados(await listarChamados()); } catch { setConexao('caiu'); }
  }, []);

  useEffect(() => {
    void recarregar();
    const canal = supabase
      .channel('chamados')
      .on('postgres_changes', { event: '*', schema: 'chamados', table: 'chamados' }, () => {
        // Agrupa rajadas de mudanças numa única releitura.
        window.clearTimeout(timer.current);
        timer.current = window.setTimeout(() => void recarregar(), 250);
      })
      .subscribe((s) => {
        if (s === 'SUBSCRIBED') { setConexao('ok'); void recarregar(); }
        if (s === 'CHANNEL_ERROR' || s === 'TIMED_OUT' || s === 'CLOSED') setConexao('caiu');
      });
    return () => { window.clearTimeout(timer.current); void supabase.removeChannel(canal); };
  }, [recarregar]);

  return { chamados, conexao, recarregar };
}
