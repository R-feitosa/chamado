import { useMemo, useState } from 'react';
import { agir, type Acao } from '../lib/api';
import { FILTROS, indicadores, noFiltro, ordenar, type Filtro } from '../lib/fila';
import { duracao, inicioDoPeriodo, resolvidosNoPeriodo, tempoDaFila, temposMedios } from '../lib/analytics';
import { formatoPct, situacaoPrazo, taxaAssumidoNoPrazo, taxaNoPrazo, textoPrazo } from '../lib/sla';
import { hojePorExtenso, iniciais, mensagemErro, titulo } from '../lib/formato';
import type { Catalogo, Chamado, Pessoa } from '../lib/tipos';
import { MiniPrints } from '../componentes/MiniPrints';
import { PilulaUrgencia } from '../componentes/Urgencia';
import { Ampliar } from '../componentes/Ampliar';

interface Props { eu: Pessoa; catalogo: Catalogo; chamados: Chamado[] }

const ROTULOS: Record<string, string> = { tela: 'Página', cargo: 'Cargo', departamento: 'Departamento', email: 'E-mail', navegador: 'Navegador', resolucao: 'Resolução', versao: 'Versão' };

/** Chamado aberto pelo botão de um sistema do hub: origem e contexto técnico (só o time vê). */
function OrigemHub({ c, nome }: { c: Chamado; nome: string | null }) {
  const itens = Object.entries(c.contexto ?? {}).filter(([, v]) => v);
  return (
    <details className="origem">
      <summary><span className="pill andamento">via {nome ?? 'hub'}</span></summary>
      {itens.length > 0 && (
        <dl>
          {itens.map(([k, v]) => (
            <div key={k}><dt>{ROTULOS[k] ?? k}</dt>
              <dd>{k === 'tela' && /^https?:\/\//.test(v) ? <a href={v} target="_blank" rel="noreferrer noopener">{v}</a> : k === 'email' ? <a href={`mailto:${v}`}>{v}</a> : v}</dd></div>
          ))}
        </dl>
      )}
    </details>
  );
}

const fmt = (iso: string) => new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });

export function Painel({ eu, catalogo, chamados }: Props) {
  const [filtro, setFiltro] = useState<Filtro>('abertos');
  const [ocupado, setOcupado] = useState<string | null>(null);
  const [erro, setErro] = useState('');
  const [ampliado, setAmpliado] = useState<string | null>(null);

  const pessoa = useMemo(() => new Map(catalogo.pessoas.map((p) => [p.id, p])), [catalogo]);
  const setor = useMemo(() => new Map(catalogo.setores.map((s) => [s.id, s.nome])), [catalogo]);
  const sistema = useMemo(() => new Map(catalogo.sistemas.map((s) => [s.id, s.nome])), [catalogo]);
  const sistemaHub = useMemo(() => new Map(catalogo.sistemas.filter((s) => s.hub_codigo).map((s) => [s.hub_codigo!, s.nome])), [catalogo]);

  const agora = Date.now();
  const k = indicadores(chamados, eu.id, agora);
  const desde30 = inicioDoPeriodo('30', agora);
  const noPrazo = taxaNoPrazo(resolvidosNoPeriodo(chamados, desde30));
  const assumidosNoPrazo = taxaAssumidoNoPrazo(chamados.filter((c) => c.assumido_em && new Date(c.assumido_em).getTime() >= desde30));
  const fila = tempoDaFila(chamados, agora);
  const t30 = temposMedios(chamados, desde30);
  const lista = ordenar(chamados.filter((c) => noFiltro(filtro, c, eu.id)));

  async function executar(acao: Acao, id: string) {
    setOcupado(id); setErro('');
    try { await agir(acao, id); } catch (e) { setErro(mensagemErro(e)); } finally { setOcupado(null); }
  }

  const contagens: [string, number, string][] = [
    ['Em aberto', k.emAberto, 'var(--accent)'],
    ['Sem responsável', k.semResponsavel, 'var(--warn)'],
    ['Atrasados', k.atrasados, 'var(--bad)'],
    ['Meus', k.meus, 'var(--ok)'],
  ];
  const tempos: [string, string, string][] = [
    ['Espera sem responsável', duracao(fila.esperaMediaSemResponsavel), 'média dos que aguardam'],
    ['Mais antigo em aberto', duracao(fila.maisAntigo), 'desde a abertura'],
    ['Assumidos no prazo', formatoPct(assumidosNoPrazo), `média ${duracao(t30.mediaAssumir)} · 30 dias`],
    ['Resolvidos no prazo', formatoPct(noPrazo), `média ${duracao(t30.mediaResolver)} · 30 dias`],
  ];

  return (
    <section>
      <div className="ph">
        <div><div className="sub">{hojePorExtenso()}</div><h1>Olá, {eu.nome}</h1></div>
      </div>
      <div className="kpis">
        {contagens.map(([nome, n, cor]) => (
          <div key={nome} className="card kpi"><span><i className="dot" style={{ background: cor }} />{nome}</span><b>{n}</b></div>
        ))}
        {tempos.map(([nome, valor, nota]) => (
          <div key={nome} className="card kpi"><span>{nome}</span><b style={{ fontSize: 24 }}>{valor}</b><small>{nota}</small></div>
        ))}
      </div>
      {erro && <p className="erro" role="alert" style={{ marginBottom: 16 }}>{erro}</p>}
      <div className="card fila">
        <div className="fh">
          <h2>Fila de chamados</h2>
          <div className="tabs" role="group" aria-label="Filtrar">
            {FILTROS.map((f) => (
              <button key={f.chave} type="button" className="tab" aria-pressed={filtro === f.chave} aria-selected={filtro === f.chave} onClick={() => setFiltro(f.chave)}>
                {f.nome}<span className="n">{chamados.filter((c) => noFiltro(f.chave, c, eu.id)).length}</span>
              </button>
            ))}
          </div>
        </div>
        <div className="row head"><span>Protocolo</span><span>Chamado</span><span>Sistema</span><span>Urgência</span><span>Prazo</span><span>Responsável</span></div>
        {!lista.length ? (
          <div className="empty">{chamados.length ? 'Nada neste filtro.' : 'Nenhum chamado ainda. Abra o primeiro na aba "Abrir chamado".'}</div>
        ) : lista.map((c) => {
          const sol = pessoa.get(c.solicitante_id);
          const resp = c.responsavel_id ? pessoa.get(c.responsavel_id) : undefined;
          const res = c.status === 'resolvido';
          const bloqueado = ocupado === c.id;
          const fim = res && c.resolvido_em ? new Date(c.resolvido_em).getTime() : agora;
          const idade = fim - new Date(c.criado_em).getTime();
          const { situacao } = situacaoPrazo(c, agora);
          return (
            <div className="row" key={c.id}>
              <span className="mono muted id" style={{ fontSize: 13 }}>{c.protocolo}</span>
              <div style={{ minWidth: 0 }}>
                <div className={`t${res ? ' res' : ''}`} title={c.descricao}>{titulo(c.descricao)}</div>
                <div className="sub">
                  {sol?.nome ?? '—'}{sol?.setor_id ? ` · ${setor.get(sol.setor_id)}` : ''}
                </div>
                {c.descricao.length > 90 && <div className="desc">{c.descricao}</div>}
                {(c.sistema_origem || c.contexto) && <OrigemHub c={c} nome={c.sistema_origem ? sistemaHub.get(c.sistema_origem) ?? c.sistema_origem : null} />}
                <MiniPrints caminhos={c.prints} onAmpliar={setAmpliado} />
              </div>
              <span className="sys">{sistema.get(c.sistema_id) ?? '—'}</span>
              <PilulaUrgencia u={c.urgencia} />
              <span className={`prazo ${situacao}`} title={`Assumir até ${fmt(c.prazo_assumir_em)} · resolver até ${fmt(c.prazo_em)}`}>
                {textoPrazo(c, agora)}
                <small>{res ? `resolvido em ${duracao(idade)}` : `aberto há ${duracao(idade)}`}</small>
              </span>
              <div className="who">
                {!resp ? (
                  <button className="mini go" type="button" disabled={bloqueado} onClick={() => executar('assumir', c.id)}>Assumir</button>
                ) : (
                  <>
                    <span className="av">{iniciais(resp.nome)}</span>
                    <div>
                      <div style={{ fontSize: 13, fontWeight: 500 }}>{resp.nome}</div>
                      <div className="sub" style={res ? { color: 'var(--ok)' } : undefined}>{res ? 'Resolvido' : 'Em andamento'}</div>
                    </div>
                    {res && <button className="mini" type="button" disabled={bloqueado} onClick={() => executar('reabrir', c.id)}>Reabrir</button>}
                    {!res && resp.id === eu.id && <button className="mini" type="button" disabled={bloqueado} onClick={() => executar('resolver', c.id)}>Resolver</button>}
                  </>
                )}
              </div>
            </div>
          );
        })}
      </div>
      {ampliado && <Ampliar src={ampliado} onFechar={() => setAmpliado(null)} />}
    </section>
  );
}
