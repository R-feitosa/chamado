import { useEffect, useState } from 'react';
import { useSessao } from './hooks/useSessao';
import { useChamados } from './hooks/useChamados';
import { configurado, supabase } from './lib/supabase';
import type { Catalogo, Pessoa } from './lib/tipos';
import { Acesso } from './telas/Acesso';
import { SemCadastro } from './telas/SemCadastro';
import { AbrirChamado } from './telas/AbrirChamado';
import { Painel } from './telas/Painel';

type Tela = 'abrir' | 'painel';

function Cabecalho({ children }: { children?: React.ReactNode }) {
  return (
    <header className="top">
      <div className="top-in">
        <div className="brand"><span className="mark">RFG</span><div><b>Central de chamados</b><small>R. Feitosa Group</small></div></div>
        {children}
      </div>
    </header>
  );
}

function Logado({ eu, userId, catalogo }: { eu: Pessoa; userId: string; catalogo: Catalogo }) {
  const dev = eu.papel === 'dev';
  const [tela, setTela] = useState<Tela>(dev && location.hash === '#painel' ? 'painel' : 'abrir');
  const { chamados, conexao } = useChamados();
  const [, setTique] = useState(0);
  const abertos = chamados.filter((c) => c.status !== 'resolvido').length;

  // Atualiza o "há X min" da fila a cada minuto.
  useEffect(() => { const t = setInterval(() => setTique((n) => n + 1), 60_000); return () => clearInterval(t); }, []);

  function irPara(t: Tela) { setTela(t); history.replaceState(null, '', t === 'painel' ? '#painel' : '#'); window.scrollTo(0, 0); }

  return (
    <>
      <Cabecalho>
        <div className="conta">
          {dev && (
            <div className="tabs" role="tablist" aria-label="Telas">
              <button className="tab" role="tab" aria-selected={tela === 'abrir'} onClick={() => irPara('abrir')}>Abrir chamado</button>
              <button className="tab" role="tab" aria-selected={tela === 'painel'} onClick={() => irPara('painel')}>Painel do time<span className="n">{abertos}</span></button>
            </div>
          )}
          <button className="sair" type="button" onClick={() => void supabase.auth.signOut()} title={`Conectado como ${eu.nome}`}>Sair</button>
        </div>
      </Cabecalho>
      <main>
        {conexao === 'caiu' && <div className="banner" role="status">A conexão com a base caiu. Recarregue a página.</div>}
        <div hidden={tela !== 'abrir'}>
          <AbrirChamado eu={eu} userId={userId} catalogo={catalogo} ativa={tela === 'abrir'} onVerPainel={dev ? () => irPara('painel') : undefined} />
        </div>
        {dev && tela === 'painel' && <Painel eu={eu} catalogo={catalogo} chamados={chamados} />}
      </main>
    </>
  );
}

export function App() {
  const estado = useSessao();

  if (!configurado) {
    return (<><Cabecalho /><main><div className="card auth"><h1>Configuração pendente</h1>
      <p className="muted" style={{ margin: 0 }}>Defina VITE_SUPABASE_URL e VITE_SUPABASE_PUBLISHABLE_KEY (veja .env.example).</p></div></main></>);
  }

  switch (estado.fase) {
    case 'carregando': return (<><Cabecalho /><div className="carregando">Carregando…</div></>);
    case 'deslogado': return (<><Cabecalho /><main><Acesso /></main></>);
    case 'nova-senha': return (<><Cabecalho /><main><Acesso novaSenha /></main></>);
    case 'sem-cadastro': return (<><Cabecalho /><main><SemCadastro email={estado.email} /></main></>);
    case 'erro': return (<><Cabecalho /><main><p className="erro">{estado.mensagem}</p></main></>);
    case 'pronto': return <Logado key={estado.eu.id} eu={estado.eu} userId={estado.sessao.user.id} catalogo={estado.catalogo} />;
  }
}
