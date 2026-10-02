import { createClient } from '@supabase/supabase-js';

// Projeto ATLAS - INTEGRADO. URL e chave publicável são públicas por natureza
// (vão para o navegador de qualquer forma; a proteção está na RLS do banco),
// por isso servem de padrão. Variáveis de ambiente, se definidas, têm prioridade.
const URL_PADRAO = 'https://ashxrwwlcarvqdigoxsi.supabase.co';
const CHAVE_PADRAO = 'sb_publishable_ZpMp4GXRi9BNHoORkzQvLA_H9CStT-T';

const url = (import.meta.env.VITE_SUPABASE_URL as string | undefined) || URL_PADRAO;
const chave = (import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined) || CHAVE_PADRAO;

export const supabase = createClient(url, chave, {
  db: { schema: 'chamados' },
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
});
