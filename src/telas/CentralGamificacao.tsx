import { useCallback, useEffect, useState, type ReactNode } from 'react';
import {
  adminConfig, adminConquista, adminMissao, adminMultiplicador, adminNiveis, adminPainel, adminRecompensa, adminRegra, adminReprocessar,
  adminSuspeita, adminTemporada, type Painel, type Regra,
} from '../lib/apiGam';
import { RARIDADES, type Raridade } from '../lib/gamificacao';
import { mensagemErro, quando } from '../lib/formato';
import { Medalha } from '../componentes/gam/Medalha';

type Aba = 'geral' | 'regras' | 'score' | 'niveis' | 'conquistas' | 'missoes' | 'temporadas' | 'recompensas' | 'revisao' | 'auditoria';
const ABAS: { chave: Aba; nome: string }[] = [
  { chave: 'geral', nome: 'Visão geral' }, { chave: 'regras', nome: 'Regras de XP' }, { chave: 'score', nome: 'Score e limites' },
  { chave: 'niveis', nome: 'Níveis' }, { chave: 'conquistas', nome: 'Conquistas' }, { chave: 'missoes', nome: 'Missões e desafios' },
  { chave: 'temporadas', nome: 'Temporadas' }, { chave: 'recompensas', nome: 'Recompensas' }, { chave: 'revisao', nome: 'Revisão' },
  { chave: 'auditoria', nome: 'Auditoria' },
];
const ROTULO_CONFIG: Record<string, string> = {
  horas_pendente: 'Horas em validação', janela_reabertura_dias: 'Janela de reabertura (dias)', teto_diario_resolucao: 'Teto diário de XP de resolução',
  multiplicador_max: 'Teto do multiplicador', resposta_rapida_fracao: 'Fração do prazo para resposta rápida', madrugador_horas: 'Horas de "Madrugador"',
  score_k: 'Suavização (k)', ranking_minimo: 'Mínimo de resolvidos no ranking', equipe_minimo: 'Mínimo para missão de equipe',
  sequencia_semana_minimo: 'Mínimo semanal para sequência de SLA', niveis_extra_fator: 'Fator dos níveis extras',
};

/** Central de Gamificação: só o gestor. Tudo que muda aqui fica na auditoria. */
export function CentralGamificacao() {
  const [aba, setAba] = useState<Aba>('geral');
  const [p, setP] = useState<Painel | null>(null);
  const [erro, setErro] = useState('');
  const [aviso, setAviso] = useState('');

  const carregar = useCallback(async () => {
    try { setP(await adminPainel()); setErro(''); } catch (e) { setErro(mensagemErro(e)); }
  }, []);
  useEffect(() => { void carregar(); }, [carregar]);

  async function salvar(acao: () => Promise<unknown>, ok = 'Salvo.') {
    setErro(''); setAviso('');
    try { await acao(); setAviso(ok); await carregar(); } catch (e) { setErro(mensagemErro(e)); }
  }

  if (!p) return erro ? <p className="erro" role="alert">{erro}</p> : <div className="carregando">Carregando…</div>;
  const ativo = p.config.ativo?.valor === true;
  const abertas = p.suspeitas.filter((s) => s.status === 'aberta').length;

  return (
    <section>
      <div className="ph"><div><div className="sub">Configuração da gamificação · alterações auditadas</div><h1>Central de Gamificação</h1></div></div>
      <nav className="central-nav" aria-label="Seções">
        {ABAS.map((a) => (
          <button key={a.chave} type="button" className="tab" aria-pressed={aba === a.chave} aria-selected={aba === a.chave} onClick={() => setAba(a.chave)}>
            {a.nome}{a.chave === 'revisao' && abertas ? <span className="n">{abertas}</span> : null}
          </button>
        ))}
      </nav>
      {erro && <p className="erro" role="alert" style={{ marginBottom: 12 }}>{erro}</p>}
      {aviso && <p className="banner" role="status">{aviso}</p>}

      {aba === 'geral' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div className="card liga">
            <input type="checkbox" className="chave" id="chave" checked={ativo} aria-describedby="chave-d"
              onChange={(e) => void salvar(() => adminConfig('ativo', e.target.checked), e.target.checked ? 'Gamificação ligada.' : 'Gamificação desligada.')} />
            <label htmlFor="chave"><b>Gamificação {ativo ? 'ligada' : 'desligada'}</b></label>
            <span id="chave-d" className="muted" style={{ fontSize: 13 }}>
              {ativo ? `Valendo desde ${p.config.ligada_em?.valor ? new Date(String(p.config.ligada_em.valor)).toLocaleString('pt-BR') : '—'}. Só eventos depois disso contam.`
                : 'Desligada: o time não vê a gamificação e os eventos são ignorados. Ao ligar, tudo começa do zero.'}
            </span>
          </div>
          <div className="kpis">
            {[['Fila pendente', p.fila.pendentes], ['Eventos com erro', p.fila.erros], ['Processados', p.fila.processados], ['XP em validação', p.xp_pendente]].map(([k, v]) => (
              <div key={String(k)} className="card kpi"><span>{k}</span><b>{Number(v).toLocaleString('pt-BR')}</b></div>
            ))}
          </div>
          <div className="card gbloco">
            <h2>Motor <small>último processamento: {p.fila.ultimo ? quando(p.fila.ultimo) : '—'}</small></h2>
            {(p.fila.ultimos_erros ?? []).map((e) => <p key={e.id} className="erro" style={{ margin: 0 }}>#{e.id} {e.tipo}: {e.erro}</p>)}
            <div><button type="button" className="btn sec" onClick={() => void salvar(adminReprocessar, 'Fila reprocessada.')}>Reprocessar eventos com erro</button></div>
          </div>
        </div>
      )}

      {aba === 'regras' && (
        <Tabela cab={['Regra', 'Evento', 'XP', 'Limite por chamado', 'Limite diário', 'Status', '']}>
          {p.regras.map((r) => <LinhaRegra key={r.codigo} r={r} onSalvar={(n) => void salvar(() => adminRegra(n))} />)}
          {p.multiplicadores.map((m) => (
            <tr key={`m${m.urgencia}`}>
              <td><b>Multiplicador · {m.rotulo}</b><small>Urgência {m.urgencia}: aplicado ao XP de resolução (teto em Score e limites)</small></td>
              <td>ticket.resolved</td>
              <td colSpan={4}><EditNum valor={m.fator} passo={0.1} onSalvar={(v) => void salvar(() => adminMultiplicador(m.urgencia, v))} sufixo="×" /></td><td />
            </tr>
          ))}
        </Tabela>
      )}

      {aba === 'score' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div className="card gbloco">
            <h2>Pesos do Performance Score</h2>
            <JsonEdit valor={p.config.score_pesos?.valor} onSalvar={(v) => void salvar(() => adminConfig('score_pesos', v))} />
            <small className="muted">Score = Σ peso × componente ÷ Σ pesos × 100. Componentes: qualidade, sla, satisfacao, produtividade, colaboracao.</small>
          </div>
          <div className="card gbloco">
            <h2>Limites e validação</h2>
            <div className="forms">
              {Object.entries(p.config).filter(([k, c]) => typeof c.valor === 'number' && ROTULO_CONFIG[k]).map(([k, c]) => (
                <label key={k} title={c.descricao}>{ROTULO_CONFIG[k]}
                  <EditNum valor={c.valor as number} passo={k.includes('fator') || k.includes('max') || k.includes('fracao') ? 0.05 : 1} onSalvar={(v) => void salvar(() => adminConfig(k, v))} />
                </label>
              ))}
            </div>
          </div>
          {(['retorno_decrescente', 'expediente', 'suspeita', 'temporada_xp'] as const).map((k) => (
            <div key={k} className="card gbloco">
              <h2>{k === 'retorno_decrescente' ? 'Retorno decrescente' : k === 'expediente' ? 'Expediente' : k === 'suspeita' ? 'Antiabuso (limites de suspeita)' : 'XP do pódio da temporada'}</h2>
              <small className="muted">{p.config[k]?.descricao}</small>
              <JsonEdit valor={p.config[k]?.valor} onSalvar={(v) => void salvar(() => adminConfig(k, v))} />
            </div>
          ))}
        </div>
      )}

      {aba === 'niveis' && <Niveis p={p} onSalvar={(n) => void salvar(() => adminNiveis(n))} />}

      {aba === 'conquistas' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div className="medalhas">
            {p.conquistas.map((c) => (
              <div key={c.codigo} className={`mcard${c.ativo ? '' : ' bloq'}`}>
                <Medalha icone={c.icone} raridade={c.raridade as Raridade} rotulo={c.nome} />
                <b>{c.nome}</b>
                <small>{c.metrica ?? 'por missão/temporada'} · {c.tiers.map((t) => `${t.nome ?? ''} ${t.limite} (+${t.xp})`.trim()).join(' · ')}</small>
                <small>{c.tiers.reduce((s, t) => s + t.desbloqueios, 0)} desbloqueios{c.ativo ? '' : ' · desativada'}</small>
              </div>
            ))}
          </div>
          <EditorJson titulo="Criar ou alterar conquista (pelo código)" exemplo={p.conquistas[0]} onSalvar={(v) => void salvar(() => adminConquista(v))}
            ajuda='Campos: codigo, nome, descricao, icone, raridade (comum…lendaria), metrica, ativo, ordem, tiers [{tier, nome (Bronze…Diamante), limite, xp, raridade, recompensa}].' />
        </div>
      )}

      {aba === 'missoes' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <Tabela cab={['Missão', 'Período', 'Alvo', 'Meta', 'XP', 'Status']}>
            {p.missoes.map((m) => (
              <tr key={m.codigo}><td><b>{m.nome}</b><small>{m.codigo} · {m.metrica}{m.especial ? ' · especial' : ''}{m.conquista ? ` · medalha ${m.conquista}` : ''}</small></td>
                <td>{m.periodo}</td><td>{m.alvo}</td><td>{m.meta}</td><td>{m.xp}</td><td>{m.ativo ? 'Ativa' : 'Desativada'}</td></tr>
            ))}
          </Tabela>
          <EditorJson titulo="Criar ou alterar missão (pelo código)" exemplo={p.missoes[0]} onSalvar={(v) => void salvar(() => adminMissao(v))}
            ajuda="Campos: codigo, nome, descricao, periodo (dia|semana|mes), alvo (individual|equipe), metrica (resolvidos, resolvidos_sla, resolvidos_sem_reabertura, avaliados_ge4, ajudas; equipe: sla_equipe_pct, satisfacao_equipe_pct), meta, xp, especial, inicio, fim, ativo, conquista, recompensa." />
        </div>
      )}

      {aba === 'temporadas' && <Temporadas p={p} onSalvar={(t, ok) => void salvar(() => adminTemporada(t), ok)} />}

      {aba === 'recompensas' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <Tabela cab={['Recompensa', 'Tipo', 'Raridade', 'Status']}>
            {p.recompensas.map((r) => <tr key={r.codigo}><td><b>{r.nome}</b><small>{r.codigo} · {r.descricao}</small></td><td>{r.tipo}</td><td>{RARIDADES[r.raridade as Raridade]}</td><td>{r.ativo ? 'Ativa' : 'Desativada'}</td></tr>)}
          </Tabela>
          <EditorJson titulo="Criar ou alterar recompensa (pelo código)" exemplo={p.recompensas[0]} onSalvar={(v) => void salvar(() => adminRecompensa(v))}
            ajuda="Recompensas são simbólicas: titulo, moldura, tema, icone ou destaque." />
        </div>
      )}

      {aba === 'revisao' && <Revisao p={p} onDecidir={(id, aceitar, nota) => void salvar(() => adminSuspeita(id, aceitar, nota), aceitar ? 'XP liberado.' : 'XP estornado.')} />}

      {aba === 'auditoria' && (
        <Tabela cab={['Quando', 'Quem', 'Ação', 'Alvo', 'Depois']}>
          {p.auditoria.map((a, i) => <tr key={i}><td>{quando(a.criado_em)}</td><td>{a.autor ?? '—'}</td><td>{a.acao}</td><td className="mono">{a.alvo}</td>
            <td className="mono" style={{ fontSize: 12, maxWidth: 360, overflowWrap: 'anywhere' }}>{JSON.stringify(a.depois)}</td></tr>)}
        </Tabela>
      )}
    </section>
  );
}

function Tabela({ cab, children }: { cab: string[]; children: ReactNode }) {
  return <div className="card scroll-x"><table className="tbl"><thead><tr>{cab.map((c, i) => <th key={i}>{c}</th>)}</tr></thead><tbody>{children}</tbody></table></div>;
}

function EditNum({ valor, passo = 1, sufixo, onSalvar }: { valor: number; passo?: number; sufixo?: string; onSalvar: (v: number) => void }) {
  const [v, setV] = useState(String(valor));
  useEffect(() => setV(String(valor)), [valor]);
  const mudou = Number(v) !== valor && v.trim() !== '' && !Number.isNaN(Number(v));
  return (
    <span style={{ display: 'inline-flex', gap: 6, alignItems: 'center' }}>
      <input className="field" type="number" step={passo} value={v} onChange={(e) => setV(e.target.value)} />{sufixo}
      {mudou && <button type="button" className="mini go" onClick={() => onSalvar(Number(v))}>Salvar</button>}
    </span>
  );
}

function LinhaRegra({ r, onSalvar }: { r: Regra; onSalvar: (n: Pick<Regra, 'codigo' | 'xp' | 'ativo' | 'limite_por_chamado' | 'limite_diario'>) => void }) {
  const [n, setN] = useState(r);
  useEffect(() => setN(r), [r]);
  const mudou = n.xp !== r.xp || n.ativo !== r.ativo || n.limite_por_chamado !== r.limite_por_chamado || n.limite_diario !== r.limite_diario;
  return (
    <tr>
      <td><b>{r.nome}</b><small>{r.descricao}{r.usa_multiplicador ? ' · usa multiplicador' : ''}</small></td>
      <td className="mono" style={{ fontSize: 12 }}>{r.evento}</td>
      <td><input className="field" type="number" value={n.xp} aria-label={`XP de ${r.nome}`} onChange={(e) => setN({ ...n, xp: Number(e.target.value) })} /></td>
      <td><input className="field" type="number" min={1} max={10} value={n.limite_por_chamado} aria-label="Limite por chamado" onChange={(e) => setN({ ...n, limite_por_chamado: Number(e.target.value) })} /></td>
      <td><input className="field" type="number" min={1} placeholder="sem limite" value={n.limite_diario ?? ''} aria-label="Limite diário"
        onChange={(e) => setN({ ...n, limite_diario: e.target.value ? Number(e.target.value) : null })} /></td>
      <td><label style={{ display: 'inline-flex', gap: 6, alignItems: 'center' }}><input type="checkbox" checked={n.ativo} onChange={(e) => setN({ ...n, ativo: e.target.checked })} />{n.ativo ? 'ON' : 'OFF'}</label></td>
      <td>{mudou && <button type="button" className="mini go" onClick={() => onSalvar(n)}>Salvar</button>}</td>
    </tr>
  );
}

function JsonEdit({ valor, onSalvar }: { valor: unknown; onSalvar: (v: unknown) => void }) {
  const [t, setT] = useState(JSON.stringify(valor, null, 2));
  const [erro, setErro] = useState('');
  useEffect(() => setT(JSON.stringify(valor, null, 2)), [valor]);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      <textarea className="field json" value={t} onChange={(e) => setT(e.target.value)} aria-label="Valor (JSON)" />
      {erro && <p className="erro">{erro}</p>}
      <div><button type="button" className="mini go" onClick={() => { try { const v = JSON.parse(t); setErro(''); onSalvar(v); } catch { setErro('JSON inválido.'); } }}>Salvar</button></div>
    </div>
  );
}

function EditorJson({ titulo, exemplo, ajuda, onSalvar }: { titulo: string; exemplo: unknown; ajuda: string; onSalvar: (v: Record<string, unknown>) => void }) {
  const limpo = exemplo && typeof exemplo === 'object' ? Object.fromEntries(Object.entries(exemplo as Record<string, unknown>)
    .filter(([k]) => !['id', 'conquista_tier_id', 'recompensa_id', 'desbloqueios', 'conquista_id'].includes(k))
    .map(([k, v]) => [k, Array.isArray(v) ? v.map((x) => (x && typeof x === 'object' ? Object.fromEntries(Object.entries(x).filter(([kk]) => !['id', 'conquista_id', 'recompensa_id', 'desbloqueios'].includes(kk))) : x)) : v])) : {};
  return (
    <div className="card gbloco">
      <h2>{titulo}</h2>
      <small className="muted">{ajuda} O exemplo abaixo é um item existente: mude o código para criar outro.</small>
      <JsonEdit valor={limpo} onSalvar={(v) => onSalvar(v as Record<string, unknown>)} />
    </div>
  );
}

function Niveis({ p, onSalvar }: { p: Painel; onSalvar: (n: Painel['niveis']) => void }) {
  const [lista, setLista] = useState(p.niveis);
  useEffect(() => setLista(p.niveis), [p.niveis]);
  const mudar = (i: number, campo: 'nome' | 'xp_minimo', v: string) =>
    setLista(lista.map((n, j) => (j === i ? { ...n, [campo]: campo === 'xp_minimo' ? Number(v) : v } : n)));
  return (
    <div className="card gbloco">
      <h2>Níveis <small>XP mínimo crescente; níveis não são removidos; acima do último, cada nível exige o intervalo anterior × fator</small></h2>
      <table className="tbl"><thead><tr><th>Nível</th><th>Nome</th><th>XP mínimo</th></tr></thead>
        <tbody>{lista.map((n, i) => (
          <tr key={n.nivel}><td className="mono">{n.nivel}</td>
            <td><input className="field" value={n.nome} aria-label={`Nome do nível ${n.nivel}`} onChange={(e) => mudar(i, 'nome', e.target.value)} /></td>
            <td><input className="field" type="number" value={n.xp_minimo} disabled={n.nivel === 1} aria-label={`XP do nível ${n.nivel}`} onChange={(e) => mudar(i, 'xp_minimo', e.target.value)} /></td></tr>
        ))}</tbody></table>
      <div className="acoes" style={{ justifyContent: 'flex-start' }}>
        <button type="button" className="mini" onClick={() => setLista([...lista, { nivel: lista.length + 1, nome: `Nível ${lista.length + 1}`, xp_minimo: (lista[lista.length - 1]?.xp_minimo ?? 0) * 2 || 500 }])}>+ Nível</button>
        <button type="button" className="mini go" onClick={() => onSalvar(lista)}>Salvar níveis</button>
      </div>
    </div>
  );
}

function Temporadas({ p, onSalvar }: { p: Painel; onSalvar: (t: Record<string, unknown>, ok: string) => void }) {
  const [nova, setNova] = useState({ nome: '', inicio: '', fim: '' });
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      <Tabela cab={['Temporada', 'Início', 'Fim', 'Situação', '']}>
        {p.temporadas.map((t) => (
          <tr key={t.id}><td><b>{t.nome}</b></td><td>{new Date(`${t.inicio}T12:00:00`).toLocaleDateString('pt-BR')}</td><td>{new Date(`${t.fim}T12:00:00`).toLocaleDateString('pt-BR')}</td>
            <td>{t.status === 'ativa' ? 'Ativa' : t.status === 'futura' ? 'Futura' : `Encerrada ${t.encerrada_em ? quando(t.encerrada_em) : ''}`}</td>
            <td>{t.status === 'ativa' && <button type="button" className="mini" onClick={() => {
              if (window.confirm(`Encerrar "${t.nome}" agora? O ranking será congelado, o pódio recebe as recompensas e a próxima temporada começa.`)) onSalvar({ acao: 'encerrar', id: t.id }, 'Temporada encerrada.');
            }}>Encerrar agora</button>}</td></tr>
        ))}
      </Tabela>
      <div className="card gbloco">
        <h2>Nova temporada <small>encerra sozinha no fim (depois da validação) e a próxima abre</small></h2>
        <div className="forms">
          <label>Nome<input className="field" value={nova.nome} onChange={(e) => setNova({ ...nova, nome: e.target.value })} placeholder="Temporada 2 · T1 2027" /></label>
          <label>Início<input className="field" type="date" value={nova.inicio} onChange={(e) => setNova({ ...nova, inicio: e.target.value })} /></label>
          <label>Fim<input className="field" type="date" value={nova.fim} onChange={(e) => setNova({ ...nova, fim: e.target.value })} /></label>
        </div>
        <div><button type="button" className="mini go" disabled={!nova.nome || !nova.inicio || !nova.fim} onClick={() => onSalvar(nova, 'Temporada criada.')}>Criar</button></div>
      </div>
    </div>
  );
}

function Revisao({ p, onDecidir }: { p: Painel; onDecidir: (id: number, aceitar: boolean, nota: string) => void }) {
  const [notas, setNotas] = useState<Record<number, string>>({});
  if (!p.suspeitas.length) return <p className="muted">Nenhum evento suspeito.</p>;
  return (
    <Tabela cab={['Suspeita', 'Técnico', 'Chamado', 'XP retido', 'Situação', 'Decisão']}>
      {p.suspeitas.map((s) => (
        <tr key={s.id}>
          <td><b>{s.regra.replace(/_/g, ' ')}</b><small>{s.descricao} · {quando(s.criada_em)}</small></td>
          <td>{s.pessoa}</td><td className="mono">{s.protocolo ?? '—'}</td><td>{s.xp_retido}</td>
          <td>{s.status === 'aberta' ? 'Aberta' : s.status === 'aceita' ? 'Legítimo' : 'Rejeitado'}{s.nota && <small>{s.nota}</small>}</td>
          <td>{s.status === 'aberta' && (
            <span style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
              <input className="field" placeholder="Nota (opcional)" value={notas[s.id] ?? ''} onChange={(e) => setNotas({ ...notas, [s.id]: e.target.value })} style={{ minWidth: 140 }} />
              <button type="button" className="mini" onClick={() => onDecidir(s.id, false, notas[s.id] ?? '')}>Rejeitar (estorna)</button>
              <button type="button" className="mini go" onClick={() => onDecidir(s.id, true, notas[s.id] ?? '')}>Legítimo (libera)</button>
            </span>
          )}</td>
        </tr>
      ))}
    </Tabela>
  );
}
