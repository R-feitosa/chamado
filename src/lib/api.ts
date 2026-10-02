import { supabase } from './supabase';
import type { Catalogo, Chamado, Pessoa, Urgencia } from './tipos';

const BUCKET = 'chamados-prints';

export async function vincularConta(): Promise<Pessoa | null> {
  const { data, error } = await supabase.rpc('vincular_minha_conta');
  if (error) throw error;
  return (data as Pessoa | null) ?? null;
}

export async function carregarCatalogo(): Promise<Catalogo> {
  const [s, p, si, u, pz] = await Promise.all([
    supabase.from('setores').select('*').order('ordem'),
    supabase.from('pessoas').select('id,nome,setor_id,papel,ativo').order('nome'),
    supabase.from('sistemas').select('*').order('ordem'),
    supabase.from('urgencias').select('*').order('nivel'),
    supabase.from('prazos').select('*'),
  ]);
  const erro = s.error || p.error || si.error || u.error || pz.error;
  if (erro) throw erro;
  return { setores: s.data ?? [], pessoas: p.data ?? [], sistemas: si.data ?? [], urgencias: u.data ?? [], prazos: pz.data ?? [] };
}

export async function listarChamados(): Promise<Chamado[]> {
  const { data, error } = await supabase.from('chamados').select('*').order('criado_em', { ascending: false });
  if (error) throw error;
  return (data ?? []) as Chamado[];
}

function extensao(f: File): string {
  return ({ 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp', 'image/gif': 'gif' } as Record<string, string>)[f.type] ?? 'img';
}

/** Catálogo do formulário para quem não está logado (só nome e setor dos solicitantes). */
export async function carregarCatalogoPublico(): Promise<Catalogo> {
  const { data, error } = await supabase.rpc('catalogo_publico');
  if (error) throw error;
  const c = data as Omit<Catalogo, 'pessoas'> & { pessoas: { id: string; nome: string; setor_id: number }[] };
  return { ...c, pessoas: c.pessoas.map((p) => ({ ...p, papel: 'solicitante', ativo: true })) };
}

export interface ChamadoAberto { protocolo: string; sistema_id: number; urgencia: Urgencia; prints: number; prazo_assumir_em: string; prazo_em: string }

async function enviarPrints(pasta: string, arquivos: File[]): Promise<string[]> {
  const caminhos: string[] = [];
  for (const f of arquivos) {
    const caminho = `${pasta}/${crypto.randomUUID()}.${extensao(f)}`;
    const { error } = await supabase.storage.from(BUCKET).upload(caminho, f, { contentType: f.type, upsert: false });
    if (error) throw error;
    caminhos.push(caminho);
  }
  return caminhos;
}

interface DadosChamado { sistemaId: number; descricao: string; urgencia: Urgencia; arquivos: File[] }

/** Quem chega pelo botão "Abrir chamado" de um sistema do hub (lido do token, sem login). */
export interface Convite {
  nome: string; setor_id: number | null; setor: string | null; precisa_setor: boolean;
  cargo: string | null; sistema_id: number | null; sistema_origem: string | null; expira_em: string;
}

export async function lerConvite(token: string): Promise<Convite> {
  const { data, error } = await supabase.rpc('ler_convite', { p_token: token });
  if (error) throw error;
  return data as Convite;
}

/**
 * Abre o chamado. Com login (time): em nome de quem está logado. Sem login: em nome do
 * solicitante escolhido na lista, ou de quem veio pelo token do hub; prints na pasta publico/.
 */
export async function abrirChamado(
  quem: { userId: string } | { setorId: number; solicitanteId: string } | { token: string; setorId: number | null },
  dados: DadosChamado,
): Promise<ChamadoAberto> {
  const logado = 'userId' in quem;
  const caminhos = await enviarPrints(logado ? quem.userId : 'publico', dados.arquivos);
  try {
    const base = { p_sistema_id: dados.sistemaId, p_descricao: dados.descricao, p_urgencia: dados.urgencia, p_prints: caminhos };
    const { data, error } = logado
      ? await supabase.rpc('abrir_chamado', base)
      : 'token' in quem
        ? await supabase.rpc('abrir_chamado_por_convite', { p_token: quem.token, p_setor_id: quem.setorId, ...base })
        : await supabase.rpc('abrir_chamado_publico', { p_setor_id: quem.setorId, p_solicitante_id: quem.solicitanteId, ...base });
    if (error) throw error;
    const c = data as ChamadoAberto & { prints: number | string[] };
    return { ...c, prints: Array.isArray(c.prints) ? c.prints.length : c.prints };
  } catch (e) {
    // Com login dá para apagar os prints órfãos; sem login, a pasta publico/ só aceita gravação.
    if (logado && caminhos.length) await supabase.storage.from(BUCKET).remove(caminhos).catch(() => undefined);
    throw e;
  }
}

export interface Consulta {
  protocolo: string; status: Chamado['status']; sistema: string; grupo: string; urgencia: Urgencia;
  criado_em: string; assumido_em: string | null; resolvido_em: string | null;
  prazo_assumir_em: string; prazo_em: string; responsavel: string | null;
}

export async function consultarChamado(protocolo: string): Promise<Consulta | null> {
  const { data, error } = await supabase.rpc('consultar_chamado', { p_protocolo: protocolo });
  if (error) throw error;
  return (data as Consulta | null) ?? null;
}

export type Acao = 'assumir' | 'resolver' | 'reabrir';

export async function agir(acao: Acao, id: string): Promise<void> {
  const { error } = await supabase.rpc(`${acao}_chamado`, { p_id: id });
  if (error) throw error;
}

/** Links temporários dos prints (bucket privado), com cache em memória. */
const cacheLinks = new Map<string, { url: string; expira: number }>();
const VALIDADE_S = 3600;

export async function linksDosPrints(caminhos: string[]): Promise<Record<string, string>> {
  const agora = Date.now();
  const faltam = caminhos.filter((c) => !(cacheLinks.get(c)?.expira! > agora + 60_000));
  if (faltam.length) {
    const { data, error } = await supabase.storage.from(BUCKET).createSignedUrls(faltam, VALIDADE_S);
    if (error) throw error;
    for (const d of data ?? []) {
      if (d.path && d.signedUrl) cacheLinks.set(d.path, { url: d.signedUrl, expira: agora + VALIDADE_S * 1000 });
    }
  }
  const out: Record<string, string> = {};
  for (const c of caminhos) { const l = cacheLinks.get(c); if (l) out[c] = l.url; }
  return out;
}
