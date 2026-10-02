import { supabase } from '../lib/supabase';

/** Conta logada que não é do time de dev/suporte. */
export function SemCadastro({ email }: { email: string }) {
  return (
    <div className="card auth">
      <h1>O login é só para o time</h1>
      <p className="muted" style={{ margin: 0 }}>
        A conta <b style={{ color: 'var(--ink)' }}>{email}</b> não está cadastrada como dev/suporte.
        Para abrir um chamado não é preciso entrar: saia e use o formulário.
      </p>
      <button className="btn pri" type="button" onClick={() => void supabase.auth.signOut()}>Sair e abrir chamado</button>
    </div>
  );
}
