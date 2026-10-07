import { useEffect, useState } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import { escolherVisual, jornada as lerJornada, ranking as lerRanking } from '../lib/apiGam';
import {
  conquistasProximas, desbloqueadas, fmtXp, PERIODO_MISSAO, pct, proximoTier, raridadeAtual, RARIDADES, SEQUENCIAS, sinalXp,
  STATUS_XP, terminaEm, valorMissao, type Jornada as Dados, type LinhaRanking,
} from '../lib/gamificacao';
import { iniciais, mensagemErro, quando } from '../lib/formato';
import { Barra } from '../componentes/gam/Barra';
import { Medalha, SeloRaridade } from '../componentes/gam/Medalha';
import { IconeGam } from '../componentes/gam/IconeGam';

/** Avatar com iniciais e moldura conquistada (texto alternativo diz qual). */
export function Avatar({ nome, moldura, grande }: { nome: string; moldura?: string | null; grande?: boolean }) {
  return <span className={`avg${grande ? ' grande' : ''}${moldura ? ` m-${moldura}` : ''}`} aria-hidden="true">{iniciais(nome)}</span>;
}

function Cards({ d }: { d: Dados }) {
  const reduzir = useReducedMotion();
  const p = d.perfil!; const n = p.nivel;
  const seqMax = Math.max(0, ...(d.sequencias ?? []).filter((s) => s.tipo !== 'semanas_sla').map((s) => s.atual));
  const itens = [
    { k: 'XP', v: fmtXp(p.xp), s: p.xp_pendente ? `${fmtXp(p.xp_pendente)} ainda em validação` : 'tudo confirmado',
      t: 'O XP conta na hora. A parte em validação é estornada se o chamado for reaberto nas primeiras 72 h.' },
    { k: 'Ranking', v: d.ranking?.posicao && d.ranking.classificado ? `#${d.ranking.posicao}` : '—',
      s: d.ranking?.classificado ? `de ${d.ranking.total} na temporada` : `em formação (mín. ${d.ranking?.minimo ?? 5} resolvidos)`, t: 'Posição pelo Performance Score da temporada.' },
    { k: 'Performance', v: d.estatisticas ? Math.round(d.estatisticas.score).toString() : '—', s: 'score de 0 a 100', t: 'Qualidade, SLA, satisfação, produtividade e colaboração.' },
    { k: 'Sequência', v: seqMax ? `🔥 ${seqMax}` : '0', s: 'melhor sequência atual', t: 'Chamados seguidos dentro do SLA, sem reabertura ou com 5 estrelas.' },
  ];
  return (
    <div className="gcards">
      <div className="card gcard gnivel" title={`Nível ${n.nivel}: ${n.nome}`}>
        <span>Nível</span>
        <motion.b key={n.nivel} initial={reduzir ? false : { scale: 0.9, opacity: 0 }} animate={{ scale: 1, opacity: 1 }}>{n.nivel} <em>{n.nome}</em></motion.b>
        <Barra valor={n.xp - n.xp_nivel} max={n.xp_proximo - n.xp_nivel} rotulo={`Progresso para o nível ${n.nivel + 1}`} />
        <small className="mono">{fmtXp(n.xp)} / {fmtXp(n.xp_proximo)} XP · faltam {fmtXp(n.faltam)} para o nível {n.nivel + 1}</small>
      </div>
      {itens.map((i) => (
        <div key={i.k} className="card gcard" title={i.t}><span>{i.k}</span><b>{i.v}</b><small>{i.s}</small></div>
      ))}
    </div>
  );
}

function Missoes({ d }: { d: Dados }) {
  const lista = d.missoes ?? [];
  if (!lista.length) return null;
  return (
    <div className="card gbloco">
      <h2>Missões ativas <small>avaliadas ao fim do período, depois da validação</small></h2>
      {lista.map((m) => {
        const feito = m.valor >= m.meta;
        return (
          <div key={m.codigo} className={`missao${m.especial ? ' especial' : ''}${m.alvo === 'equipe' ? ' equipe' : ''}`}>
            <div className="mt">
              <div>
                <b>{m.alvo === 'equipe' ? 'Missão da equipe · ' : ''}{m.nome}</b>
                <small>{PERIODO_MISSAO[m.periodo]}{m.especial ? ' · especial' : ''} · {m.descricao}</small>
              </div>
              <span className="xpb" title="Recompensa">{m.xp ? sinalXp(m.xp) : 'Medalha'}</span>
            </div>
            <Barra valor={m.valor} max={m.meta} rotulo={`Progresso da missão ${m.nome}`} tom={feito ? 'ok' : m.especial ? 'epic' : 'accent'} />
            <div className="mv">
              <span>{valorMissao(m)}{feito ? ' · meta atingida, aguardando validação' : ''}</span>
              <span>termina em {terminaEm(m.termina_em)}{m.concluidas ? ` · concluída ${m.concluidas}×` : ''}</span>
            </div>
          </div>
        );
      })}
    </div>
  );
}

function Proximas({ d }: { d: Dados }) {
  const lista = conquistasProximas(d.conquistas ?? [], 3);
  if (!lista.length) return null;
  return (
    <div className="card gbloco">
      <h2>Conquistas próximas</h2>
      {lista.map(({ conquista: c, tier, faltam }) => (
        <div key={c.codigo} className="cq">
          <Medalha icone={c.icone} raridade={tier.raridade} bloqueada rotulo={c.nome} />
          <div>
            <b>{c.nome}{tier.nome ? ` · ${tier.nome}` : ''}</b>
            <Barra valor={c.valor} max={tier.limite} rotulo={`Progresso de ${c.nome}`} fina />
            <small className="mono">{c.valor} / {tier.limite} · {faltam} restante{faltam === 1 ? '' : 's'}{tier.xp ? ` · ${sinalXp(tier.xp)}` : ''}</small>
          </div>
        </div>
      ))}
    </div>
  );
}

function Sequencias({ d }: { d: Dados }) {
  const seqs = d.sequencias ?? [];
  const tipos = Object.keys(SEQUENCIAS) as (keyof typeof SEQUENCIAS)[];
  return (
    <div className="card gbloco">
      <h2>Sequências <small>consistência e qualidade, nunca presença</small></h2>
      <div className="seqs">
        {tipos.map((t) => {
          const s = seqs.find((x) => x.tipo === t);
          return (
            <div key={t} className="seq" title={`${SEQUENCIAS[t].nome}: ${s?.atual ?? 0} ${SEQUENCIAS[t].unidade}. Recorde: ${s?.recorde ?? 0}.`}>
              <b>{(s?.atual ?? 0) > 0 && <IconeGam nome="chama" tamanho={18} />}{s?.atual ?? 0}</b>
              <small>{SEQUENCIAS[t].nome} · recorde {s?.recorde ?? 0}</small>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function RankingMini({ linhas, onRanking, onPerfil }: { linhas: LinhaRanking[]; onRanking?: () => void; onPerfil?: (id: string) => void }) {
  return (
    <div className="card gbloco">
      <h2>Ranking da temporada {onRanking && <button className="mini" type="button" onClick={onRanking}>Ver completo</button>}</h2>
      <div>
        {linhas.slice(0, 5).map((l) => (
          <div key={l.pessoa_id} className={`cq${l.eu ? ' voce' : ''}`} style={{ padding: '6px 0' }}>
            <span className="mono" style={{ width: 22, fontWeight: 600 }}>{l.classificado ? l.posicao : '–'}</span>
            <Avatar nome={l.nome} moldura={l.moldura} />
            <div>
              <b>{onPerfil ? <button type="button" className="sair" style={{ padding: 0, color: 'inherit', fontWeight: 600 }} onClick={() => onPerfil(l.pessoa_id)}>{l.eu ? 'Você' : l.nome}</button> : l.nome}</b>
              <small>{l.score !== null ? `Score ${Math.round(l.score)}` : '—'} · {fmtXp(l.xp)} XP · SLA {pct(l.sla)}</small>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function Medalhas({ d }: { d: Dados }) {
  const lista = d.conquistas ?? [];
  return (
    <div className="card gbloco">
      <h2>Medalhas <small>{desbloqueadas(lista).length} desbloqueadas</small></h2>
      <div className="medalhas">
        {lista.map((c) => {
          const prox = proximoTier(c);
          const algum = c.tiers.some((t) => t.desbloqueada_em);
          const feitos = c.tiers.filter((t) => t.desbloqueada_em);
          const r = raridadeAtual(c);
          return (
            <div key={c.codigo} className={`mcard${algum ? '' : ' bloq'}`}>
              <Medalha icone={c.icone} raridade={r} bloqueada={!algum} rotulo={c.nome} tamanho={52} />
              <b>{c.nome}{feitos.length && feitos[feitos.length - 1].nome ? ` · ${feitos[feitos.length - 1].nome}` : ''}</b>
              <SeloRaridade r={r} />
              <small>{c.descricao}</small>
              {prox && c.metrica && (
                <>
                  <Barra valor={c.valor} max={prox.tier.limite} rotulo={`Progresso de ${c.nome}`} fina />
                  <small className="mono">{c.valor} / {prox.tier.limite}{prox.tier.nome ? ` · ${prox.tier.nome}` : ''}</small>
                </>
              )}
              {!prox && <small>Completa{feitos[0]?.desbloqueada_em ? ` · ${new Date(feitos[feitos.length - 1].desbloqueada_em!).toLocaleDateString('pt-BR')}` : ''}</small>}
            </div>
          );
        })}
      </div>
    </div>
  );
}

function Feed({ d, onLer }: { d: Dados; onLer?: () => void }) {
  const feed = d.feed ?? [];
  useEffect(() => { if (onLer && d.nao_lidas) { const t = setTimeout(onLer, 2500); return () => clearTimeout(t); } }, [d.nao_lidas, onLer]);
  return (
    <div className="card gbloco feed">
      <h2>Atividades {d.nao_lidas ? <small>{d.nao_lidas} nova{d.nao_lidas > 1 ? 's' : ''}</small> : null}</h2>
      {!feed.length ? <p className="muted" style={{ margin: 0 }}>Nada ainda. Resolva chamados com qualidade e no prazo.</p> : (
        <ul>
          {feed.slice(0, 12).map((n) => (
            <li key={n.id}>
              <span className={`fi t-${n.tipo}`}><IconeGam nome={n.tipo === 'conquista' ? 'trofeu' : n.tipo === 'nivel' ? 'nivel' : n.tipo === 'missao' ? 'missao' : n.tipo === 'revisao' ? 'revisao' : 'estrela'} tamanho={16} /></span>
              <div className="fc">
                <b>{n.titulo}</b>
                <small>{n.detalhe ? `${n.detalhe} · ` : ''}{quando(n.criada_em)}</small>
              </div>
              {n.xp ? <span className={`xpb${n.xp < 0 ? ' neg' : ''}`}>{sinalXp(n.xp)}</span> : null}
              {!n.lida && <span className="nova" title="Nova" aria-label="Nova" />}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function Historico({ d }: { d: Dados }) {
  const h = d.historico ?? [];
  if (!h.length) return null;
  return (
    <div className="card gbloco">
      <h2>Histórico de XP <small>auditável: cada linha tem origem</small></h2>
      <div className="scroll-x">
        <table className="hist">
          <tbody>
            {h.slice(0, 25).map((x) => (
              <tr key={x.id} className={x.status === 'estornado' ? 'est' : ''}>
                <td className={`v${x.valor < 0 ? ' neg' : ''}`}>{sinalXp(x.valor)}</td>
                <td>{x.motivo}{x.protocolo && <span className="mono muted"> · {x.protocolo}</span>}</td>
                <td><span className={`stx ${x.status}`}>{STATUS_XP[x.status]}</span></td>
                <td className="muted" style={{ whiteSpace: 'nowrap' }}>{quando(x.criado_em)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function Visual({ d, onMudou }: { d: Dados; onMudou: () => void }) {
  const titulos = (d.recompensas ?? []).filter((r) => r.tipo === 'titulo');
  const molduras = (d.recompensas ?? []).filter((r) => r.tipo === 'moldura');
  const [erro, setErro] = useState('');
  if (!titulos.length && !molduras.length) return null;
  async function salvar(t: number | null, m: number | null) {
    setErro('');
    try { await escolherVisual(t, m); onMudou(); } catch (e) { setErro(mensagemErro(e)); }
  }
  return (
    <div className="card gbloco">
      <h2>Recompensas</h2>
      <div className="forms">
        <label>Título no perfil
          <select className="field" value={d.perfil?.titulo?.id ?? ''} onChange={(e) => void salvar(e.target.value ? Number(e.target.value) : null, d.perfil?.moldura?.id ?? null)}>
            <option value="">Nenhum</option>
            {titulos.map((t) => <option key={t.id} value={t.id}>{t.nome} ({RARIDADES[t.raridade]})</option>)}
          </select>
        </label>
        <label>Moldura do avatar
          <select className="field" value={d.perfil?.moldura?.id ?? ''} onChange={(e) => void salvar(d.perfil?.titulo?.id ?? null, e.target.value ? Number(e.target.value) : null)}>
            <option value="">Nenhuma</option>
            {molduras.map((t) => <option key={t.id} value={t.id}>{t.nome}</option>)}
          </select>
        </label>
      </div>
      {(d.recompensas ?? []).filter((r) => r.tipo === 'destaque').map((r) => <p key={r.id} className="banner" style={{ margin: 0 }}>Destaque: <b>{r.nome}</b> · {r.descricao}</p>)}
      {erro && <p className="erro" role="alert">{erro}</p>}
    </div>
  );
}

function Estatisticas({ d }: { d: Dados }) {
  const e = d.estatisticas;
  if (!e) return null;
  const itens: [string, string, string][] = [
    ['Resolvidos', String(e.resolvidos), 'na temporada'],
    ['SLA', pct(e.sla), 'resolvidos no prazo'],
    ['Tempo médio', e.tempo_medio_h !== null ? `${e.tempo_medio_h.toLocaleString('pt-BR')} h` : '—', 'de assumir a resolver'],
    ['Satisfação', e.satisfacao !== null ? `${e.satisfacao.toLocaleString('pt-BR')} / 5` : '—', 'média das avaliações'],
    ['Reabertura', pct(e.reabertura), 'dos resolvidos'],
    ['XP total', fmtXp(d.perfil?.xp ?? 0), 'confirmado'],
  ];
  const comp: [string, number][] = [['Qualidade', e.componentes.qualidade], ['SLA', e.componentes.sla], ['Satisfação', e.componentes.satisfacao],
    ['Produtividade', e.componentes.produtividade], ['Colaboração', e.componentes.colaboracao]];
  return (
    <div className="card gbloco">
      <h2>Estatísticas <small>temporada atual</small></h2>
      <div className="forms">
        {itens.map(([k, v, s]) => <div key={k} className="seq"><small>{k}</small><b style={{ fontSize: 20 }}>{v}</b><small>{s}</small></div>)}
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        <small className="muted">Componentes do Performance Score (já suavizados pela média do time)</small>
        {comp.map(([k, v]) => (
          <div key={k} className="cq"><span style={{ width: 110, fontSize: 13 }}>{k}</span><div><Barra valor={v} rotulo={`${k}: ${pct(v)}`} fina /></div><span className="mono" style={{ width: 44, textAlign: 'right', fontSize: 13 }}>{pct(v)}</span></div>
        ))}
      </div>
    </div>
  );
}

/** "Minha jornada" (pessoaId vazio) ou perfil de um colega (pessoaId). */
export function Jornada({ dados, pessoaId, onLer, onAtualizar, onRanking, onPerfil, onVoltar }: {
  dados?: Dados | null; pessoaId?: string; onLer?: () => void; onAtualizar?: () => void;
  onRanking?: () => void; onPerfil?: (id: string) => void; onVoltar?: () => void;
}) {
  const [outro, setOutro] = useState<Dados | null>(null);
  const [rank, setRank] = useState<LinhaRanking[]>([]);
  const [erro, setErro] = useState('');
  const d = pessoaId ? outro : dados;

  useEffect(() => {
    if (!pessoaId) return;
    setOutro(null);
    lerJornada(pessoaId).then(setOutro).catch((e) => setErro(mensagemErro(e)));
  }, [pessoaId]);
  useEffect(() => { lerRanking('temporada', 'score').then((r) => setRank(r.linhas)).catch(() => undefined); }, [d?.perfil?.xp]);

  if (erro) return <p className="erro" role="alert">{erro}</p>;
  if (!d) return <div className="carregando">Carregando…</div>;
  if (!d.participa || !d.perfil || !d.pessoa) return <p className="muted">Sem dados de gamificação para esta pessoa.</p>;

  return (
    <section>
      {pessoaId ? (
        <div className="card perfil-top">
          <Avatar nome={d.pessoa.nome} moldura={d.perfil.moldura?.codigo} grande />
          <div style={{ flex: 1, minWidth: 0 }}>
            {d.perfil.titulo && <div className="tit">{d.perfil.titulo.nome}</div>}
            <h1>{d.pessoa.nome}</h1>
            <div className="sub">{d.pessoa.cargo} · Nível {d.perfil.nivel.nivel} ({d.perfil.nivel.nome})</div>
          </div>
          {onVoltar && <button type="button" className="btn sec" onClick={onVoltar}>← Voltar</button>}
        </div>
      ) : (
        <div className="ph">
          <div>
            <div className="sub">{d.temporada ? `${d.temporada.nome} · até ${new Date(`${d.temporada.fim}T12:00:00`).toLocaleDateString('pt-BR')}` : 'Sem temporada ativa'}</div>
            <h1>Minha jornada</h1>
          </div>
          {d.perfil.titulo && <span className="pill rarp rar-epica" title="Título ativo">{d.perfil.titulo.nome}</span>}
        </div>
      )}
      <Cards d={d} />
      <div className="ggrid">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
          <Missoes d={d} />
          <Proximas d={d} />
          <Medalhas d={d} />
          {d.historico && <Historico d={d} />}
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
          {d.feed && <Feed d={d} onLer={onLer} />}
          <RankingMini linhas={rank} onRanking={onRanking} onPerfil={onPerfil} />
          <Sequencias d={d} />
          <Estatisticas d={d} />
          {!pessoaId && onAtualizar && <Visual d={d} onMudou={onAtualizar} />}
          {(d.temporadas ?? []).length > 0 && (
            <div className="card gbloco">
              <h2>Temporadas anteriores</h2>
              {d.temporadas!.map((t) => <div key={t.nome} className="cq"><IconeGam nome="trofeu" /><div><b>{t.nome}</b><small>{t.posicao}º lugar{t.score !== null ? ` · score ${t.score}` : ''}</small></div></div>)}
            </div>
          )}
        </div>
      </div>
    </section>
  );
}
