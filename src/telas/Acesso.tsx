import { useState, type FormEvent } from 'react';
import { supabase } from '../lib/supabase';
import { mensagemErro } from '../lib/formato';

/**
 * Login com a mesma conta dos sistemas ATLAS (projeto Supabase compartilhado).
 * Não há cadastro nem recuperação de senha aqui: isso é feito nos sistemas ATLAS.
 * O modo 'nova-senha' só aparece quando a pessoa chega por um link de recuperação.
 */
export function Acesso({ novaSenha = false }: { novaSenha?: boolean }) {
  const [email, setEmail] = useState('');
  const [senha, setSenha] = useState('');
  const [erro, setErro] = useState('');
  const [enviando, setEnviando] = useState(false);

  async function enviar(e: FormEvent) {
    e.preventDefault();
    setErro('');
    if (novaSenha && senha.length < 8) { setErro('A senha precisa ter pelo menos 8 caracteres.'); return; }
    setEnviando(true);
    try {
      const { error } = novaSenha
        ? await supabase.auth.updateUser({ password: senha })
        : await supabase.auth.signInWithPassword({ email: email.trim(), password: senha });
      if (error) throw error;
    } catch (err) {
      setErro(mensagemErro(err));
    } finally {
      setEnviando(false);
    }
  }

  return (
    <div className="card auth">
      <div>
        <h1>{novaSenha ? 'Nova senha' : 'Entrar'}</h1>
        <p className="muted" style={{ margin: '6px 0 0' }}>
          {novaSenha ? 'Escolha a nova senha de acesso.' : 'Use o mesmo e-mail e senha dos sistemas ATLAS.'}
        </p>
      </div>
      <form onSubmit={enviar} noValidate>
        {!novaSenha && (
          <div className="grp">
            <label className="lbl" htmlFor="email">E-mail</label>
            <input className="field" id="email" type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
          </div>
        )}
        <div className="grp">
          <label className="lbl" htmlFor="senha">{novaSenha ? 'Nova senha (mínimo 8 caracteres)' : 'Senha'}</label>
          <input className="field" id="senha" type="password" required autoComplete={novaSenha ? 'new-password' : 'current-password'}
            value={senha} onChange={(e) => setSenha(e.target.value)} />
        </div>
        {erro && <p className="erro" role="alert">{erro}</p>}
        <button className="btn pri" type="submit" disabled={enviando || !senha || (!novaSenha && !email.trim())}>
          {enviando ? 'Aguarde…' : novaSenha ? 'Salvar senha' : 'Entrar'}
        </button>
      </form>
      {!novaSenha && <p className="muted" style={{ margin: 0, fontSize: 13 }}>Esqueceu a senha? Use a recuperação dos sistemas ATLAS ou fale com o time de desenvolvimento.</p>}
    </div>
  );
}
