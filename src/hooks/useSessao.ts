import { useEffect, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';
import { carregarCatalogo, vincularConta } from '../lib/api';
import type { Catalogo, Pessoa } from '../lib/tipos';

export type EstadoSessao =
  | { fase: 'carregando' }
  | { fase: 'deslogado' }
  | { fase: 'nova-senha' }
  | { fase: 'sem-cadastro'; email: string }
  | { fase: 'erro'; mensagem: string }
  | { fase: 'pronto'; sessao: Session; eu: Pessoa; catalogo: Catalogo };

export function useSessao(): EstadoSessao {
  const [estado, setEstado] = useState<EstadoSessao>({ fase: 'carregando' });

  useEffect(() => {
    let vivo = true;
    let usuarioAtual: string | null = null;

    async function entrar(sessao: Session) {
      if (usuarioAtual === sessao.user.id) return; // renovação de token: nada muda
      usuarioAtual = sessao.user.id;
      setEstado({ fase: 'carregando' });
      try {
        const eu = await vincularConta();
        if (!vivo) return;
        if (!eu) { setEstado({ fase: 'sem-cadastro', email: sessao.user.email ?? '' }); return; }
        const catalogo = await carregarCatalogo();
        if (vivo) setEstado({ fase: 'pronto', sessao, eu, catalogo });
      } catch {
        usuarioAtual = null;
        if (vivo) setEstado({ fase: 'erro', mensagem: 'Não foi possível carregar seus dados. Recarregue a página.' });
      }
    }

    const { data: sub } = supabase.auth.onAuthStateChange((evento, sessao) => {
      if (evento === 'PASSWORD_RECOVERY') { usuarioAtual = null; setEstado({ fase: 'nova-senha' }); return; }
      if (!sessao) { usuarioAtual = null; setEstado({ fase: 'deslogado' }); return; }
      // Evita chamar o Supabase de dentro do callback (recomendação da biblioteca).
      setTimeout(() => { if (vivo) void entrar(sessao); }, 0);
    });
    return () => { vivo = false; sub.subscription.unsubscribe(); };
  }, []);

  return estado;
}
