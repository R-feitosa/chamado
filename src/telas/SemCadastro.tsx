import { supabase } from '../lib/supabase';

export function SemCadastro({ email }: { email: string }) {
  return (
    <div className="card auth">
      <h1>Acesso ainda não liberado</h1>
      <p className="muted" style={{ margin: 0 }}>
        O e-mail <b style={{ color: 'var(--ink)' }}>{email}</b> não está cadastrado na Central de Chamados.
        Peça ao time de desenvolvimento para incluir seu e-mail e entre de novo.
      </p>
      <button className="btn sec" type="button" onClick={() => void supabase.auth.signOut()}>Sair e usar outro e-mail</button>
    </div>
  );
}
