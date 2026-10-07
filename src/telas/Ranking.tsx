import { useEffect, useRef, useState } from 'react';
import { LayoutGroup, motion, useReducedMotion } from 'motion/react';
import { ranking as lerRanking } from '../lib/apiGam';
import { CRITERIOS, fmtXp, PERIODOS, pct, type Criterio, type Periodo, type Ranking as Dados } from '../lib/gamificacao';
import { mensagemErro } from '../lib/formato';
import { Avatar } from './Jornada';

type Linha = Dados['linhas'][number];
const MEDALHA = ['ouro', 'prata', 'bronze'] as const;

/** Pódio dos 3 primeiros: 2º à esquerda, 1º no centro (mais alto), 3º à direita, nas cores ouro, prata e bronze. */
function Podio({ linhas, valor, onPerfil }: { linhas: Linha[]; valor: (l: Linha) => string; onPerfil: (id: string) => void }) {
  const top = linhas.slice(0, 3);
  if (!top.length) return null;
  const ordem = [top[1], top[0], top[2]].filter(Boolean) as Linha[];
  const provisorio = top.some((l) => !l.classificado);
  return (
    <div className="podio-bloco">
      <ol className="podio" aria-label="Pódio">
        {ordem.map((l) => {
          const m = MEDALHA[l.posicao - 1] ?? 'bronze';
          return (
            <li key={l.pessoa_id} className={`degrau d${l.posicao} ${m}${l.eu ? ' voce' : ''}`}>
              <button type="button" className="podio-quem" onClick={() => onPerfil(l.pessoa_id)} title={`${l.posicao}º lugar · ver perfil`}>
                <span className="podio-medalha" aria-hidden="true">{l.posicao}</span>
                <Avatar nome={l.nome} moldura={l.moldura} />
                <b>{l.eu ? `${l.nome.split(' ')[0]} (você)` : l.nome}</b>
                <small>{valor(l)}</small>
              </button>
              <div className="podio-base"><span className="podio-num">{l.posicao}º</span></div>
            </li>
          );
        })}
      </ol>
      {provisorio && <p className="muted podio-nota">Pódio provisório: ainda sem o mínimo de chamados resolvidos para a classificação oficial.</p>}
    </div>
  );
}

/** Leaderboard: período × critério (padrão: Performance Score), temporadas encerradas congeladas. */
export function Ranking({ temporadas, onPerfil }: { temporadas: { id: number; nome: string; status: string }[]; onPerfil: (id: string) => void }) {
  const reduzir = useReducedMotion();
  const [periodo, setPeriodo] = useState<Periodo>('temporada');
  const [criterio, setCriterio] = useState<Criterio>('score');
  const [temporada, setTemporada] = useState<number | null>(null);
  const [dados, setDados] = useState<Dados | null>(null);
  const [erro, setErro] = useState('');
  const anterior = useRef<Map<string, number>>(new Map());

  useEffect(() => {
    let vivo = true;
    setErro('');
    lerRanking(periodo, criterio, temporada).then((d) => {
      if (!vivo) return;
      setDados((velho) => { anterior.current = new Map((velho?.linhas ?? []).map((l) => [l.pessoa_id, l.posicao])); return d; });
    }).catch((e) => vivo && setErro(mensagemErro(e)));
    return () => { vivo = false; };
  }, [periodo, criterio, temporada]);

  const ajuda = CRITERIOS.find((c) => c.chave === criterio)?.ajuda;
  const valor = (l: Linha) =>
    criterio === 'xp' ? `${fmtXp(l.xp)} XP` : criterio === 'resolvidos' ? String(l.resolvidos)
      : criterio === 'score' ? (l.score !== null ? Math.round(l.score).toString() : '—') : pct(l.valor ?? null);

  return (
    <section>
      <div className="ph"><div><div className="sub">Score composto: qualidade, SLA, satisfação, produtividade e colaboração</div><h1>Ranking</h1></div></div>
      <div className="filtros">
        <select aria-label="Temporada" value={temporada ?? ''} onChange={(e) => setTemporada(e.target.value ? Number(e.target.value) : null)}>
          <option value="">Ao vivo</option>
          {temporadas.filter((t) => t.status === 'encerrada').map((t) => <option key={t.id} value={t.id}>{t.nome} (encerrada)</option>)}
        </select>
        {!temporada && (
          <>
            <div className="tabs" role="group" aria-label="Período">
              {PERIODOS.map((p) => <button key={p.chave} type="button" className="tab" aria-pressed={periodo === p.chave} aria-selected={periodo === p.chave} onClick={() => setPeriodo(p.chave)}>{p.nome}</button>)}
            </div>
            <select aria-label="Critério" value={criterio} onChange={(e) => setCriterio(e.target.value as Criterio)}>
              {CRITERIOS.map((c) => <option key={c.chave} value={c.chave}>{c.nome}</option>)}
            </select>
          </>
        )}
      </div>
      <p className="muted" style={{ marginTop: -6, fontSize: 13 }}>{temporada ? 'Ranking congelado no encerramento da temporada.' : ajuda}
        {!temporada && criterio === 'score' && dados?.minimo ? ` Mínimo de ${dados.minimo} resolvidos no período para ser classificado.` : ''}</p>
      {erro && <p className="erro" role="alert">{erro}</p>}
      {dados && <Podio linhas={dados.linhas} valor={valor} onPerfil={onPerfil} />}
      <div className="card fila">
        <div className="rk head"><span>#</span><span>Técnico</span><span>{CRITERIOS.find((c) => c.chave === (dados?.congelado ? 'score' : criterio))?.nome}</span><span className="opt">XP</span><span>SLA</span><span className="opt">Resolvidos</span><span className="opt">Satisfação</span></div>
        <LayoutGroup>
          {(dados?.linhas ?? []).map((l) => {
            const antes = anterior.current.get(l.pessoa_id);
            const subiu = antes !== undefined && antes > l.posicao;
            return (
              <motion.div layout={!reduzir} key={l.pessoa_id} className={`rk${l.eu ? ' voce' : ''}${l.classificado ? '' : ' fora'}`}
                initial={false} animate={subiu && !reduzir ? { backgroundColor: ['var(--ok-soft)', 'rgba(0,0,0,0)'] } : undefined} transition={{ duration: 1.2 }}>
                <span className={`pos p${l.posicao}${l.posicao <= 3 ? ` med ${MEDALHA[l.posicao - 1]}` : ''}`}
                  title={l.classificado ? `${l.posicao}º lugar` : `${l.posicao}º lugar (em formação: ainda sem o mínimo de chamados)`}>
                  {l.posicao}º{subiu && <span className="sr"> (subiu)</span>}
                </span>
                <span className="quem">
                  <Avatar nome={l.nome} moldura={l.moldura} />
                  <button type="button" onClick={() => onPerfil(l.pessoa_id)} title="Ver perfil">
                    <b>{l.eu ? `${l.nome} (você)` : l.nome}</b>
                    <small>{l.titulo ?? (l.nivel ? `Nível ${l.nivel}` : '')}{!l.classificado ? ' · em formação' : ''}</small>
                  </button>
                </span>
                <span className="destaque">{valor(l)}</span>
                <span className="opt">{fmtXp(l.xp)}</span>
                <span>{pct(l.sla)}</span>
                <span className="opt">{l.resolvidos}</span>
                <span className="opt">{l.satisfacao === null || l.satisfacao === undefined ? '—' : dados?.congelado ? pct(l.satisfacao) : `${Number(l.satisfacao).toLocaleString('pt-BR')} / 5`}</span>
              </motion.div>
            );
          })}
        </LayoutGroup>
        {dados && !dados.linhas.length && <div className="empty">Sem dados no período.</div>}
      </div>
    </section>
  );
}
