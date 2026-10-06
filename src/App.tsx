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
import { useGamificacao } from './hooks/useGamificacao';
import { listarTemporadas } from './lib/apiGam';
import { CentralL as CentralGamificacao, JornadaL as Jornada, RankingL as Ranking, SeloXPL as SeloXP, ToastsL as Toasts } from './componentes/gam/Lazy';
import { avaliacaoDaUrl, guardarCodigo, urlSemAvaliacao } from './lib/avaliacao';
import { useAlertas } from './hooks/useAlertas';
import { AvisosNaTela, Notificacoes } from './componentes/Notificacoes';

type Tela = 'abrir' | 'acompanhar' | 'entrar' | 'painel' | 'analytics' | 'jornada' | 'ranking' | 'central' | 'perfil';
type Aba = { tela: Tela; nome: string };

const ABAS_PUBLICAS: Aba[] = [{ tela: 'abrir', nome: 'Abrir chamado' }, { tela: 'acompanhar', nome: 'Acompanhar' }];
const ABAS_DEV: Aba[] = [{ tela: 'abrir', nome: 'Abrir chamado' }, { tela: 'painel', nome: 'Painel do time' }, { tela: 'analytics', nome: 'Analytics' }];
const ABAS_DEV_GAM: Aba[] = [{ tela: 'abrir', nome: 'Abrir chamado' }, { tela: 'painel', nome: 'Painel do time' }, { tela: 'jornada', nome: 'Minha jornada' },
  { tela: 'ranking', nome: 'Ranking' }, { tela: 'analytics', nome: 'Analytics' }];
const ABAS_GESTOR: Aba[] = [{ tela: 'ranking', nome: 'Ranking' }, { tela: 'analytics', nome: 'Analytics' }, { tela: 'central', nome: 'Gamificação' }];

/** Temporadas para o filtro do ranking. */
function useTemporadas(ativo: boolean) {
  const [t, setT] = useState<{ id: number; nome: string; status: string }[]>([]);
  useEffect(() => { if (ativo) listarTemporadas().then(setT).catch(() => undefined); }, [ativo]);
  return t;
}

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
        <div className="brand"><span className="logo-chip"><img src="/logo-rfg.png" alt="R. Feitosa Group" width="119" height="34" /></span><span className="brand-sep" aria-hidden="true" /><span className="brand-nome">Central de chamados</span></div>
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

/** Link "avaliar depois" (?avaliar=TI-0425.<código>): guarda o código, limpa a URL e abre o Acompanhar. */
function lerAvaliacaoDaUrl() {
  const a = avaliacaoDaUrl(location.search);
  if (a) { guardarCodigo(a.protocolo, a.codigo); history.replaceState(null, '', urlSemAvaliacao(location.href)); }
  return a;
}

function Publico({ catalogo }: { catalogo: Catalogo }) {
  const [avaliar] = useState(lerAvaliacaoDaUrl);
  const [tela, setTela] = useState<Tela>(() => (avaliar ? 'acompanhar' : telaDoEndereco(ABAS_PUBLICAS, ['entrar'])));
  const [protocolo, setProtocolo] = useState(avaliar?.protocolo ?? '');
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
        {tela === 'acompanhar' && <Acompanhar key={protocolo} inicial={protocolo} codigoInicial={avaliar?.protocolo === protocolo ? avaliar.codigo : undefined} />}
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
  // Link do botão do hub vale mesmo com alguém do time logado: abre o formulário com a identidade do link.
  const [convite, descartarConvite] = useConvite();
  const [tela, setTela] = useState<Tela>(() => {
    if (tokenDaUrl(location.search)) return 'abrir';
    const t = telaDoEndereco(ABAS_DEV_GAM);
    return t === 'abrir' && !location.hash ? 'painel' : t;
  });
  const { chamados, conexao } = useChamados();
  const alertas = useAlertas({ chamados, catalogo, euId: eu.id, avisar: true });
  const [, setTique] = useState(0);
  const abertos = chamados.filter((c) => c.status !== 'resolvido').length;
  const ir = (t: Tela) => irPara(t, setTela);
  const gam = useGamificacao(true);
  const gamAtivo = !!gam.jornada?.ativo;
  const abas = gamAtivo ? ABAS_DEV_GAM : ABAS_DEV;
  const temporadas = useTemporadas(gamAtivo);
  const [perfilId, setPerfilId] = useState<string | null>(null);
  const verPerfil = (id: string) => { if (id === eu.id) { ir('jornada'); return; } setPerfilId(id); ir('perfil'); };
  // Com a gamificação desligada, telas dela caem no painel.
  useEffect(() => { if (gam.jornada && !gamAtivo && ['jornada', 'ranking', 'perfil'].includes(tela)) setTela('painel'); }, [gam.jornada, gamAtivo, tela]);

  // Atualiza os tempos e prazos a cada minuto.
  useEffect(() => { const t = setInterval(() => setTique((n) => n + 1), 60_000); return () => clearInterval(t); }, []);

  return (
    <>
      <Cabecalho abas={abas} tela={tela} onTela={ir} contador={abertos}>
        <Notificacoes a={alertas} />
        {gamAtivo && gam.jornada?.perfil ? <SeloXP jornada={gam.jornada} ganho={gam.ganho} onAbrir={() => ir('jornada')} />
          : <span className="papel" title={eu.nome}>{eu.nome.split(' ')[0]} · {NOME_PAPEL[eu.papel]}</span>}
        <button className="sair" type="button" onClick={() => { history.replaceState(null, '', location.pathname); void supabase.auth.signOut(); }}>Sair</button>
      </Cabecalho>
      <main>
        {conexao === 'caiu' && <div className="banner" role="status">A conexão com a base caiu. Recarregue a página.</div>}
        <div hidden={tela !== 'abrir'}>
          {convite.fase === 'erro' && <div className="banner" role="alert">{convite.mensagem}</div>}
          {convite.fase === 'lendo' ? <div className="carregando">Conferindo o link…</div> : (
            <AbrirChamado key={convite.fase} catalogo={catalogo} ativa={tela === 'abrir'} onVerPainel={() => ir('painel')}
              quem={convite.fase === 'ok' ? { tipo: 'convite', token: convite.token, convite: convite.convite } : { tipo: 'dev', eu, userId }}
              onConviteUsado={descartarConvite} />
          )}
        </div>
        {tela === 'painel' && <Painel eu={eu} catalogo={catalogo} chamados={chamados} onAcao={() => void gam.atualizar(true)} />}
        {tela === 'analytics' && <Analytics catalogo={catalogo} chamados={chamados} />}
        {tela === 'jornada' && gamAtivo && <Jornada dados={gam.jornada} onLer={gam.lerTudo} onAtualizar={() => void gam.atualizar()} onRanking={() => ir('ranking')} onPerfil={verPerfil} />}
        {tela === 'ranking' && gamAtivo && <Ranking temporadas={temporadas} onPerfil={verPerfil} />}
        {tela === 'perfil' && gamAtivo && perfilId && <Jornada pessoaId={perfilId} onPerfil={verPerfil} onVoltar={() => ir('ranking')} onRanking={() => ir('ranking')} />}
      </main>
      {gamAtivo && <Toasts itens={gam.toasts} onFechar={gam.fecharToast} />}
      <AvisosNaTela a={alertas} onVer={() => ir('painel')} />
    </>
  );
}

/** Gestor: ranking, analytics e Central de Gamificação (não assume nem pontua). */
function Gestor({ eu, catalogo }: { eu: Pessoa; catalogo: Catalogo }) {
  const [tela, setTela] = useState<Tela>(() => { const h = location.hash.slice(1) as Tela; return ABAS_GESTOR.some((a) => a.tela === h) ? h : 'central'; });
  const ir = (t: Tela) => irPara(t, setTela);
  const { chamados } = useChamados();
  const alertas = useAlertas({ chamados, catalogo, euId: eu.id, avisar: false });
  const temporadas = useTemporadas(true);
  const [perfilId, setPerfilId] = useState<string | null>(null);
  return (
    <>
      <Cabecalho abas={ABAS_GESTOR} tela={tela} onTela={ir}>
        <Notificacoes a={alertas} />
        <span className="papel" title={eu.nome}>{eu.nome.split(' ')[0]} · Gestor</span>
        <button className="sair" type="button" onClick={() => { history.replaceState(null, '', location.pathname); void supabase.auth.signOut(); }}>Sair</button>
      </Cabecalho>
      <main>
        {tela === 'central' && <CentralGamificacao />}
        {tela === 'ranking' && <Ranking temporadas={temporadas} onPerfil={(id) => { setPerfilId(id); ir('perfil'); }} />}
        {tela === 'perfil' && perfilId && <Jornada pessoaId={perfilId} onVoltar={() => ir('ranking')} onPerfil={(id) => setPerfilId(id)} onRanking={() => ir('ranking')} />}
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
    case 'gestor': return <Gestor key={estado.eu.id} eu={estado.eu} catalogo={estado.catalogo} />;
  }
}
