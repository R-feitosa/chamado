import { supabase } from './supabase';
import type { Catalogo, Chamado, Pessoa, Urgencia } from './tipos';

const BUCKET = 'chamados-prints';

export async function vincularConta(): Promise<Pessoa | null> {
  const { data, error } = await supabase.rpc('vincular_minha_conta');
  if (error) throw error;
  return (data as Pessoa | null) ?? null;
}

export async function carregarCatalogo(): Promise<Catalogo> {
  const [s, p, si] = await Promise.all([
    supabase.from('setores').select('*').order('ordem'),
    supabase.from('pessoas').select('id,nome,setor_id,papel,ativo').order('nome'),
    supabase.from('sistemas').select('*').order('ordem'),
  ]);
  const erro = s.error || p.error || si.error;
  if (erro) throw erro;
  return { setores: s.data ?? [], pessoas: p.data ?? [], sistemas: si.data ?? [] };
}

export async function listarChamados(): Promise<Chamado[]> {
  const { data, error } = await supabase.from('chamados').select('*').order('criado_em', { ascending: false });
  if (error) throw error;
  return (data ?? []) as Chamado[];
}

function extensao(f: File): string {
  return ({ 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp', 'image/gif': 'gif' } as Record<string, string>)[f.type] ?? 'img';
}

/** Envia os prints, abre o chamado e, se a abertura falhar, apaga os prints enviados. */
export async function abrirChamado(
  userId: string,
  dados: { sistemaId: number; descricao: string; urgencia: Urgencia; arquivos: File[] },
): Promise<Chamado> {
  const caminhos: string[] = [];
  try {
    for (const f of dados.arquivos) {
      const caminho = `${userId}/${crypto.randomUUID()}.${extensao(f)}`;
      const { error } = await supabase.storage.from(BUCKET).upload(caminho, f, { contentType: f.type, upsert: false });
      if (error) throw error;
      caminhos.push(caminho);
    }
    const { data, error } = await supabase.rpc('abrir_chamado', {
      p_sistema_id: dados.sistemaId,
      p_descricao: dados.descricao,
      p_urgencia: dados.urgencia,
      p_prints: caminhos,
    });
    if (error) throw error;
    return data as Chamado;
  } catch (e) {
    if (caminhos.length) await supabase.storage.from(BUCKET).remove(caminhos).catch(() => undefined);
    throw e;
  }
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
