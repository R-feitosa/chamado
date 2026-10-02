import { useEffect, useState } from 'react';
import { lerConvite, type Convite } from './lib/api';
import { tokenDaUrl, urlSemToken } from './lib/convite';
import { mensagemErro } from './lib/formato';
import { useSessao } from './hooks/useSessao';
import { useChamados } from './hooks/useChamados';
import { supabase } from './lib/supabase';
import { NOME_PAPEL, type Catalogo, type Pessoa } from './lib/tipos';
import { Acesso } from './telas/Acesso';
import { SemCadastro } from './telas/SemCadastro';
import { AbrirChamado } from './telas/AbrirChamado';
import { Acompanhar } from './telas/Acompanhar';
import { Painel } from './telas/Painel';
import { Analytics } from './telas/Analytics';

type Tela = 'abrir' | 'acompanhar' | 'entrar' | 'painel' | 'analytics';
type Aba = { tela: Tela; nome: string };

const ABAS_PUBLICAS: Aba[] = [{ tela: 'abrir', nome: 'Abrir chamado' }, { tela: 'acompanhar', nome: 'Acompanhar' }];
const ABAS_DEV: Aba[] = [{ tela: 'abrir', nome: 'Abrir chamado' }, { tela: 'painel', nome: 'Painel do time' }, { tela: 'analytics', nome: 'Analytics' }];

function telaDoEndereco(abas: Aba[], extra: Tela[] = []): Tela {
  const h = location.hash.slice(1) as Tela;
  return abas.some((a) => a.tela === h) || extra.includes(h) ? h : 'abrir';
}

function irPara(t: Tela, set: (t: Tela) => void) {
  set(t); history.replaceState(null, '', t === 'abrir' ? location.pathname : `#${t}`); window.scrollTo(0, 0);
}

function Cabecalho({ abas, tela, onTela, contador, children }: {
  abas?: Aba[]; tela?: Tela; onTela?: (t: Tela) => void; contador?: number; children?: React.ReactNode;
}) {
  return (
    <header className="top">
      <div className="top-in">
        <div className="brand"><span className="mark">RFG</span><div><b>Central de chamados</b><small>R. Feitosa Group</small></div></div>
        <div className="conta">
          {abas && onTela && (
            <div className="tabs" role="tablist" aria-label="Telas">
              {abas.map((a) => (
                <button key={a.tela} className="tab" role="tab" aria-selected={tela === a.tela} onClick={() => onTela(a.tela)}>
                  {a.nome}{a.tela === 'painel' && contador !== undefined && <span className="n">{contador}</span>}
                </button>
              ))}
            </div>
          )}
          {children}
        </div>
      </div>
    </header>
  );
}

/** Sem login: abrir e acompanhar chamados; o time entra pelo botão. */
type EstadoConvite = { fase: 'nenhum' } | { fase: 'lendo' } | { fase: 'ok'; token: string; convite: Convite } | { fase: 'erro'; mensagem: string };

/** Lê o token do botão do hub (?t=) uma vez e o tira da barra de endereço. */
function useConvite(): [EstadoConvite, () => void] {
  const [estado, setEstado] = useState<EstadoConvite>(() => (tokenDaUrl(location.search) ? { fase: 'lendo' } : { fase: 'nenhum' }));
  useEffect(() => {
    const token = tokenDaUrl(location.search);
    if (!token) return;
    history.replaceState(null, '', urlSemToken(location.href));
    let vivo = true;
    lerConvite(token)
      .then((convite) => { if (vivo) setEstado({ fase: 'ok', token, convite }); })
      .catch((e) => { if (vivo) setEstado({ fase: 'erro', mensagem: mensagemErro(e, 'Não foi possível ler o link. Abra o chamado pelo formulário.') }); });
    return () => { vivo = false; };
  }, []);
  return [estado, () => setEstado({ fase: 'nenhum' })];
}

function Publico({ catalogo }: { catalogo: Catalogo }) {
  const [tela, setTela] = useState<Tela>(() => telaDoEndereco(ABAS_PUBLICAS, ['entrar']));
  const [protocolo, setProtocolo] = useState('');
  const [convite, descartarConvite] = useConvite();
  const ir = (t: Tela) => irPara(t, setTela);
  return (
    <>
      <Cabecalho abas={ABAS_PUBLICAS} tela={tela} onTela={ir}>
        {tela !== 'entrar' && (
          <button type="button" className="entrar" onClick={() => ir('entrar')}><span>É dev/suporte? </span><b>Entrar</b></button>
        )}
      </Cabecalho>
      <main>
        <div hidden={tela !== 'abrir'}>
          {convite.fase === 'erro' && <div className="banner" role="alert">{convite.mensagem}</div>}
          {convite.fase === 'lendo' ? <div className="carregando">Conferindo o link…</div> : (
            <AbrirChamado key={convite.fase} catalogo={catalogo} ativa={tela === 'abrir'}
              quem={convite.fase === 'ok' ? { tipo: 'convite', token: convite.token, convite: convite.convite } : { tipo: 'publico' }}
              onConviteUsado={descartarConvite}
              onAcompanhar={(p) => { setProtocolo(p); ir('acompanhar'); }} />
          )}
        </div>
        {tela === 'acompanhar' && <Acompanhar key={protocolo} inicial={protocolo} />}
        {tela === 'entrar' && (
          <>
            <Acesso />
            <p style={{ textAlign: 'center', marginTop: 16 }}>
              <button type="button" className="sair" onClick={() => ir('abrir')}>← Voltar para abrir chamado</button>
            </p>
          </>
        )}
      </main>
    </>
  );
}

/** Time de dev/suporte logado. */
function Dev({ eu, userId, catalogo }: { eu: Pessoa; userId: string; catalogo: Catalogo }) {
  const [tela, setTela] = useState<Tela>(() => {
    const t = telaDoEndereco(ABAS_DEV);
    return t === 'abrir' && !location.hash ? 'painel' : t;
  });
  const { chamados, conexao } = useChamados();
  const [, setTique] = useState(0);
  const abertos = chamados.filter((c) => c.status !== 'resolvido').length;
  const ir = (t: Tela) => irPara(t, setTela);

  // Atualiza os tempos e prazos a cada minuto.
  useEffect(() => { const t = setInterval(() => setTique((n) => n + 1), 60_000); return () => clearInterval(t); }, []);

  return (
    <>
      <Cabecalho abas={ABAS_DEV} tela={tela} onTela={ir} contador={abertos}>
        <span className="papel" title={eu.nome}>{eu.nome.split(' ')[0]} · {NOME_PAPEL[eu.papel]}</span>
        <button className="sair" type="button" onClick={() => { history.replaceState(null, '', location.pathname); void supabase.auth.signOut(); }}>Sair</button>
      </Cabecalho>
      <main>
        {conexao === 'caiu' && <div className="banner" role="status">A conexão com a base caiu. Recarregue a página.</div>}
        <div hidden={tela !== 'abrir'}>
          <AbrirChamado quem={{ tipo: 'dev', eu, userId }} catalogo={catalogo} ativa={tela === 'abrir'} onVerPainel={() => ir('painel')} />
        </div>
        {tela === 'painel' && <Painel eu={eu} catalogo={catalogo} chamados={chamados} />}
        {tela === 'analytics' && <Analytics catalogo={catalogo} chamados={chamados} />}
      </main>
    </>
  );
}

export function App() {
  const estado = useSessao();
  switch (estado.fase) {
    case 'carregando': return (<><Cabecalho /><div className="carregando">Carregando…</div></>);
    case 'publico': return <Publico catalogo={estado.catalogo} />;
    case 'nova-senha': return (<><Cabecalho /><main><Acesso novaSenha /></main></>);
    case 'sem-acesso': return (<><Cabecalho /><main><SemCadastro email={estado.email} /></main></>);
    case 'erro': return (<><Cabecalho /><main><p className="erro">{estado.mensagem}</p></main></>);
    case 'dev': return <Dev key={estado.eu.id} eu={estado.eu} userId={estado.sessao.user.id} catalogo={estado.catalogo} />;
  }
}
