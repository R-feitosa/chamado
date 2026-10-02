import { useMemo, useState } from 'react';
import { duracao } from '../lib/analytics';
import { titulo } from '../lib/formato';
import type { Catalogo, Chamado, Pessoa } from '../lib/tipos';
import { PilulaUrgencia } from '../componentes/Urgencia';
import { MiniPrints } from '../componentes/MiniPrints';
import { Ampliar } from '../componentes/Ampliar';

type Filtro = 'abertos' | 'resolvidos' | 'todos';
const FILTROS: { chave: Filtro; nome: string }[] = [
  { chave: 'abertos', nome: 'Em aberto' }, { chave: 'resolvidos', nome: 'Resolvidos' }, { chave: 'todos', nome: 'Todos' },
];
const passa = (f: Filtro, c: Chamado) => f === 'todos' || (f === 'resolvidos') === (c.status === 'resolvido');

/** Chamados abertos pelo próprio usuário, com situação e tempo. */
export function MeusChamados({ eu, catalogo, chamados, onAbrir }: { eu: Pessoa; catalogo: Catalogo; chamados: Chamado[]; onAbrir: () => void }) {
  const [filtro, setFiltro] = useState<Filtro>('abertos');
  const [ampliado, setAmpliado] = useState<string | null>(null);
  const pessoa = useMemo(() => new Map(catalogo.pessoas.map((p) => [p.id, p.nome])), [catalogo]);
  const sistema = useMemo(() => new Map(catalogo.sistemas.map((s) => [s.id, s.nome])), [catalogo]);

  const meus = chamados.filter((c) => c.solicitante_id === eu.id);
  const lista = meus.filter((c) => passa(filtro, c)).sort((a, b) => b.criado_em.localeCompare(a.criado_em));
  const agora = Date.now();

  return (
    <section>
      <div className="ph"><div><div className="sub">Acompanhe o andamento</div><h1>Meus chamados</h1></div></div>
      <div className="card fila">
        <div className="fh">
          <h2>{meus.filter((c) => c.status !== 'resolvido').length} em aberto</h2>
          <div className="tabs" role="group" aria-label="Filtrar">
            {FILTROS.map((f) => (
              <button key={f.chave} type="button" className="tab" aria-pressed={filtro === f.chave} aria-selected={filtro === f.chave} onClick={() => setFiltro(f.chave)}>
                {f.nome}<span className="n">{meus.filter((c) => passa(f.chave, c)).length}</span>
              </button>
            ))}
          </div>
        </div>
        <div className="row head"><span>Protocolo</span><span>Chamado</span><span>Sistema</span><span>Urgência</span><span>Tempo</span><span>Situação</span></div>
        {!lista.length ? (
          <div className="empty">
            {meus.length ? 'Nada neste filtro.' : <>Você ainda não abriu chamados. <button type="button" className="mini go" onClick={onAbrir}>Abrir chamado</button></>}
          </div>
        ) : lista.map((c) => {
          const res = c.status === 'resolvido';
          const fim = res && c.resolvido_em ? new Date(c.resolvido_em).getTime() : agora;
          const resp = c.responsavel_id ? pessoa.get(c.responsavel_id) : null;
          return (
            <div className="row" key={c.id}>
              <span className="mono muted id" style={{ fontSize: 13 }}>{c.protocolo}</span>
              <div style={{ minWidth: 0 }}>
                <div className={`t${res ? ' res' : ''}`} title={c.descricao}>{titulo(c.descricao)}</div>
                <div className="sub">Aberto em {new Date(c.criado_em).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })}</div>
                <MiniPrints caminhos={c.prints} onAmpliar={setAmpliado} />
              </div>
              <span className="sys">{sistema.get(c.sistema_id) ?? '—'}</span>
              <PilulaUrgencia u={c.urgencia} />
              <span className="idade" title={res ? 'Tempo total até resolver' : 'Tempo desde a abertura'}>{duracao(fim - new Date(c.criado_em).getTime())}</span>
              <div>
                {res ? <span className="pill u0"><i className="dot" />Resolvido</span>
                  : resp ? <><span className="pill" style={{ background: 'var(--accent-soft)', color: 'var(--accent-ink)' }}><i className="dot" />Em andamento</span><div className="sub" style={{ marginTop: 4 }}>com {resp}</div></>
                  : <span className="pill" style={{ background: 'var(--soft)', color: 'var(--ink2)' }}><i className="dot" />Aguardando o time</span>}
              </div>
            </div>
          );
        })}
      </div>
      {ampliado && <Ampliar src={ampliado} onFechar={() => setAmpliado(null)} />}
    </section>
  );
}
