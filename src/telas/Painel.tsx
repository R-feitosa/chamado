import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { agir, justificarAtraso, listarColaboracoes, MOTIVOS_REABERTURA, pedirAjuda, reabrir, responderAjuda, type Acao, type Colaboracao, type MotivoReabertura } from '../lib/api';
import { FILTROS, indicadores, noFiltro, ordenar, quemAbriu, type Filtro } from '../lib/fila';
import { duracao, inicioDoPeriodo, resolvidosNoPeriodo, tempoDaFila, temposMedios } from '../lib/analytics';
import { formatoPct, situacaoPrazo, taxaAssumidoNoPrazo, taxaNoPrazo, textoPrazo } from '../lib/sla';
import { hojePorExtenso, iniciais, mensagemErro, titulo } from '../lib/formato';
import type { Catalogo, Chamado, Pessoa } from '../lib/tipos';
import { MiniPrints } from '../componentes/MiniPrints';
import { PilulaUrgencia } from '../componentes/Urgencia';
import { Ampliar } from '../componentes/Ampliar';

interface Props { eu: Pessoa; catalogo: Catalogo; chamados: Chamado[]; onAcao?: () => void }

type Dialogo = { tipo: 'reabrir' | 'ajuda' | 'justificar'; c: Chamado } | null;

/** Diálogos do Painel: reabrir com motivo, pedir ajuda a um colega e justificar atraso. */
function Dialogos({ d, eu, devs, onFechar, onFeito }: { d: NonNullable<Dialogo>; eu: Pessoa; devs: Pessoa[]; onFechar: () => void; onFeito: () => void }) {
  const [motivo, setMotivo] = useState<MotivoReabertura | ''>('');
  const [texto, setTexto] = useState('');
  const [colega, setColega] = useState('');
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState('');
  useEffect(() => { const esc = (e: KeyboardEvent) => e.key === 'Escape' && onFechar(); window.addEventListener('keydown', esc); return () => window.removeEventListener('keydown', esc); }, [onFechar]);
  const pronto = d.tipo === 'reabrir' ? !!motivo && (motivo !== 'outro' || texto.trim().length >= 5) : d.tipo === 'ajuda' ? !!colega : texto.trim().length >= 5;
  async function enviar(e: FormEvent) {
    e.preventDefault();
    if (!pronto || enviando) return;
    setEnviando(true); setErro('');
    try {
      if (d.tipo === 'reabrir') await reabrir(d.c.id, motivo as MotivoReabertura, texto);
      else if (d.tipo === 'ajuda') await pedirAjuda(d.c.id, colega);
      else await justificarAtraso(d.c.id, texto);
      onFeito();
    } catch (err) { setErro(mensagemErro(err)); } finally { setEnviando(false); }
  }
  const titulos = { reabrir: 'Reabrir chamado', ajuda: 'Pedir ajuda a um colega', justificar: 'Justificar atraso' };
  return (
    <div className="dlg" role="dialog" aria-modal="true" aria-labelledby="dlg-t" onClick={(e) => e.target === e.currentTarget && onFechar()}>
      <form className="card" onSubmit={enviar}>
        <h2 id="dlg-t">{titulos[d.tipo]} <span className="mono muted" style={{ fontSize: 14 }}>{d.c.protocolo}</span></h2>
        {d.tipo === 'reabrir' && (
          <div className="opcoes" role="radiogroup" aria-label="Motivo">
            {MOTIVOS_REABERTURA.map((m) => (
              <label key={m.chave}><input type="radio" name="motivo" value={m.chave} checked={motivo === m.chave} onChange={() => setMotivo(m.chave)} />
                <span><b>{m.nome}</b><small>{m.ajuda}</small></span></label>
            ))}
          </div>
        )}
        {d.tipo === 'ajuda' && (
          <label className="grp"><span className="lbl">Quem vai ajudar?</span>
            <select className="field" value={colega} onChange={(e) => setColega(e.target.value)} required>
              <option value="">Escolha um colega</option>
              {devs.filter((p) => p.id !== eu.id).map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}
            </select>
            <small className="muted">O colega confirma no próprio painel. A ajuda conta quando o chamado for resolvido e validado.</small>
          </label>
        )}
        {(d.tipo !== 'ajuda') && (
          <label className="grp"><span className="lbl">{d.tipo === 'justificar' ? 'O que causou o atraso?' : `Detalhes${motivo === 'outro' ? ' (obrigatório)' : ' (opcional)'}`}</span>
            <textarea className="field" rows={3} maxLength={d.tipo === 'justificar' ? 500 : 300} value={texto} onChange={(e) => setTexto(e.target.value)}
              placeholder={d.tipo === 'justificar' ? 'Ex.: dependia do fornecedor; aguardando o solicitante.' : ''} />
            {d.tipo === 'justificar' && <small className="muted">Atraso justificado até a validação do chamado não gera penalidade.</small>}
          </label>
        )}
        {erro && <p className="erro" role="alert">{erro}</p>}
        <div className="acoes">
          <button type="button" className="btn sec" onClick={onFechar}>Cancelar</button>
          <button type="submit" className="btn pri" disabled={!pronto || enviando}>{enviando ? 'Enviando…' : d.tipo === 'reabrir' ? 'Reabrir' : d.tipo === 'ajuda' ? 'Pedir ajuda' : 'Salvar justificativa'}</button>
        </div>
      </form>
    </div>
  );
}

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

export function Painel({ eu, catalogo, chamados, onAcao }: Props) {
  const [filtro, setFiltro] = useState<Filtro>('abertos');
  const [ocupado, setOcupado] = useState<string | null>(null);
  const [erro, setErro] = useState('');
  const [ampliado, setAmpliado] = useState<string | null>(null);
  const [dialogo, setDialogo] = useState<Dialogo>(null);
  const [colabs, setColabs] = useState<Colaboracao[]>([]);
  const carregarColabs = useCallback(() => { listarColaboracoes().then(setColabs).catch(() => undefined); }, []);
  useEffect(() => { carregarColabs(); }, [carregarColabs, chamados]);
  useEffect(() => { const t = setInterval(carregarColabs, 30_000); return () => clearInterval(t); }, [carregarColabs]);
  const devs = catalogo.pessoas.filter((p) => p.papel === 'dev' && p.ativo);
  const pedidosParaMim = colabs.filter((x) => x.ajudante_id === eu.id && x.status === 'pedida');
  async function responder(id: number, aceitar: boolean) {
    setErro('');
    try { await responderAjuda(id, aceitar); carregarColabs(); onAcao?.(); } catch (e) { setErro(mensagemErro(e)); }
  }

  const pessoa = useMemo(() => new Map(catalogo.pessoas.map((p) => [p.id, p])), [catalogo]);
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
    try { await agir(acao, id); onAcao?.(); } catch (e) { setErro(mensagemErro(e)); } finally { setOcupado(null); }
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
      {pedidosParaMim.map((x) => {
        const c = chamados.find((y) => y.id === x.chamado_id);
        return (
          <div key={x.id} className="card ajuda-banner" role="status">
            <span><b>{pessoa.get(x.responsavel_id)?.nome ?? 'Um colega'}</b> pediu sua ajuda no <span className="mono">{c?.protocolo ?? 'chamado'}</span>{c ? ` · ${titulo(c.descricao).slice(0, 60)}` : ''}</span>
            <span className="acoes"><button className="mini" type="button" onClick={() => void responder(x.id, false)}>Recusar</button>
              <button className="mini go" type="button" onClick={() => void responder(x.id, true)}>Vou ajudar</button></span>
          </div>
        );
      })}
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
          const sol = quemAbriu(c, pessoa, catalogo.setores);
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
                  {sol.nome}{sol.cargo ? ` · ${sol.cargo}` : ''}{sol.setor ? ` · ${sol.setor}` : ''}
                </div>
                {colabs.some((x) => x.chamado_id === c.id && x.status !== 'recusada') && (
                  <div className="sub">Com ajuda de {colabs.filter((x) => x.chamado_id === c.id && x.status !== 'recusada')
                    .map((x) => `${pessoa.get(x.ajudante_id)?.nome.split(' ')[0] ?? '—'}${x.status === 'pedida' ? ' (aguardando)' : ''}`).join(', ')}</div>
                )}
                {c.justificativa_atraso && <div className="sub" title={c.justificativa_atraso}>Atraso justificado</div>}
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
                    {res && <button className="mini" type="button" disabled={bloqueado} onClick={() => setDialogo({ tipo: 'reabrir', c })}>Reabrir</button>}
                    {!res && resp.id === eu.id && <button className="mini" type="button" disabled={bloqueado} onClick={() => executar('resolver', c.id)}>Resolver</button>}
                    {!res && resp.id === eu.id && <button className="mini" type="button" title="Pedir ajuda a um colega" aria-label="Pedir ajuda" onClick={() => setDialogo({ tipo: 'ajuda', c })}>Ajuda</button>}
                    {resp.id === eu.id && !c.justificativa_atraso && (c.resolvido_em ? new Date(c.resolvido_em).getTime() : agora) > new Date(c.prazo_em).getTime() && (
                      <button className="mini" type="button" title="Justificar o atraso evita a penalidade" onClick={() => setDialogo({ tipo: 'justificar', c })}>Justificar</button>
                    )}
                  </>
                )}
              </div>
            </div>
          );
        })}
      </div>
      {ampliado && <Ampliar src={ampliado} onFechar={() => setAmpliado(null)} />}
      {dialogo && <Dialogos d={dialogo} eu={eu} devs={devs} onFechar={() => setDialogo(null)} onFeito={() => { setDialogo(null); carregarColabs(); onAcao?.(); }} />}
    </section>
  );
}
