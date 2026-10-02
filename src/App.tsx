import { useEffect, useState } from 'react';
import { useSessao } from './hooks/useSessao';
import { useChamados } from './hooks/useChamados';
import { supabase } from './lib/supabase';
import { NOME_PAPEL, type Catalogo, type Pessoa } from './lib/tipos';
import { Acesso } from './telas/Acesso';
import { SemCadastro } from './telas/SemCadastro';
import { AbrirChamado } from './telas/AbrirChamado';
import { Painel } from './telas/Painel';
import { MeusChamados } from './telas/MeusChamados';
import { Analytics } from './telas/Analytics';

type Tela = 'abrir' | 'meus' | 'painel' | 'analytics';

const ABAS: Record<'dev' | 'solicitante', { tela: Tela; nome: string }[]> = {
  dev: [{ tela: 'abrir', nome: 'Abrir chamado' }, { tela: 'painel', nome: 'Painel do time' }, { tela: 'analytics', nome: 'Analytics' }],
  solicitante: [{ tela: 'abrir', nome: 'Abrir chamado' }, { tela: 'meus', nome: 'Meus chamados' }],
};

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
  const abas = ABAS[eu.papel];
  const inicial = abas.find((a) => `#${a.tela}` === location.hash)?.tela ?? 'abrir';
  const [tela, setTela] = useState<Tela>(inicial);
  const { chamados, conexao } = useChamados();
  const [, setTique] = useState(0);
  const abertos = chamados.filter((c) => c.status !== 'resolvido' && (dev || c.solicitante_id === eu.id)).length;

  // Atualiza os tempos ("aberto há") a cada minuto.
  useEffect(() => { const t = setInterval(() => setTique((n) => n + 1), 60_000); return () => clearInterval(t); }, []);

  function irPara(t: Tela) { setTela(t); history.replaceState(null, '', t === 'abrir' ? '#' : `#${t}`); window.scrollTo(0, 0); }

  return (
    <>
      <Cabecalho>
        <div className="conta">
          <div className="tabs" role="tablist" aria-label="Telas">
            {abas.map((a) => (
              <button key={a.tela} className="tab" role="tab" aria-selected={tela === a.tela} onClick={() => irPara(a.tela)}>
                {a.nome}{(a.tela === 'painel' || a.tela === 'meus') && <span className="n">{abertos}</span>}
              </button>
            ))}
          </div>
          <span className="papel" title={eu.nome}>{eu.nome.split(' ')[0]} · {NOME_PAPEL[eu.papel]}</span>
          <button className="sair" type="button" onClick={() => void supabase.auth.signOut()}>Sair</button>
        </div>
      </Cabecalho>
      <main>
        {conexao === 'caiu' && <div className="banner" role="status">A conexão com a base caiu. Recarregue a página.</div>}
        <div hidden={tela !== 'abrir'}>
          <AbrirChamado eu={eu} userId={userId} catalogo={catalogo} ativa={tela === 'abrir'}
            onVerPainel={() => irPara(dev ? 'painel' : 'meus')} rotuloVer={dev ? 'Ver no painel do time' : 'Ver meus chamados'} />
        </div>
        {tela === 'meus' && <MeusChamados eu={eu} catalogo={catalogo} chamados={chamados} onAbrir={() => irPara('abrir')} />}
        {dev && tela === 'painel' && <Painel eu={eu} catalogo={catalogo} chamados={chamados} />}
        {dev && tela === 'analytics' && <Analytics catalogo={catalogo} chamados={chamados} />}
      </main>
    </>
  );
}

export function App() {
  const estado = useSessao();

  switch (estado.fase) {
    case 'carregando': return (<><Cabecalho /><div className="carregando">Carregando…</div></>);
    case 'deslogado': return (<><Cabecalho /><main><Acesso /></main></>);
    case 'nova-senha': return (<><Cabecalho /><main><Acesso novaSenha /></main></>);
    case 'sem-cadastro': return (<><Cabecalho /><main><SemCadastro email={estado.email} /></main></>);
    case 'erro': return (<><Cabecalho /><main><p className="erro">{estado.mensagem}</p></main></>);
    case 'pronto': return <Logado key={estado.eu.id} eu={estado.eu} userId={estado.sessao.user.id} catalogo={estado.catalogo} />;
  }
}
