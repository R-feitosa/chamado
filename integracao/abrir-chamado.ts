/**
 * Botão "Abrir chamado" para os sistemas do hub (ATLAS - INTEGRADO).
 *
 * Copie este arquivo para o sistema e chame `abrirChamado(supabase, 'crm')` no clique.
 * Requisitos: o usuário estar logado no sistema (mesmo Supabase da Central) e o schema
 * `chamados` exposto na API (já está). Nome, setor e cargo são lidos pelo banco a partir
 * do login; o navegador só envia o sistema, a tela atual e dados técnicos.
 */

/** Mínimo do cliente Supabase usado aqui (compatível com @supabase/supabase-js v2). */
interface ClienteSupabase {
  schema(nome: string): { rpc(fn: string, args: Record<string, unknown>): PromiseLike<{ data: unknown; error: { message: string } | null }> };
}

/** Códigos aceitos (hub.sistemas.codigo). */
export type SistemaHub =
  | 'academy' | 'cash' | 'consult' | 'crm' | 'hub' | 'imoveis' | 'juris'
  | 'legal_ops' | 'ponto' | 'rf_ops' | 'rh' | 'tributario' | 'valley';

function navegador(ua: string): string {
  const m = ua.match(/(Edg|OPR|Chrome|Firefox|Safari)\/(\d+)/);
  const nome = m ? ({ Edg: 'Edge', OPR: 'Opera' } as Record<string, string>)[m[1]] ?? m[1] : 'Outro';
  const so = /Windows/.test(ua) ? 'Windows' : /Android/.test(ua) ? 'Android' : /iPhone|iPad/.test(ua) ? 'iOS' : /Mac OS/.test(ua) ? 'macOS' : /Linux/.test(ua) ? 'Linux' : '';
  return [m ? `${nome} ${m[2]}` : nome, so].filter(Boolean).join(' · ');
}

/**
 * Gera o link (válido por 2 h, uso único) e abre a Central de Chamados numa nova aba.
 * @param versao opcional: versão do sistema, para o time saber em qual build o problema aconteceu.
 */
export async function abrirChamado(supabase: ClienteSupabase, sistema: SistemaHub, versao?: string): Promise<void> {
  // Abre a aba já no clique (evita bloqueio de pop-up) e depois aponta para o link.
  const aba = window.open('about:blank', '_blank');
  const contexto: Record<string, string> = {
    navegador: navegador(navigator.userAgent),
    resolucao: `${window.screen.width}×${window.screen.height}`,
  };
  if (versao) contexto.versao = versao;
  const { data, error } = await supabase.schema('chamados').rpc('gerar_link_chamado', {
    p_sistema: sistema,
    p_url: location.href.slice(0, 500),
    p_contexto: contexto,
  });
  const url = (data as { url?: string } | null)?.url;
  if (error || !url) {
    aba?.close();
    throw new Error(error?.message ?? 'Não foi possível gerar o link do chamado.');
  }
  if (aba) { aba.opener = null; aba.location.href = url; } else { window.location.href = url; }
}
