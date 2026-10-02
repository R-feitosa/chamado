import { useEffect, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';
import { carregarCatalogo, carregarCatalogoPublico, vincularConta } from '../lib/api';
import type { Catalogo, Pessoa } from '../lib/tipos';

/**
 * Sem login: modo público (abre chamado escolhendo o nome na lista).
 * Com login: só o time de dev/suporte usa; outras contas caem em 'sem-acesso'.
 */
export type EstadoSessao =
  | { fase: 'carregando' }
  | { fase: 'publico'; catalogo: Catalogo }
  | { fase: 'nova-senha' }
  | { fase: 'sem-acesso'; email: string; catalogo: Catalogo }
  | { fase: 'erro'; mensagem: string }
  | { fase: 'dev'; sessao: Session; eu: Pessoa; catalogo: Catalogo };

export function useSessao(): EstadoSessao {
  const [estado, setEstado] = useState<EstadoSessao>({ fase: 'carregando' });

  useEffect(() => {
    let vivo = true;
    let atual: string | null = null; // user id já processado, ou '' para o modo público

    async function publico() {
      if (atual === '') return;
      atual = '';
      try {
        const catalogo = await carregarCatalogoPublico();
        if (vivo && atual === '') setEstado({ fase: 'publico', catalogo });
      } catch {
        atual = null;
        if (vivo) setEstado({ fase: 'erro', mensagem: 'Não foi possível carregar o formulário. Recarregue a página.' });
      }
    }

    async function entrar(sessao: Session) {
      if (atual === sessao.user.id) return; // renovação de token
      atual = sessao.user.id;
      setEstado({ fase: 'carregando' });
      try {
        const eu = await vincularConta();
        if (!vivo || atual !== sessao.user.id) return;
        if (eu?.papel === 'dev') {
          const catalogo = await carregarCatalogo();
          if (vivo) setEstado({ fase: 'dev', sessao, eu, catalogo });
        } else {
          const catalogo = await carregarCatalogoPublico();
          if (vivo) setEstado({ fase: 'sem-acesso', email: sessao.user.email ?? '', catalogo });
        }
      } catch {
        atual = null;
        if (vivo) setEstado({ fase: 'erro', mensagem: 'Não foi possível carregar seus dados. Recarregue a página.' });
      }
    }

    const { data: sub } = supabase.auth.onAuthStateChange((evento, sessao) => {
      if (evento === 'PASSWORD_RECOVERY') { atual = null; setEstado({ fase: 'nova-senha' }); return; }
      // Evita chamar o Supabase de dentro do callback (recomendação da biblioteca).
      setTimeout(() => { if (vivo) void (sessao ? entrar(sessao) : publico()); }, 0);
    });
    return () => { vivo = false; sub.subscription.unsubscribe(); };
  }, []);

  return estado;
}
